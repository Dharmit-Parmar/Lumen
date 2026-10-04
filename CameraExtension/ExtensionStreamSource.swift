import Foundation
import CoreMediaIO
import CoreVideo

class ExtensionStreamSource: NSObject, CMIOExtensionStreamSource {
    let stream: CMIOExtensionStream
    
    private let queue = DispatchQueue(label: "com.example.Lumen.videoqueue")
    private var timer: DispatchSourceTimer?
    private var isStreaming = false
    private let formatDescription: CMVideoFormatDescription
    private var pixelBufferPool: CVPixelBufferPool?
    
    init(localizedName: String, streamID: UUID, direction: CMIOExtensionStream.Direction, clockType: CMIOExtensionStream.ClockType, formatDescription: CMVideoFormatDescription) {
        self.formatDescription = formatDescription
        self.stream = CMIOExtensionStream(localizedName: localizedName, streamID: streamID, direction: direction, clockType: clockType, source: nil)
        super.init()
        self.stream.source = self
        
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
        return CMIOExtensionStreamProperties(dictionary: [:])
    }
    
    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws { }
    
    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { return true }
    
    func startStream() throws {
        queue.async {
            self.isStreaming = true
            self.startPushingFrames()
        }
    }
    
    func stopStream() throws {
        queue.async {
            self.isStreaming = false
            self.timer?.cancel()
            self.timer = nil
        }
    }
    
    private func startPushingFrames() {
        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now(), repeating: 1.0 / 30.0) // 30 FPS
        timer?.setEventHandler { [weak self] in
            self?.pushPlaceholderFrame()
        }
        timer?.resume()
    }
    
    private func pushPlaceholderFrame() {
        guard let pool = pixelBufferPool else { return }
        
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
        
        guard let buffer = pixelBuffer else { return }
        
        // Fill buffer with blue color (placeholder)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let ptr = CVPixelBufferGetBaseAddress(buffer) {
            let width = CVPixelBufferGetWidth(buffer)
            let height = CVPixelBufferGetHeight(buffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
            
            // Draw a solid color (e.g. Blue: B=255, G=0, R=0, A=255)
            memset_pattern4(ptr, [255, 0, 0, 255], bytesPerRow * height)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
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
