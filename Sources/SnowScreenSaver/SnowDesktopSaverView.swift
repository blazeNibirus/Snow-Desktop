import AppKit
import ScreenSaver

/// Runs inside Apple's ScreenSaver host, independently from the desktop overlay.
/// It never enumerates windows, requests Accessibility, or creates snowbanks.
@objc(SnowDesktopSaverView)
final class SnowDesktopSaverView: ScreenSaverView {
    private var engine: SnowEngine!
    private var lastTime: CFTimeInterval = 0
    private var snowColor = NSColor(white: 0.95, alpha: 1)
    private var configWindow: NSWindow?
    private var speedControl: NSSlider?
    private var intensityControl: NSSegmentedControl?
    private let settings = ScreenSaverDefaults(forModuleWithName: "com.blazenibirus.SnowDesktop.Saver")!
    override var isFlipped: Bool { true }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        settings.register(defaults: ["speed": 1.0, "intensity": 0])
        configureEngine()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        settings.register(defaults: ["speed": 1.0, "intensity": 0])
        configureEngine()
    }
    private func configureEngine() {
        // Keep preview flakes visible while maintaining the same unhurried motion.
        engine = SnowEngine(width: max(1, bounds.width), height: max(1, bounds.height))
        engine.accumulationEnabled = false
        engine.particleLimit = 1000
        engine.intensity = Intensity(rawValue: settings.integer(forKey: "intensity")) ?? .light
        engine.speed = max(0.35, min(2.5, settings.double(forKey: "speed")))
        engine.seedSky()
        animationTimeInterval = 1.0 / Double(window?.screen?.maximumFramesPerSecond ?? 60)
    }
    override func startAnimation() {
        super.startAnimation(); lastTime = 0
        if engine.width != bounds.width || engine.height != bounds.height { configureEngine() }
    }
    override func stopAnimation() { super.stopAnimation(); lastTime = 0 }
    override func animateOneFrame() {
        let now = ProcessInfo.processInfo.systemUptime
        engine.advance(by: lastTime == 0 ? animationTimeInterval : now - lastTime)
        lastTime = now; needsDisplay = true
    }
    override func draw(_ rect: NSRect) {
        NSColor(calibratedRed: 0.035, green: 0.065, blue: 0.105, alpha: 1).setFill()
        bounds.fill()
        for p in engine.particles {
            snowColor.withAlphaComponent(p.opacity).setFill()
            NSBezierPath(ovalIn: NSRect(x: p.x, y: p.y, width: p.radius * 2, height: p.radius * 2)).fill()
        }
    }
    override var hasConfigureSheet: Bool { true }
    override var configureSheet: NSWindow? {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 340, height: 190),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Snow Desktop"
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.addArrangedSubview(NSTextField(labelWithString: "Тихий снег без накопления"))
        let intensity = NSSegmentedControl(labels: ["Лёгкий", "Средний", "Густой"], trackingMode: .selectOne, target: nil, action: nil)
        intensity.selectedSegment = engine.intensity.rawValue; intensityControl = intensity
        stack.addArrangedSubview(intensity)
        let speed = NSSlider(value: engine.speed, minValue: 0.35, maxValue: 2.5, target: nil, action: nil)
        speed.setAccessibilityLabel("Скорость снега"); speedControl = speed
        stack.addArrangedSubview(speed)
        stack.addArrangedSubview(NSButton(title: "Готово", target: self, action: #selector(saveConfiguration)))
        window.contentView = stack; configWindow = window
        return window
    }
    @objc private func saveConfiguration() {
        settings.set(speedControl?.doubleValue ?? 1, forKey: "speed")
        settings.set(intensityControl?.selectedSegment ?? 0, forKey: "intensity")
        settings.synchronize(); configureEngine()
        if let sheet = configWindow { sheet.sheetParent?.endSheet(sheet) }
        configWindow = nil
    }
}
