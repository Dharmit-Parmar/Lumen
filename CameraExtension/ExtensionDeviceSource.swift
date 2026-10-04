import Foundation
import CoreMediaIO

class ExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private var streamSource: ExtensionStreamSource!
    
    init(localizedName: String) {
        let deviceID = UUID()
        super.init()
        self.device = CMIOExtensionDevice(localizedName: localizedName, deviceID: deviceID, legacyDeviceID: nil, source: self)
        
        let streamFormat = ExtensionStreamSource.createFormatDescription()
        self.streamSource = ExtensionStreamSource(localizedName: "Lumen Stream", streamID: UUID(), direction: .source, clockType: .hostTime, formatDescription: streamFormat)
        
        do {
            try device.addStream(streamSource.stream)
        } catch {
            print("Failed to add stream: \(error)")
        }
    }
    
    var availableProperties: Set<CMIOExtensionProperty> {
        return [.deviceModel]
    }
    
    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceModel) {
            deviceProperties.model = "Lumen Android Webcam"
        }
        return deviceProperties
    }
    
    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
        // read only
    }
}
