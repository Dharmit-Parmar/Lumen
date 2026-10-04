import Foundation
import CoreMediaIO

class ExtensionProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: ExtensionDeviceSource?
    
    init(clientQueue: DispatchQueue? = nil) {
        super.init()
        self.provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        
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
        let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            providerProperties.manufacturer = "Lumen"
        }
        return providerProperties
    }
    
    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {
        // read-only
    }
}
