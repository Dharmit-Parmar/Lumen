import CoreMedia
import CoreImage
import CoreVideo
import Foundation
import VideoToolbox

final class H264StreamReceiver {
    private let queue = DispatchQueue(label: "com.example.Lumen.stream-receiver")
    private let stateLock = NSLock()
    private let frameHandler: (CVPixelBuffer?) -> Void
    private var running = false
    private var socket: Int32 = -1
    private var decoder: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private var configured = false
    private var sawKeyframe = false
    private var rotation = 0
    private var mirror = false
    private var decodeStartedAt: UInt64 = 0
    private var receivedFrameCount = 0
    private var decodedFrameCount = 0
    private let outputContext = CIContext()
    private var outputPool: CVPixelBufferPool?

    init(frameHandler: @escaping (CVPixelBuffer?) -> Void) {
        self.frameHandler = frameHandler
        let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: 2]
        let bufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: 1280,
            kCVPixelBufferHeightKey as String: 720,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as CFDictionary, bufferAttributes as CFDictionary, &outputPool)
    }

    func start() {
        stateLock.lock()
        guard !running else { stateLock.unlock(); return }
        running = true
        stateLock.unlock()
        queue.async { self.connectAndReceive() }
    }

    func stop() {
        stateLock.lock()
        running = false
        let descriptor = socket
        socket = -1
        stateLock.unlock()
        if descriptor >= 0 {
            shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
        }
        queue.sync {
            self.resetDecoder()
            self.frameHandler(nil)
        }
    }

    private var isRunning: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return running
    }

    private func connectAndReceive() {
        var backoff: TimeInterval = 0.25
        while isRunning {
            do {
                let descriptor = try connectToPhone()
                stateLock.lock()
                guard running else { stateLock.unlock(); Darwin.close(descriptor); return }
                socket = descriptor
                stateLock.unlock()
                var timeout = timeval(tv_sec: 1, tv_usec: 0)
                _ = setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                try receiveMessages(descriptor)
                backoff = 0.25
            } catch {
                if isRunning { print("Lumen stream: \(error)") }
            }
            closeCurrentSocket()
            resetDecoder()
            frameHandler(nil)
            if isRunning {
                var remaining = backoff
                while isRunning && remaining > 0 {
                    let pause = min(remaining, 0.05)
                    Thread.sleep(forTimeInterval: pause)
                    remaining -= pause
                }
                backoff = min(backoff * 2, 3)
            }
        }
    }

    private func connectToPhone() throws -> Int32 {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw streamError("socket failed") }
        var noDelay: Int32 = 1
        _ = setsockopt(descriptor, IPPROTO_TCP, TCP_NODELAY, &noDelay, socklen_t(MemoryLayout<Int32>.size))
        var bufferSize: Int32 = 64 * 1024
        _ = setsockopt(descriptor, SOL_SOCKET, SO_SNDBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size))
        _ = setsockopt(descriptor, SOL_SOCKET, SO_RCVBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(5000).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(descriptor)
            throw streamError("connect failed: \(message)")
        }
        return descriptor
    }

    private func receiveMessages(_ descriptor: Int32) throws {
        configured = false
        sawKeyframe = false
        var lastTimestamp: UInt64 = 0
        while isRunning {
            guard let header = try readExact(descriptor, count: 16, allowCleanEOF: true) else { return }
            let length = integer(header[3..<7])
            let type = header[7]
            let timestamp = integer(header[8..<16])
            guard header[0] == 0x4c, header[1] == 0x55, header[2] == 1,
                  (1...3).contains(type), length > 0, length <= 8_388_608 else {
                throw streamError("invalid stream header")
            }
            guard let payload = try readExact(descriptor, count: Int(length)) else { throw streamError("unexpected end of stream") }
            switch type {
            case 1:
                guard !configured, length <= 65_536, timestamp == 0 else { throw streamError("invalid stream config") }
                try configureDecoder(payload)
            case 2, 3:
                guard configured, timestamp >= lastTimestamp else { throw streamError("video arrived before config or timestamps moved backwards") }
                lastTimestamp = timestamp
                if type == 2 { sawKeyframe = true }
                guard sawKeyframe else { throw streamError("delta frame arrived before keyframe") }
                receivedFrameCount += 1
                if receivedFrameCount % 30 == 0 {
                    print("LumenTiming: received frame \(receivedFrameCount), \(length) bytes at host uptime \(DispatchTime.now().uptimeNanoseconds)")
                }
                try decode(payload, timestampUs: timestamp)
            default:
                throw streamError("unknown message type")
            }
        }
    }

    private func configureDecoder(_ payload: Data) throws {
        guard payload.count >= 14, payload[0] == 1 else { throw streamError("invalid video config") }
        let width = integer(payload[1..<3])
        let height = integer(payload[3..<5])
        let fps = integer(payload[5..<7])
        let configuredRotation = Int(integer(payload[7..<9]))
        let mirror = payload[9]
        let spsLength = Int(integer(payload[10..<12]))
        let ppsOffset = 12 + spsLength
        guard width == 1280, height == 720, fps > 0,
              [0, 90, 180, 270].contains(configuredRotation), mirror <= 1,
              spsLength > 0, ppsOffset + 2 <= payload.count else {
            throw streamError("unsupported dimensions or incomplete video config")
        }
        let ppsLength = Int(integer(payload[ppsOffset..<(ppsOffset + 2)]))
        guard ppsLength > 0, ppsOffset + 2 + ppsLength == payload.count else {
            throw streamError("invalid SPS/PPS sizes")
        }
        let sps = Array(payload[12..<ppsOffset])
        let pps = Array(payload[(ppsOffset + 2)..<payload.count])
        guard sps.first.map({ $0 & 0x1f }) == 7, pps.first.map({ $0 & 0x1f }) == 8 else {
            throw streamError("invalid SPS/PPS NAL units")
        }

        var description: CMVideoFormatDescription?
        let status = sps.withUnsafeBytes { spsBytes in
            pps.withUnsafeBytes { ppsBytes in
                var pointers = [spsBytes.bindMemory(to: UInt8.self).baseAddress!, ppsBytes.bindMemory(to: UInt8.self).baseAddress!]
                var sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault,
                    parameterSetCount: 2,
                    parameterSetPointers: &pointers,
                    parameterSetSizes: &sizes,
                    nalUnitHeaderLength: 4,
                    formatDescriptionOut: &description
                )
            }
        }
        guard status == noErr, let description else { throw streamError("cannot create H.264 format (\(status))") }
        resetDecoder()
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decodedFrame,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        var session: VTDecompressionSession?
        let createStatus = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: description,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )
        guard createStatus == noErr, let session else { throw streamError("cannot create video decoder (\(createStatus))") }
        formatDescription = description
        decoder = session
        configured = true
        sawKeyframe = false
        rotation = configuredRotation
        self.mirror = mirror == 1
        print("Lumen stream: configured \(width)x\(height) at \(fps) fps, rotation \(rotation), mirror \(self.mirror)")
    }

    private func decode(_ avcc: Data, timestampUs: UInt64) throws {
        guard let decoder, let formatDescription else { throw streamError("decoder is not configured") }
        decodeStartedAt = DispatchTime.now().uptimeNanoseconds
        guard !avcc.isEmpty else { throw streamError("empty H.264 access unit") }
        var block: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: avcc.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avcc.count,
            flags: 0,
            blockBufferOut: &block
        )
        guard blockStatus == noErr, let block else { throw streamError("cannot allocate compressed frame") }
        let copyStatus = avcc.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: avcc.count)
        }
        guard copyStatus == noErr else { throw streamError("cannot copy compressed frame") }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: Int64(timestampUs), timescale: 1_000_000),
            decodeTimeStamp: .invalid
        )
        var sampleSize = avcc.count
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else { throw streamError("cannot create compressed sample") }
        var flags = VTDecodeInfoFlags()
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            decoder,
            sampleBuffer: sampleBuffer,
            flags: [._1xRealTimePlayback],
            frameRefcon: nil,
            infoFlagsOut: &flags
        )
        guard decodeStatus == noErr else { throw streamError("video decode failed (\(decodeStatus))") }
    }

    fileprivate func deliver(_ pixelBuffer: CVPixelBuffer) {
        decodedFrameCount += 1
        if decodedFrameCount % 30 == 0 {
            let elapsed = (DispatchTime.now().uptimeNanoseconds - decodeStartedAt) / 1_000
            print("LumenTiming: decoder output callback after \(elapsed)us")
        }
        if rotation == 0 && !mirror {
            frameHandler(pixelBuffer)
            return
        }
        guard let outputPool else { return }
        var output: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, outputPool, &output) == kCVReturnSuccess,
              let output else { return }

        let exifOrientation: Int32 = switch rotation {
        case 90: 6
        case 180: 3
        case 270: 8
        default: 1
        }
        var image = CIImage(cvPixelBuffer: pixelBuffer).oriented(forExifOrientation: exifOrientation)
        var extent = image.extent
        image = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        extent = image.extent
        if mirror {
            image = image.transformed(by: CGAffineTransform(translationX: extent.width, y: 0).scaledBy(x: -1, y: 1))
        }
        let scale = min(1280 / image.extent.width, 720 / image.extent.height)
        image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        extent = image.extent
        let bounds = CGRect(x: 0, y: 0, width: 1280, height: 720)
        image = image.transformed(by: CGAffineTransform(translationX: bounds.midX - extent.midX, y: bounds.midY - extent.midY))
        image = image.composited(over: CIImage(color: .black).cropped(to: bounds))
        outputContext.render(image, to: output, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
        frameHandler(output)
    }

    private func resetDecoder() {
        if let decoder {
            VTDecompressionSessionWaitForAsynchronousFrames(decoder)
            VTDecompressionSessionInvalidate(decoder)
        }
        decoder = nil
        formatDescription = nil
        configured = false
        sawKeyframe = false
        rotation = 0
        mirror = false
    }

    private func closeCurrentSocket() {
        stateLock.lock()
        let descriptor = socket
        socket = -1
        stateLock.unlock()
        if descriptor >= 0 { Darwin.close(descriptor) }
    }

    private func readExact(_ descriptor: Int32, count: Int, allowCleanEOF: Bool = false) throws -> Data? {
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let received = data.withUnsafeMutableBytes { bytes in
                recv(descriptor, bytes.baseAddress!.advanced(by: offset), count - offset, 0)
            }
            if received < 0 {
                if errno == EINTR { continue }
                throw streamError("receive failed: \(String(cString: strerror(errno)))")
            }
            if received == 0 {
                if allowCleanEOF && offset == 0 { return nil }
                throw streamError("connection closed mid-message")
            }
            offset += received
        }
        return data
    }

    private func integer(_ bytes: Data.SubSequence) -> UInt64 {
        bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }

    private func streamError(_ message: String) -> NSError {
        NSError(domain: "com.example.Lumen.stream", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private let decodedFrame: VTDecompressionOutputCallback = { refcon, _, status, _, imageBuffer, _, _ in
    guard status == noErr, let refcon, let imageBuffer else { return }
    Unmanaged<H264StreamReceiver>.fromOpaque(refcon).takeUnretainedValue().deliver(imageBuffer)
}
