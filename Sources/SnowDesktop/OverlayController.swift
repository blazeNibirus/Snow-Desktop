import AppKit
import SnowCore

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class OverlayController {
    let tracker = WindowTracker()
    private var windows: [NSWindow] = []
    private var views: [SnowView] = []
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var lastGeometry: CFTimeInterval = 0
    private var sessionActive = true
    private var locked = false
    private var asleep = false
    private var saverRunning = false

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.asleep = true; self?.refreshState() })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.asleep = false; self?.refreshState() })
        }
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.sessionActive = false; self?.refreshState() })
        observers.append(center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.sessionActive = true; self?.refreshState() })
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.views.forEach { $0.engine.clear() }; self?.lastGeometry = 0
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.rebuild() })
        observers.append(NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.views.forEach { $0.updateRate() } })
        let distributed = DistributedNotificationCenter.default()
        // These notifications supplement workspace session events. Security never depends on them.
        for (name, flag) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            distributedObservers.append(distributed.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.locked = flag; self?.refreshState() })
        }
        for (name, flag) in [("com.apple.screensaver.didstart", true), ("com.apple.screensaver.didstop", false)] {
            distributedObservers.append(distributed.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in self?.saverRunning = flag; self?.refreshState() })
        }
        rebuild()
    }
    func rebuild() {
        views.forEach { $0.stop() }; windows.forEach { $0.close() }
        views = []; windows = []
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            window.setFrame(screen.frame, display: false)
            window.isReleasedWhenClosed = false; window.isOpaque = false; window.backgroundColor = .clear
            window.hasShadow = false; window.ignoresMouseEvents = true; window.hidesOnDeactivate = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let engine = SnowEngine(width: screen.frame.width, height: screen.frame.height)
            engine.particleLimit = max(240, 1400 / max(1, NSScreen.screens.count))
            engine.surfaceLimit = 64
            let view = SnowView(frame: CGRect(origin: .zero, size: screen.frame.size), engine: engine)
            view.applyPreferences(); engine.seedSky()
            window.contentView = view
            views.append(view); windows.append(window)
        }
        views.first?.beforeFrame = { [weak self] in self?.pollGeometry() }
        lastGeometry = 0
        refreshState()
    }
    func preferencesChanged() {
        views.forEach { $0.applyPreferences() }
        lastGeometry = 0
        refreshState()
    }
    private func refreshState() {
        let active = Settings.shared.value.enabled && sessionActive && !locked && !asleep && !saverRunning
        for (window, view) in zip(windows, views) {
            if active { window.orderFrontRegardless(); view.start() }
            else { view.stop(); window.orderOut(nil) }
        }
        if !active { views.forEach { $0.engine.clearAccumulation() } }
    }
    private func pollGeometry() {
        let now = CACurrentMediaTime()
        let dragging = NSEvent.pressedMouseButtons & 1 != 0
        let interval = dragging ? 1.0 / 30 : 1.0 / 10
        guard now - lastGeometry >= interval else { return }
        let elapsed = lastGeometry == 0 ? interval : now - lastGeometry
        lastGeometry = now
        let geometry = tracker.snapshot(preferences: Settings.shared.value)
        for (view, info) in zip(views, geometry) {
            view.engine.blockers = info.blockers
            view.engine.updateSurfaces(info.surfaces, elapsed: elapsed)
            view.updateVisibilityMask()
        }
    }
    var diagnosticSnapshot: [[String: Any]] {
        views.enumerated().map { index, view in
            ["display": index, "particles": view.engine.particles.count,
             "surfaces": view.engine.piles.count,
             "snowVolume": view.engine.piles.values.reduce(0) { $0 + $1.volume },
             "fullscreenBlockers": view.engine.blockers.count]
        }
    }
    func clearSnow() { views.forEach { $0.engine.clearAccumulation() } }
    deinit {
        views.forEach { $0.stop() }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }
}
