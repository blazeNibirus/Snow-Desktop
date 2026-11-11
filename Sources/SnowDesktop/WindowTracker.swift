import AppKit
import ApplicationServices
import SnowCore

struct DisplayGeometry {
    var frame: CGRect
    var workArea: CGRect
    var surfaces: [SurfaceDescriptor]
    var blockers: [SnowRect]
}

final class WindowTracker {
    private var dockPID: pid_t = 0
    private var dockRoot: AXUIElement?
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var lastDockRects: [CGRect] = []
    private var lastAXRead: CFTimeInterval = 0
    private var axReadInFlight = false
    private let dockQueue = DispatchQueue(label: "com.blazenibirus.SnowDesktop.DockGeometry", qos: .utility)
    var hasDockAccess: Bool { AXIsProcessTrusted() }

    func requestDockAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
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
            windows.append((id, rect))
            if windows.count == 96 { break }
        }
        let dock = preferences.onDock ? dockRects() : []
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
                if fullscreen { blockers.append(local(r)) }
                if !fullscreen, preferences.onWindows, r.minY >= frame.minY + 1, r.minY < frame.maxY {
                    var spans = [Span(max(r.minX + 7, frame.minX) - frame.minX,
                                      min(r.maxX - 7, frame.maxX) - frame.minX)]
                    for cover in occluders where cover.minY < r.minY + 1 && cover.maxY > r.minY - 14 {
                        spans = spans.flatMap { $0.subtracting(Span(cover.minX - frame.minX - 1, cover.maxX - frame.minX + 1)) }
                    }
                    surfaces.append(SurfaceDescriptor(id: window.id, x: r.minX + 7 - frame.minX,
                        y: r.minY - frame.minY, width: max(2, r.width - 14), visible: spans))
                }
                occluders.append(r)
            }
            let icons = dock.filter { $0.intersects(frame) }
            if !icons.isEmpty {
                let union = icons.reduce(CGRect.null) { $0.union($1) }
                // Horizontal Dock only. Vertical Dock has no horizontal collecting shelf.
                let isBottom = union.midY > frame.maxY - max(180, union.height * 2) && union.width > union.height * 1.8
                if isBottom {
                    let baseY = icons.map(\.minY).max()! - 5
                    if preferences.fullWidthDock {
                        surfaces.append(SurfaceDescriptor(id: UInt64.max - 1, x: 0, y: baseY - frame.minY,
                                                           width: frame.width, kind: .dock))
                    } else {
                        // Each icon pushes the snow up during magnification. Flat gaps form the shelf.
                        let left = max(frame.minX, union.minX - 9), right = min(frame.maxX, union.maxX + 9)
                        let sorted = icons.sorted { $0.minX < $1.minX }
                        for (index, icon) in sorted.enumerated() {
                            let start = index == 0 ? left : (sorted[index - 1].maxX + icon.minX) / 2
                            let end = index == sorted.count - 1 ? right : (icon.maxX + sorted[index + 1].minX) / 2
                            surfaces.append(SurfaceDescriptor(id: UInt64.max - UInt64(index + 100),
                                x: start - frame.minX, y: icon.minY - 5 - frame.minY,
                                width: max(2, end - start), kind: .dock))
                        }
                    }
                }
            }
            return DisplayGeometry(frame: frame, workArea: work, surfaces: surfaces, blockers: blockers)
        }
    }
    private func dockRects() -> [CGRect] {
        guard hasDockAccess else { lastDockRects = []; return [] }
        let now = CACurrentMediaTime()
        guard !axReadInFlight, now - lastAXRead >= 1.0 / 24 else { return lastDockRects }
        lastAXRead = now; axReadInFlight = true
        let frames = NSScreen.screens.map { cgFrame($0) }
        dockQueue.async { [weak self] in
            guard let self else { return }
            let rects = self.readDockRects(screenFrames: frames)
            DispatchQueue.main.async { [weak self] in
                self?.lastDockRects = rects; self?.axReadInFlight = false
            }
        }
        return lastDockRects
    }
    private func readDockRects(screenFrames: [CGRect]) -> [CGRect] {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [] }
        if dockPID != app.processIdentifier {
            dockPID = app.processIdentifier; dockRoot = AXUIElementCreateApplication(dockPID)
            if let root = dockRoot { AXUIElementSetMessagingTimeout(root, 0.015) }
        }
        guard let root = dockRoot else { return [] }
        var result: [CGRect] = []
        var remaining = 160
        func read(_ item: AXUIElement, depth: Int) {
            guard depth < 4, remaining > 0 else { return }
            remaining -= 1
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXRoleAttribute as CFString, &roleValue)
            let role = roleValue as? String ?? ""
            if role == "AXDockItem" {
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
            if AXUIElementCopyAttributeValue(item, kAXChildrenAttribute as CFString, &children) == .success,
               let elements = children as? [AXUIElement] {
                for child in elements { read(child, depth: depth + 1) }
            }
        }
        read(root, depth: 0)
        // An auto-hidden Dock has no onscreen shelf; do not create a bottom-screen floor.
        return result.filter { rect in
            screenFrames.contains { f in
                rect.minY < f.maxY - 2 && rect.intersection(f).height > 8
            }
        }
    }
}
