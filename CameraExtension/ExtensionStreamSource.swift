import Foundation
import CoreMediaIO
import CoreVideo
import CoreText

class ExtensionStreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    let formats: [CMIOExtensionStreamFormat]
    
    private let queue = DispatchQueue(label: "com.example.Lumen.videoqueue")
    private var timer: DispatchSourceTimer?
    private var isStreaming = false
    private let formatDescription: CMVideoFormatDescription
    private var pixelBufferPool: CVPixelBufferPool?
    private var latestPhoneFrame: CVPixelBuffer?
    private lazy var receiver = H264StreamReceiver { [weak self] frame in
        guard let self else { return }
        self.queue.async { self.latestPhoneFrame = frame }
    }
    
    init(localizedName: String, streamID: UUID, direction: CMIOExtensionStream.Direction, clockType: CMIOExtensionStream.ClockType, formatDescription: CMVideoFormatDescription) {
        self.formatDescription = formatDescription
        self.formats = [CMIOExtensionStreamFormat(formatDescription: formatDescription,
                                                  maxFrameDuration: CMTime(value: 1, timescale: 30),
                                                  minFrameDuration: CMTime(value: 1, timescale: 30),
                                                  validFrameDurations: nil)]
        super.init()
        self.stream = CMIOExtensionStream(localizedName: localizedName,
                                          streamID: streamID,
                                          direction: direction,
                                          clockType: clockType,
                                          source: self)
        
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 2
        ]
        let bufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1280,
            kCVPixelBufferHeightKey as String: 720,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        
        CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes as CFDictionary, bufferAttributes as CFDictionary, &pixelBufferPool)
    }
    
    static func createFormatDescription() -> CMVideoFormatDescription {
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                       codecType: kCVPixelFormatType_32BGRA,
                                       width: 1280,
                                       height: 720,
                                       extensions: nil,
                                       formatDescriptionOut: &formatDescription)
        return formatDescription!
    }
    
    var availableProperties: Set<CMIOExtensionProperty> {
        return [.streamActiveFormatIndex, .streamFrameDuration]
    }
    
    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = CMTime(value: 1, timescale: 30)
        }
        return streamProperties
    }
    
    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws { }
    
    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { return true }
    
    func startStream() throws {
        queue.async {
            guard !self.isStreaming else { return }
            self.isStreaming = true
            self.receiver.start()
            self.startPushingFrames()
        }
    }
    
    func stopStream() throws {
        queue.async {
            self.isStreaming = false
            self.timer?.cancel()
            self.timer = nil
            self.receiver.stop()
            self.latestPhoneFrame = nil
        }
    }
    
    private func startPushingFrames() {
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: 1.0 / 30.0) // 30 FPS
        timer?.setEventHandler { [weak self] in
            self?.pushCurrentFrame()
        }
        timer?.resume()
    }
    
    private func pushCurrentFrame() {
        if let frame = latestPhoneFrame {
            send(frame)
            return
        }
        pushPlaceholderFrame()
    }

    private func pushPlaceholderFrame() {
        guard let pool = pixelBufferPool else { return }
        
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        
        guard let buffer = pixelBuffer else { return }
        
        // Keep the camera preview useful while the phone connects.
        CVPixelBufferLockBaseAddress(buffer, [])
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                   width: CVPixelBufferGetWidth(buffer),
                                   height: CVPixelBufferGetHeight(buffer),
                                   bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) {
            let bounds = CGRect(x: 0, y: 0, width: context.width, height: context.height)
            context.setFillColor(CGColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1))
            context.fill(bounds)
            context.setFillColor(CGColor(red: 0.24, green: 0.62, blue: 0.96, alpha: 1))
            context.fillEllipse(in: CGRect(x: bounds.midX - 24, y: bounds.midY + 70, width: 48, height: 48))

            let text = "No phone connected"
            let attributes: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 42, nil),
                kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 1, alpha: 1)
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            context.textPosition = CGPoint(x: bounds.midX - lineWidth / 2, y: bounds.midY - 12)
            CTLineDraw(line, context)

            let instruction = "Connect an Android phone over USB to start video."
            let detailAttributes: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key: CTFontCreateWithName("HelveticaNeue" as CFString, 22, nil),
                kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 0.72, alpha: 1)
            ]
            let detailLine = CTLineCreateWithAttributedString(NSAttributedString(string: instruction, attributes: detailAttributes))
            let detailWidth = CGFloat(CTLineGetTypographicBounds(detailLine, nil, nil, nil))
            context.textPosition = CGPoint(x: bounds.midX - detailWidth / 2, y: bounds.midY - 55)
            CTLineDraw(detailLine, context)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
        send(buffer)
    }

    private func send(_ buffer: CVPixelBuffer) {
        guard CVPixelBufferGetWidth(buffer) == 1280, CVPixelBufferGetHeight(buffer) == 720 else { return }
        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                 imageBuffer: buffer,
                                                 formatDescription: formatDescription,
                                                 sampleTiming: &timing,
                                                 sampleBufferOut: &sampleBuffer)
        
        if let sbuf = sampleBuffer {
            self.stream.send(sbuf, discontinuity: [], hostTimeInNanoseconds: UInt64(timing.presentationTimeStamp.seconds * 1_000_000_000))
        }
    }
}
