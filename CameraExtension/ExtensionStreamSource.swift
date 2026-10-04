import Foundation
import CoreMediaIO
import CoreVideo

class ExtensionStreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    let formats: [CMIOExtensionStreamFormat]
    
    private let queue = DispatchQueue(label: "com.example.Lumen.videoqueue")
    private var timer: DispatchSourceTimer?
    private var isStreaming = false
    private let formatDescription: CMVideoFormatDescription
    private var latestPhoneFrame: CVPixelBuffer?
    private var displayedPhoneFrames = 0
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
        
    }
    
    static func createFormatDescription() -> CMVideoFormatDescription {
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                                       codecType: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
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
        guard let frame = latestPhoneFrame else { return }
        send(frame, fromPhone: true)
    }

    private func send(_ buffer: CVPixelBuffer, fromPhone: Bool = false) {
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
            if fromPhone {
                displayedPhoneFrames += 1
                if displayedPhoneFrames % 30 == 0 {
                    print("LumenTiming: submitted phone frame \(displayedPhoneFrames) to CoreMediaIO at host time \(DispatchTime.now().uptimeNanoseconds)")
                }
            }
        }
    }
}
