import CoreMedia
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

    init(frameHandler: @escaping (CVPixelBuffer?) -> Void) {
        self.frameHandler = frameHandler
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
                try receiveMessages(descriptor)
                backoff = 0.25
            } catch {
                if isRunning { print("Lumen stream: \(error)") }
            }
            closeCurrentSocket()
            resetDecoder()
            frameHandler(nil)
            if isRunning { Thread.sleep(forTimeInterval: backoff); backoff = min(backoff * 2, 3) }
        }
    }

    private func connectToPhone() throws -> Int32 {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw streamError("socket failed") }
        var noDelay: Int32 = 1
        _ = setsockopt(descriptor, IPPROTO_TCP, TCP_NODELAY, &noDelay, socklen_t(MemoryLayout<Int32>.size))

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
        let rotation = integer(payload[7..<9])
        let mirror = payload[9]
        let spsLength = Int(integer(payload[10..<12]))
        let ppsOffset = 12 + spsLength
        guard width == 1280, height == 720, fps > 0,
              [0, 90, 180, 270].contains(rotation), mirror <= 1,
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
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
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
        print("Lumen stream: configured \(width)x\(height) at \(fps) fps, rotation \(rotation)")
    }

    private func decode(_ annexB: Data, timestampUs: UInt64) throws {
        guard let decoder, let formatDescription else { throw streamError("decoder is not configured") }
        let units = annexBUnits(annexB)
        guard !units.isEmpty else { throw streamError("empty H.264 access unit") }
        var sample = Data()
        for unit in units {
            guard unit.count <= Int(UInt32.max) else { throw streamError("NAL unit is too large") }
            var length = UInt32(unit.count).bigEndian
            withUnsafeBytes(of: &length) { sample.append(contentsOf: $0) }
            sample.append(unit)
        }
        var block: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: sample.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: sample.count,
            flags: 0,
            blockBufferOut: &block
        )
        guard blockStatus == noErr, let block else { throw streamError("cannot allocate compressed frame") }
        let copyStatus = sample.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: sample.count)
        }
        guard copyStatus == noErr else { throw streamError("cannot copy compressed frame") }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: Int64(timestampUs), timescale: 1_000_000),
            decodeTimeStamp: .invalid
        )
        var sampleSize = sample.count
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
            flags: [._EnableAsynchronousDecompression, ._1xRealTimePlayback],
            frameRefcon: nil,
            infoFlagsOut: &flags
        )
        guard decodeStatus == noErr else { throw streamError("video decode failed (\(decodeStatus))") }
    }

    fileprivate func deliver(_ pixelBuffer: CVPixelBuffer) {
        frameHandler(pixelBuffer)
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

    private func annexBUnits(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var markers: [(Int, Int)] = []
        var index = 0
        while index + 3 < bytes.count {
            if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 0, bytes[index + 3] == 1 {
                markers.append((index, 4)); index += 4
            } else if bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 {
                markers.append((index, 3)); index += 3
            } else { index += 1 }
        }
        return markers.indices.compactMap { position in
            let start = markers[position].0 + markers[position].1
            let end = position + 1 < markers.count ? markers[position + 1].0 : bytes.count
            guard start < end else { return nil }
            return Data(bytes[start..<end])
        }
    }

    private func streamError(_ message: String) -> NSError {
        NSError(domain: "com.example.Lumen.stream", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private let decodedFrame: VTDecompressionOutputCallback = { refcon, _, status, _, imageBuffer, _, _ in
    guard status == noErr, let refcon, let imageBuffer else { return }
    Unmanaged<H264StreamReceiver>.fromOpaque(refcon).takeUnretainedValue().deliver(imageBuffer)
}
