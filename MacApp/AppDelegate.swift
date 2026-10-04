import Cocoa
import SystemExtensions

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    private let imageView = NSImageView()
    private var receiver: H264StreamReceiver?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create window
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.title = "Lumen Host App"
        
        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        
        imageView.frame = content.bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(imageView)
        
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
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

}
