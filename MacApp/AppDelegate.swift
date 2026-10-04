import Cocoa
import SystemExtensions

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    private let statusLabel = NSTextField(labelWithString: "Camera extension is not installed.")
    private let installButton = NSButton(title: "Install Camera Extension", target: nil, action: nil)

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create window
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.title = "Lumen Host App"
        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        statusLabel.frame = NSRect(x: 24, y: 205, width: 432, height: 40)
        statusLabel.lineBreakMode = .byWordWrapping
        installButton.frame = NSRect(x: 24, y: 155, width: 220, height: 32)
        installButton.target = self
        installButton.action = #selector(installExtension)
        content.addSubview(statusLabel)
        content.addSubview(installButton)
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func installExtension() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            statusLabel.stringValue = "Could not determine the app identifier."
            return
        }
        installButton.isEnabled = false
        statusLabel.stringValue = "Requesting camera extension installation…"
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
        statusLabel.stringValue = "Approve Lumen Camera in System Settings → Privacy & Security."
    }
    
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            statusLabel.stringValue = "Camera extension installed. Open Photo Booth and select Lumen Camera."
        case .willCompleteAfterReboot:
            statusLabel.stringValue = "Restart your Mac to finish installing the camera extension."
        @unknown default:
            statusLabel.stringValue = "Camera extension installation finished."
        }
        installButton.isEnabled = true
    }
    
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        statusLabel.stringValue = "Installation failed: \(error.localizedDescription)"
        installButton.isEnabled = true
    }
}
