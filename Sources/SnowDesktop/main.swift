import AppKit
import SnowCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover = NSPopover()
    private var overlays: OverlayController!
    private var diagnosticsTimer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.blazenibirus.SnowDesktop").count > 1 {
            NSApp.terminate(nil); return
        }
        overlays = OverlayController()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Snow Desktop — настройки снега")
            button.image?.isTemplate = true
            button.target = self; button.action = #selector(togglePopover)
            button.toolTip = "Snow Desktop"
        }
        popover.behavior = .transient; popover.animates = true; popover.delegate = self
        Settings.shared.onChange = { [weak self] in self?.overlays.preferencesChanged() }
        if let pathIndex = CommandLine.arguments.firstIndex(of: "--diagnostics"), pathIndex + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[pathIndex + 1]
            diagnosticsTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                let report: [String: Any] = ["memoryMB": Diagnostics.memoryMB(), "budgetMB": Diagnostics.budgetMB,
                    "displayHz": NSScreen.screens.map(\.maximumFramesPerSecond),
                    "dockAccess": self?.overlays.tracker.hasDockAccess ?? false,
                    "dockItems": self?.overlays.tracker.dockItemCount ?? 0,
                    "dockStatus": self?.overlays.tracker.dockStatus ?? "",
                    "dockAXError": self?.overlays.tracker.dockAXError ?? 0,
                    "scene": self?.overlays.diagnosticSnapshot ?? []]
                if let data = try? JSONSerialization.data(withJSONObject: report, options: .prettyPrinted) {
                    try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
                }
            }
        }
        if CommandLine.arguments.contains("--show-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.togglePopover() }
        }
    }
    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        if popover.contentViewController == nil {
            popover.contentViewController = SettingsPopover(tracker: overlays.tracker) { [weak self] in self?.overlays.clearSnow() }
        }
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
