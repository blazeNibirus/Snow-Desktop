import Foundation

public enum Intensity: Int, CaseIterable, Sendable {
    case light, medium, heavy
    public var emission: Double { [3.5, 7.0, 12.0][rawValue] }
}

public struct Particle: Sendable {
    public var x: Double, y: Double, vx: Double, vy: Double
    public var radius: Double, opacity: Double, phase: Double, age: Double
    public var debris: Bool
    public init(x: Double, y: Double, vx: Double = 0, vy: Double = 16,
                radius: Double = 1, opacity: Double = 0.8, phase: Double = 0,
                age: Double = 0, debris: Bool = false) {
        self.x = x; self.y = y; self.vx = vx; self.vy = vy; self.radius = radius
        self.opacity = opacity; self.phase = phase; self.age = age; self.debris = debris
    }
}

public final class SnowPile {
    public internal(set) var surface: SurfaceDescriptor
    public internal(set) var heights: [Double]
    public internal(set) var lateralVelocity: Double = 0
    public internal(set) var velocityY: Double = 0
    public internal(set) var velocityX: Double = 0
    public var cellWidth: Double { surface.width / Double(heights.count) }
    public var volume: Double { heights.reduce(0, +) * cellWidth }
    init(surface: SurfaceDescriptor) {
        self.surface = surface
        heights = Array(repeating: 0, count: max(2, min(1024, Int(ceil(surface.width / 4)))))
    }
    public func height(at x: Double) -> Double {
        guard x >= surface.x, x <= surface.x + surface.width else { return 0 }
        return heights[min(heights.count - 1, max(0, Int((x - surface.x) / cellWidth)))]
    }
}

/// Bounded, deterministic simulation. Coordinates are screen-local points, y down.
public final class SnowEngine {
    public var width: Double, height: Double
    public var intensity: Intensity = .light
    public var speed: Double = 1
    public var maxDepth: Double = 13
    public var particleLimit = 1400
    public var surfaceLimit = 64
    public var accumulationEnabled = true
    public private(set) var particles: [Particle] = []
    public private(set) var piles: [UInt64: SnowPile] = [:]
    public private(set) var time: Double = 0
    public var blockers: [SnowRect] = []
    private var seed: UInt64
    private var emissionRemainder: Double = 0
    private var accumulator: Double = 0
    private var lastGeometryTime: Double = 0
    private var surfaceOrder: [SnowPile] = []
    private var relaxationCounter = 0

