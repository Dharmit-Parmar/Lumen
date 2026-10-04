import Cocoa
import SystemExtensions

class AppDelegate: NSObject, NSApplicationDelegate, OSSystemExtensionRequestDelegate {
    var window: NSWindow!
    private let imageView = NSImageView()
    private var receiver: H264StreamReceiver?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.title = "Lumen Host App"
        
        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        
        let btn = NSButton(title: "Install Virtual Camera to macOS", target: self, action: #selector(installExtension))
        btn.frame = NSRect(x: 20, y: 20, width: 250, height: 30)
        content.addSubview(btn)
        
        imageView.frame = NSRect(x: 0, y: 60, width: 1280, height: 660)
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(imageView)
        
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        receiver = H264StreamReceiver { [weak self] buffer in
            guard let buffer = buffer else { return }
            let ciImage = CIImage(cvPixelBuffer: buffer)
            let rep = NSCIImageRep(ciImage: ciImage)
            let img = NSImage(size: rep.size)
            img.addRepresentation(rep)
            DispatchQueue.main.async {
                self?.imageView.image = img
            }
        }
        receiver?.start()
    }

    @objc func installExtension() {
        let extensionIdentifier = "com.example.lumen.extension"
        let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extensionIdentifier, queue: .main)
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        return .replace
    }
    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        print("Extension needs user approval. Open System Settings -> Privacy & Security to allow it.")
        let alert = NSAlert()
        alert.messageText = "Approval Required"
        alert.informativeText = "Please open System Settings > Privacy & Security and click 'Allow' for the Lumen Camera Extension."
        alert.runModal()
    }
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        let alert = NSAlert()
        alert.messageText = "Success!"
        alert.informativeText = "Virtual Camera installed successfully! You may need to restart apps like Zoom to see it."
        alert.runModal()
    }
    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let alert = NSAlert()
        alert.messageText = "Installation Failed"
        alert.informativeText = "Error: \(error.localizedDescription)\n\nNote: Because this is a local build without a paid Apple Developer certificate, you MUST run 'systemextensionsctl developer on' in terminal and disable SIP for it to install."
        alert.runModal()
    }
}

@main
struct MainApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
