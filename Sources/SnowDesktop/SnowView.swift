import AppKit
import QuartzCore
import SnowCore

/// Tiny shared sprite textures, bounded layer pool, and small strip paths for snowbanks.
/// No per-frame full-screen CPU bitmap and no per-particle view hierarchy.
final class SnowView: NSView {
    let engine: SnowEngine
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var sprites: [CALayer] = []
    private let particleLayer = CALayer()
    var particleOccluders: [SnowRect] = []
    private var bankLayers: [UInt64: CAShapeLayer] = [:]
    private var bankMaskRects: [UInt64: [SnowRect]] = [:]
    private var bankMaskSizes: [UInt64: CGSize] = [:]
    private var lastParticleOccluders: [SnowRect]?
    private var lastMaskBounds = CGRect.zero
    private var fallingImage: CGImage?
    private var debrisImage: CGImage?
    private var appearanceKey = ""
    private var frameCounter = 0
    var beforeFrame: (() -> Void)?
    var preview = false
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    init(frame: CGRect, engine: SnowEngine, preview: Bool = false) {
        self.engine = engine; self.preview = preview
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = preview ? NSColor(calibratedRed: 0.10, green: 0.15, blue: 0.22, alpha: 1).cgColor : nil
        layer?.masksToBounds = true
        if preview { layer?.cornerRadius = 12 }
        layer?.addSublayer(particleLayer)
        updateAppearance()
    }
    required init?(coder: NSCoder) { nil }
    func start() {
        guard link == nil else { return }
        lastTime = 0
        let displayLink = displayLink(target: self, selector: #selector(frameTick(_:)))
        link = displayLink
        updateRate()
        displayLink.add(to: .main, forMode: .common)
    }
    func stop() {
        link?.invalidate(); link = nil; lastTime = 0
    }
    func updateRate() {
        let maximum = Float(window?.screen?.maximumFramesPerSecond ?? 60)
        let process = ProcessInfo.processInfo
        let constrained: Float = process.thermalState == .critical || process.isLowPowerModeEnabled ? 30 :
            (process.thermalState == .serious ? min(60, maximum) : maximum)
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, constrained), maximum: constrained, preferred: constrained)
    }
    func applyPreferences() {
        let p = Settings.shared.value
        engine.intensity = Intensity(rawValue: p.intensity) ?? .light
        engine.speed = p.speed
        updateAppearance()
        updateRate()
    }
    func updateAppearance() {
        let p = Settings.shared.value
        let key = "\(p.falling.brightness),\(p.falling.warmth),\(p.settled.brightness),\(p.settled.warmth)"
        guard key != appearanceKey else { return }
        appearanceKey = key
        fallingImage = Self.sprite(color: p.falling.color)
        debrisImage = Self.sprite(color: p.settled.color)
        for bank in bankLayers.values { bank.fillColor = p.settled.color.cgColor }
    }
    private static func sprite(color: NSColor) -> CGImage? {
        guard let context = CGContext(data: nil, width: 12, height: 12, bitsPerComponent: 8, bytesPerRow: 48,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: 1, y: 1, width: 10, height: 10))
        return context.makeImage()
    }
    private func visibilityMask(excluding cuts: [SnowRect], in region: CGRect? = nil) -> CAShapeLayer? {
        guard !cuts.isEmpty else { return nil }
        let box = region ?? bounds
        var visible = [SnowRect(x: box.minX, y: box.minY, width: box.width, height: box.height)]
        for cut in cuts { visible = visible.flatMap { $0.subtracting(cut) } }
        let mask = CAShapeLayer(), path = CGMutablePath()
        visible.forEach { path.addRect(CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)) }
        mask.path = path; mask.fillColor = NSColor.white.cgColor
        return mask
    }
    func updateVisibilityMask() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // Piles remain above the window edge; falling flakes are behind every window.
        layer?.mask = nil
        particleLayer.frame = bounds
        if particleOccluders != lastParticleOccluders || bounds != lastMaskBounds {
            particleLayer.mask = visibilityMask(excluding: particleOccluders)
            lastParticleOccluders = particleOccluders; lastMaskBounds = bounds
        }
        CATransaction.commit()
    }
    @objc private func frameTick(_ sender: CADisplayLink) {
        autoreleasepool {
            beforeFrame?()
            let now = sender.timestamp
            let dt = lastTime == 0 ? 1.0 / 60 : now - lastTime
            lastTime = now
            engine.advance(by: dt)
            render()
        }
    }
    func render() {
        guard let root = layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let particles = engine.particles
        while sprites.count < particles.count {
            let sprite = CALayer()
            sprite.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "opacity": NSNull(), "hidden": NSNull()]
            particleLayer.addSublayer(sprite); sprites.append(sprite)
        }
        for i in sprites.indices {
            let sprite = sprites[i]
            guard i < particles.count else { sprite.isHidden = true; continue }
            let p = particles[i]
            sprite.isHidden = false
            sprite.position = CGPoint(x: p.x, y: p.y)
            let size = p.radius * 2.4
            sprite.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            sprite.contents = p.debris ? debrisImage : fallingImage
            sprite.opacity = Float(p.opacity)
        }
        frameCounter += 1
        // Snowbanks deform slowly; particle positions still update at the display rate.
        if frameCounter % 2 == 0 {
            let ids = Set(engine.piles.keys)
            for id in Array(bankLayers.keys) where !ids.contains(id) {
                bankLayers.removeValue(forKey: id)?.removeFromSuperlayer()
                bankMaskRects.removeValue(forKey: id); bankMaskSizes.removeValue(forKey: id)
            }
            for (id, pile) in engine.piles {
                let bank: CAShapeLayer
                if let existing = bankLayers[id] { bank = existing }
                else {
                    bank = CAShapeLayer(); bank.masksToBounds = true; bank.fillColor = Settings.shared.value.settled.color.cgColor
                    root.addSublayer(bank); bankLayers[id] = bank
                }
                let path = CGMutablePath(), surface = pile.surface
                bank.frame = CGRect(x: surface.x, y: surface.y - engine.maxDepth - 1,
                                    width: surface.width, height: engine.maxDepth + 2)
                let localOccluders = surface.occluders.map { r in
                    SnowRect(x: r.x - bank.frame.minX, y: r.y - bank.frame.minY, width: r.width, height: r.height)
                }
                if bankMaskRects[id] != localOccluders || bankMaskSizes[id] != bank.bounds.size {
                    bank.mask = visibilityMask(excluding: localOccluders, in: bank.bounds)
                    bankMaskRects[id] = localOccluders; bankMaskSizes[id] = bank.bounds.size
                }
                let base = engine.maxDepth + 1
                for span in surface.visible {
                    let left = max(0, span.lower - surface.x), right = min(surface.width, span.upper - surface.x)
                    guard right > left else { continue }
                    let first = max(0, Int(left / pile.cellWidth))
                    let last = min(pile.heights.count - 1, Int(right / pile.cellWidth))
                    guard last >= first else { continue }
                    path.move(to: CGPoint(x: left, y: base))
                    path.addLine(to: CGPoint(x: left, y: base - pile.height(at: surface.x + left)))
                    for i in first...last {
                        let x = min(right, (Double(i) + 0.5) * pile.cellWidth)
                        let endX = min(right, (Double(i) + 1) * pile.cellWidth)
                        path.addQuadCurve(to: CGPoint(x: endX, y: base - pile.height(at: surface.x + endX)),
                                          control: CGPoint(x: x, y: base - pile.height(at: surface.x + x)))
                    }
                    path.addLine(to: CGPoint(x: right, y: base)); path.closeSubpath()
                }
                bank.path = path
            }
        }
        // Shrink the high-water pool after bursts rather than keeping it forever.
        if frameCounter % 300 == 0, sprites.count > particles.count + 160 {
            let target = particles.count + 80
            while sprites.count > target { sprites.removeLast().removeFromSuperlayer() }
        }
        CATransaction.commit()
    }
    deinit { link?.invalidate() }
}
