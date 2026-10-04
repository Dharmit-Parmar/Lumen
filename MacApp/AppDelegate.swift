import Cocoa
import SystemExtensions

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create window
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.title = "Lumen Host App"
        window.makeKeyAndOrderFront(nil)

        // Request extension installation
        installExtension()
    }

    func installExtension() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let extensionIdentifier = bundleIdentifier + ".CameraExtension"
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extensionIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }
}

extension AppDelegate: OSSystemExtensionRequestDelegate {
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        return .replace
    }
    
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        print("Extension needs user approval")
    }
    
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        print("Extension installed successfully")
    }
    
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        print("Extension failed to install: \(error.localizedDescription)")
    }
}
