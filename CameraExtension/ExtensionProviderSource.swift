import Foundation
import CoreMediaIO

class ExtensionProviderSource: NSObject, CMIOExtensionProviderSource {
    let provider: CMIOExtensionProvider
    private var deviceSource: ExtensionDeviceSource?
    
    init(clientQueue: DispatchQueue? = nil) {
        self.provider = CMIOExtensionProvider(source: nil, clientQueue: clientQueue)
        super.init()
        self.provider.source = self
        
        let device = ExtensionDeviceSource(localizedName: "Lumen Camera")
        self.deviceSource = device
        do {
            try provider.addDevice(device.device)
        } catch {
            print("Failed to add device: \(error)")
        }
    }
    
    func connect(to client: CMIOExtensionClient) throws {
        // Accept all clients for Phase 1
    }
    
    func disconnect(from client: CMIOExtensionClient) {
        // Handle client disconnect
    }
    
    var availableProperties: Set<CMIOExtensionProperty> {
        return [.providerManufacturer]
    }
    
    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let dict = NSMutableDictionary()
        if properties.contains(.providerManufacturer) {
            dict[CMIOExtensionProperty.providerManufacturer.rawValue] = "Lumen"
        }
        return CMIOExtensionProviderProperties(dictionary: dict as! [String: Any])
    }
    
    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {
        // read-only
    }
}