    public init(width: Double, height: Double, seed: UInt64 = 0x5A0F) {
        self.width = width; self.height = height; self.seed = max(1, seed)
        particles.reserveCapacity(particleLimit)
    }
    private func random() -> Double {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        return Double(seed & 0x1FFFFFFFFFFFFF) / Double(0x20000000000000)
    }
    public func seedSky() {
        let count = min(particleLimit / 2, Int(intensity.emission * width / 1440 * height / 19))
        for _ in 0..<max(0, count) { spawn(y: random() * height) }
    }
    private func spawn(y: Double = -5) {
        guard particles.count < particleLimit else { return }
        particles.append(Particle(x: random() * width, y: y, vx: random() * 3 - 1.5,
            vy: 11 + random() * 12, radius: 0.55 + random() * 0.85,
            opacity: 0.32 + random() * 0.56, phase: random() * .pi * 2))
    }
    public func addParticle(_ particle: Particle) {
        if particles.count < particleLimit { particles.append(particle) }
    }
    public func updateSurfaces(_ descriptors: [SurfaceDescriptor], elapsed: Double) {
        let dt = max(1.0 / 120, min(0.5, elapsed))
        let incoming = Array(descriptors.filter { $0.width > 2 }.prefix(surfaceLimit))
        let ids = Set(incoming.map(\.id))
        for id in Array(piles.keys) where !ids.contains(id) {
            if let pile = piles.removeValue(forKey: id) { release(pile) }
        }
        for desc in incoming {
            guard let pile = piles[desc.id] else { piles[desc.id] = SnowPile(surface: desc); continue }
            let dx = desc.x - pile.surface.x, dy = desc.y - pile.surface.y
            if abs(desc.width - pile.surface.width) > 2 {
                let old = pile.heights, oldCell = pile.cellWidth
                let count = max(2, min(1024, Int(ceil(desc.width / 4))))
                pile.heights = (0..<count).map { i in
                    let index = Int(Double(i) * desc.width / Double(count) / oldCell)
                    return index < old.count ? old[index] : 0
                }
                // Trimmed material drops from the old window edge.
                if desc.width < pile.surface.width {
                    for i in old.indices where Double(i) * oldCell > desc.width && old[i] > 0.2 {
                        fragment(x: pile.surface.x + Double(i) * oldCell,
                                 y: pile.surface.y - old[i] / 2, vx: 0, vy: 8, amount: old[i])
                    }
                }
            }
            if abs(dx) < width * 0.75 && abs(dy) < height * 0.75 {
                let windowVelocity = dx / dt
                pile.lateralVelocity -= (windowVelocity - pile.velocityX) * 0.62
                pile.velocityX = windowVelocity
                pile.lateralVelocity = max(-700, min(700, pile.lateralVelocity))
                pile.velocityY = dy / dt
                if dy > 10 { release(pile, fraction: min(0.8, dy / 100)) }
            } else {
                // Space changes / teleports do not drag a snowbank across displays.
                pile.heights = pile.heights.map { _ in 0 }
                pile.lateralVelocity = 0
            }
            pile.surface = desc
        }
        surfaceOrder = piles.values.sorted { $0.surface.y < $1.surface.y }
        lastGeometryTime = time
    }
    public func clear() {
        particles.removeAll(keepingCapacity: true); piles.removeAll(keepingCapacity: true)
        surfaceOrder.removeAll(keepingCapacity: true); accumulator = 0; emissionRemainder = 0
    }
    public func clearAccumulation() {
        for pile in piles.values { pile.heights = pile.heights.map { _ in 0 } }
    }
    public func advance(by elapsed: Double) {
        // Never catch up a sleeping machine with thousands of physics steps.
        accumulator += max(0, min(elapsed, 0.1))
        let step = 1.0 / 120
        while accumulator >= step { simulate(step); accumulator -= step }
    }
    private func simulate(_ dt: Double) {
        time += dt
        emissionRemainder += intensity.emission * width / 1440 * dt
        while emissionRemainder >= 1 { spawn(); emissionRemainder -= 1 }
        var i = 0
        while i < particles.count {
            var p = particles[i]
            let oldY = p.y
            p.age += dt
            if p.debris { p.vy += 190 * dt; p.vx *= exp(-0.5 * dt) }
            let wind = p.debris ? 0 : sin(time * 0.47 + p.phase) * 5.5
            let motion = p.debris ? 1 : max(0.25, min(3, speed))
            p.x += (p.vx + wind) * dt * motion; p.y += p.vy * dt * motion
            var caught = false
            if accumulationEnabled, p.vy > 0 {
                for pile in surfaceOrder {
                    let surface = pile.surface
                    guard surface.supports(p.x), p.x >= surface.x, p.x <= surface.x + surface.width else { continue }
                    let top = surface.y - pile.height(at: p.x)
                    if oldY + p.radius <= top + 2, p.y + p.radius >= top,
                       !blockers.contains(where: { $0.contains(x: p.x, y: top - 1) }) {
                        deposit(pile, at: p.x, volume: p.debris ? p.radius * 4.2 : p.radius * 5.5)
                        caught = true; break
                    }
                }
            }
            if caught || p.y > height + 12 || p.x < -40 || p.x > width + 40 || (p.debris && p.age > 12) {
                particles.swapAt(i, particles.count - 1); particles.removeLast()
            } else { particles[i] = p; i += 1 }
        }
        for pile in surfaceOrder {
            if time - lastGeometryTime > 0.15 { pile.velocityY *= exp(-15 * dt) }
            advect(pile, dt: dt)
        }
        relaxationCounter += 1
        if relaxationCounter % 4 == 0 { for pile in surfaceOrder { relax(pile) } }
    }
    private func deposit(_ pile: SnowPile, at x: Double, volume: Double) {
        let center = min(pile.heights.count - 1, max(0, Int((x - pile.surface.x) / pile.cellWidth)))
        let weights = [0.16, 0.68, 0.16]
        for offset in -1...1 {
            let index = center + offset
            if pile.heights.indices.contains(index) {
                pile.heights[index] = min(maxDepth, pile.heights[index] + volume * weights[offset + 1] / pile.cellWidth)
            }
        }
    }
    private func advect(_ pile: SnowPile, dt: Double) {
        let velocity = pile.lateralVelocity
        guard abs(velocity) > 0.08 else { return }
        let f = min(0.95, abs(velocity) * dt / pile.cellWidth)
        let old = pile.heights
        for i in old.indices {
            let from = velocity > 0 ? i - 1 : i + 1
            pile.heights[i] = old[i] * (1 - f) + (old.indices.contains(from) ? old[from] * f : 0)
        }
        let edge = velocity > 0 ? old.count - 1 : 0
        if old[edge] * f > 0.06 {
            fragment(x: velocity > 0 ? pile.surface.x + pile.surface.width + 1 : pile.surface.x - 1,
                     y: pile.surface.y - old[edge] / 2, vx: velocity * 0.55,
                     vy: max(5, pile.velocityY * 0.2), amount: old[edge] * f)
        }
        pile.lateralVelocity *= exp(-3.8 * dt)
    }
    private func relax(_ pile: SnowPile) {
        guard pile.heights.count > 1 else { return }
        // An angle-of-repose solver, alternating direction to avoid directional bias.
        let indices = relaxationCounter % 8 == 0 ? Array(0..<(pile.heights.count - 1)) : Array((0..<(pile.heights.count - 1)).reversed())
        for i in indices {
            let difference = pile.heights[i] - pile.heights[i + 1]
            if abs(difference) > pile.cellWidth * 0.48 {
                let transfer = (abs(difference) - pile.cellWidth * 0.48) * 0.22
                if difference > 0 { pile.heights[i] -= transfer; pile.heights[i + 1] += transfer }
                else { pile.heights[i] += transfer; pile.heights[i + 1] -= transfer }
            }
        }
    }
    private func release(_ pile: SnowPile, fraction: Double = 1) {
        for i in pile.heights.indices where pile.heights[i] > 0.18 {
            let h = pile.heights[i] * fraction
            let x = pile.surface.x + (Double(i) + 0.5) * pile.cellWidth
            if pile.surface.supports(x) {
                fragment(x: x, y: pile.surface.y - h / 2,
                         vx: pile.lateralVelocity * 0.4 + random() * 14 - 7,
                         vy: max(4, pile.velocityY * 0.3), amount: h)
            }
            pile.heights[i] *= 1 - fraction
        }
    }
    private func fragment(x: Double, y: Double, vx: Double, vy: Double, amount: Double) {
        guard particles.count < particleLimit else { return }
        particles.append(Particle(x: x, y: y, vx: vx, vy: vy,
            radius: min(2.4, max(0.65, sqrt(amount) * 0.65)), opacity: 0.86,
            phase: random() * .pi * 2, debris: true))
    }
}
