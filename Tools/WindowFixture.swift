import AppKit

// Disposable window used only by Scripts/smoke-test.sh.
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: CGRect(x: 180, y: 220, width: 600, height: 380),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Snow Desktop — physics fixture"
        window.isReleasedWhenClosed = false
        let text = NSTextField(labelWithString: "Проверка снега на небольшом окне")
        text.frame = CGRect(x: 28, y: 280, width: 500, height: 32)
        window.contentView?.addSubview(text)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            self.window.setFrameOrigin(CGPoint(x: 380, y: 240))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
            self.window.close(); NSApp.terminate(nil)
        }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = FixtureDelegate(); app.delegate = delegate; app.run()
