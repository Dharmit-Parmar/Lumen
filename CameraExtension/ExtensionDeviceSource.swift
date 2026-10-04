import Foundation
import CoreMediaIO

class ExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {
    let device: CMIOExtensionDevice
    private var streamSource: ExtensionStreamSource!
    
    init(localizedName: String) {
        let deviceID = UUID()
        self.device = CMIOExtensionDevice(localizedName: localizedName, deviceID: deviceID, legacyDeviceID: nil, source: nil)
        super.init()
        self.device.source = self
        
        let streamFormat = ExtensionStreamSource.createFormatDescription()
        self.streamSource = ExtensionStreamSource(localizedName: "Lumen Stream", streamID: UUID(), direction: .source, clockType: .hostTime, formatDescription: streamFormat)
        
        do {
            try device.addStream(streamSource.stream)
        } catch {
            print("Failed to add stream: \(error)")
        }
    }
    
    var availableProperties: Set<CMIOExtensionProperty> {
        return [.deviceModel, .deviceName]
    }
    
    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let dict = NSMutableDictionary()
        if properties.contains(.deviceModel) {
            dict[CMIOExtensionProperty.deviceModel.rawValue] = "Lumen Android Webcam"
        }
        if properties.contains(.deviceName) {
            dict[CMIOExtensionProperty.deviceName.rawValue] = "Lumen Camera"
        }
        return CMIOExtensionDeviceProperties(dictionary: dict as! [String: Any])
    }
    
    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
        // read only
    }
}
