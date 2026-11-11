import AppKit
import ApplicationServices
import SnowCore

struct DisplayGeometry {
    var frame: CGRect
    var workArea: CGRect
    var surfaces: [SurfaceDescriptor]
    var blockers: [SnowRect]
    var windowAreas: [SnowRect]
}

final class WindowTracker {
    private var dockPID: pid_t = 0
    private var dockRoot: AXUIElement?
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var lastDockRects: [CGRect] = []
    private var lastAXRead: CFTimeInterval = 0
    private var axReadInFlight = false
    private let dockQueue = DispatchQueue(label: "com.blazenibirus.SnowDesktop.DockGeometry", qos: .utility)
    private(set) var dockStatus = "Проверка доступа к Dock…"
    private(set) var dockItemCount = 0
    private(set) var dockAXError: Int32 = 0
    var hasDockAccess: Bool { AXIsProcessTrusted() || dockItemCount > 0 }

    func requestDockAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        lastAXRead = 0
    }
    private func cgFrame(_ screen: NSScreen) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        return CGRect(x: screen.frame.minX, y: mainHeight - screen.frame.maxY,
                      width: screen.frame.width, height: screen.frame.height)
    }
    private func workFrame(_ screen: NSScreen) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        return CGRect(x: screen.visibleFrame.minX, y: mainHeight - screen.visibleFrame.maxY,
                      width: screen.visibleFrame.width, height: screen.visibleFrame.height)
    }
    func snapshot(preferences: Preferences) -> [DisplayGeometry] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var windows: [(id: UInt64, rect: CGRect)] = []
        for w in list {
            guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let dict = w[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary), rect.width > 90, rect.height > 55,
                  let id = w[kCGWindowNumber as String] as? UInt64 else { continue }
            // Accessory controls and transient duplicate render windows are not shelves.
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .prohibited { continue }
            if windows.contains(where: { $0.rect == rect }) { continue }
            windows.append((id, rect))
            if windows.count == 96 { break }
        }
        let dock = preferences.onDock ? dockRects() : []
        let dockDomain = "com.apple.dock" as CFString
        let bottomDock = (CFPreferencesCopyAppValue("orientation" as CFString, dockDomain) as? String ?? "bottom") == "bottom"
        let autoHidden = (CFPreferencesCopyAppValue("autohide" as CFString, dockDomain) as? Bool) ?? false
        return NSScreen.screens.map { screen in
            let frame = cgFrame(screen), work = workFrame(screen)
            func local(_ rect: CGRect) -> SnowRect {
                SnowRect(x: rect.minX - frame.minX, y: rect.minY - frame.minY, width: rect.width, height: rect.height)
            }
            var surfaces: [SurfaceDescriptor] = []
            var blockers: [SnowRect] = []
            var occluders: [CGRect] = []
            for window in windows where window.rect.intersects(frame) {
                let r = window.rect
                let fullscreen = local(r).covers(local(work)) || local(r).covers(local(frame))
                if fullscreen {
                    var visibleParts = [local(r)]
                    for cover in occluders {
                        let front = local(cover.insetBy(dx: 0, dy: -14))
                        visibleParts = visibleParts.flatMap { $0.subtracting(front) }
                    }
                    blockers.append(contentsOf: visibleParts)
                }
                if !fullscreen, preferences.onWindows, r.minY >= frame.minY + 1, r.minY < frame.maxY {
                    var spans = [Span(max(r.minX + 7, frame.minX) - frame.minX,
                                      min(r.maxX - 7, frame.maxX) - frame.minX)]
                    for cover in occluders where cover.minY <= r.minY && cover.maxY > r.minY {
                        spans = spans.flatMap { $0.subtracting(Span(cover.minX - frame.minX, cover.maxX - frame.minX)) }
                    }
                    surfaces.append(SurfaceDescriptor(id: window.id, x: r.minX + 7 - frame.minX,
                        y: r.minY - frame.minY, width: max(2, r.width - 14), visible: spans, occluders: occluders.map(local)))
                }
                occluders.append(r)
            }
            if preferences.onDock {
                let dockSurfaces = DockLayout.surfaces(frame: local(frame), workArea: local(work),
                    icons: dock.map(local), fullWidth: preferences.fullWidthDock,
                    bottomDock: bottomDock, autoHidden: autoHidden).map { shelf in
                        var shelf = shelf; shelf.occluders = windows.map { local($0.rect) }; return shelf
                    }
                surfaces.insert(contentsOf: dockSurfaces, at: 0)
            }
            return DisplayGeometry(frame: frame, workArea: work, surfaces: surfaces,
                blockers: blockers, windowAreas: windows.map { local($0.rect) })
        }
    }
    private func dockRects() -> [CGRect] {
        let now = CACurrentMediaTime()
        guard !axReadInFlight, now - lastAXRead >= (dockAXError == AXError.apiDisabled.rawValue ? 2.0 : 1.0 / 24) else { return lastDockRects }
        lastAXRead = now; axReadInFlight = true
        let frames = NSScreen.screens.map { cgFrame($0) }
        dockQueue.async { [weak self] in
            guard let self else { return }
            let result = self.readDockRects(screenFrames: frames)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lastDockRects = result.rects; self.axReadInFlight = false
                self.dockItemCount = result.rects.count; self.dockAXError = result.error
                if !result.rects.isEmpty { self.dockStatus = "Dock: точные границы, \(result.rects.count) значков" }
                else if result.error == AXError.apiDisabled.rawValue {
                    self.dockStatus = "macOS не допускает текущую сборку к Dock. После обновления перевыберите Snow Desktop в «Универсальном доступе»."
                } else { self.dockStatus = "Dock пока не найден (AX: \(result.error)). Вся ширина работает по системной границе Dock." }
            }
        }
        return lastDockRects
    }
    private func readDockRects(screenFrames: [CGRect]) -> (rects: [CGRect], error: Int32) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return ([], AXError.cannotComplete.rawValue) }
        if dockPID != app.processIdentifier {
            dockPID = app.processIdentifier; dockRoot = AXUIElementCreateApplication(dockPID)
            if let root = dockRoot { AXUIElementSetMessagingTimeout(root, 0.015) }
        }
        guard let root = dockRoot else { return ([], AXError.invalidUIElement.rawValue) }
        var result: [CGRect] = []
        var rootError: Int32 = 0
        var remaining = 256
        func read(_ item: AXUIElement, depth: Int) {
            guard depth < 8, remaining > 0 else { return }
            remaining -= 1
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXRoleAttribute as CFString, &roleValue)
            let role = roleValue as? String ?? ""
            var subroleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXSubroleAttribute as CFString, &subroleValue)
            let subrole = subroleValue as? String ?? ""
            if role == "AXDockItem" || subrole.hasSuffix("DockItem") {
                var position: CFTypeRef?, size: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &position)
                AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size)
                if let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
                    var point = CGPoint.zero, dimensions = CGSize.zero
                    AXValueGetValue(position as! AXValue, .cgPoint, &point)
                    AXValueGetValue(size as! AXValue, .cgSize, &dimensions)
                    if dimensions.width > 8, dimensions.height > 8 {
                        result.append(CGRect(origin: point, size: dimensions))
                    }
                }
                return
            }
            var children: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(item, kAXChildrenAttribute as CFString, &children)
            if depth == 0 { rootError = error.rawValue }
            if error == .success, let elements = children as? [AXUIElement] {
                for child in elements { read(child, depth: depth + 1) }
            }
        }
        read(root, depth: 0)
        // An auto-hidden Dock has no onscreen shelf; do not create a bottom-screen floor.
        let visible = result.filter { rect in
            screenFrames.contains { f in
                rect.minY < f.maxY - 2 && rect.intersection(f).height > 8
            }
        }
        return (visible, rootError)
    }
}
