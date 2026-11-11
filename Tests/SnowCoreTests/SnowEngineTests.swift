#if STANDALONE_TESTS
import Foundation
class XCTestCase {}
func XCTAssertTrue(_ value: @autoclosure () -> Bool) { precondition(value()) }
func XCTAssertFalse(_ value: @autoclosure () -> Bool) { precondition(!value()) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "\(a) != \(b)") }
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double) { precondition(abs(a - b) <= accuracy) }
func XCTAssertLessThan<T: Comparable>(_ a: T, _ b: T) { precondition(a < b) }
func XCTAssertLessThanOrEqual<T: Comparable>(_ a: T, _ b: T) { precondition(a <= b) }
func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T) { precondition(a > b) }
#else
import XCTest
@testable import SnowCore
#endif

final class SnowEngineTests: XCTestCase {
    func run(_ engine: SnowEngine, seconds: Double) {
        for _ in 0..<Int(seconds * 120) { engine.advance(by: 1.0 / 120) }
    }
    func testVisibleIntervalsSubtractFrontWindows() {
        XCTAssertEqual(Span(0, 100).subtracting(Span(30, 70)), [Span(0, 30), Span(70, 100)])
        XCTAssertEqual(Span(0, 100).subtracting(Span(-20, 120)), [])
    }
    func testMaximizedWindowCoversWorkArea() {
        let work = SnowRect(x: 0, y: 30, width: 1440, height: 800)
        XCTAssertTrue(SnowRect(x: 0, y: 28, width: 1440, height: 802).covers(work))
        XCTAssertFalse(SnowRect(x: 30, y: 80, width: 800, height: 500).covers(work))
    }
    func testFullscreenMaskPreservesForegroundWindow() {
        let full = SnowRect(x: 0, y: 0, width: 400, height: 300)
        let front = SnowRect(x: 100, y: 80, width: 200, height: 150)
        let parts = full.subtracting(front)
        XCTAssertFalse(parts.contains { $0.contains(x: 200, y: 150) })
        XCTAssertTrue(parts.contains { $0.contains(x: 10, y: 10) })
        XCTAssertEqual(parts.reduce(0) { $0 + $1.width * $1.height }, 90000)
    }
    func testSnowLandsOnlyOnShelf() {
        let engine = SnowEngine(width: 400, height: 300)
        engine.updateSurfaces([SurfaceDescriptor(id: 1, x: 100, y: 120, width: 200)], elapsed: 0.1)
        engine.addParticle(Particle(x: 150, y: 117, vy: 30))
        run(engine, seconds: 0.2)
        XCTAssertGreaterThan(engine.piles[1]!.volume, 0)
    }
    func testDockGapsHaveNoFloor() {
        let engine = SnowEngine(width: 400, height: 300)
        engine.updateSurfaces([SurfaceDescriptor(id: 1, x: 100, y: 260, width: 200, kind: .dock)], elapsed: 0.1)
        engine.addParticle(Particle(x: 20, y: 255, vy: 100, debris: true))
        run(engine, seconds: 1)
        XCTAssertEqual(engine.piles[1]!.volume, 0)
        XCTAssertFalse(engine.particles.contains { $0.debris })
    }
    func testHiddenPortionCannotCollectSnow() {
        let engine = SnowEngine(width: 400, height: 300)
        engine.updateSurfaces([SurfaceDescriptor(id: 1, x: 50, y: 120, width: 300, visible: [Span(50, 100)])], elapsed: 0.1)
        engine.addParticle(Particle(x: 200, y: 117, vy: 30))
        run(engine, seconds: 0.2)
        XCTAssertEqual(engine.piles[1]!.volume, 0)
    }
    func testClosedWindowReleasesSnow() {
        let engine = SnowEngine(width: 400, height: 300)
        engine.updateSurfaces([SurfaceDescriptor(id: 1, x: 100, y: 120, width: 200)], elapsed: 0.1)
        engine.addParticle(Particle(x: 150, y: 116, vy: 30))
        run(engine, seconds: 0.2)
        engine.updateSurfaces([], elapsed: 0.1)
        XCTAssertTrue(engine.piles.isEmpty)
        XCTAssertTrue(engine.particles.contains { $0.debris })
        run(engine, seconds: 4)
        XCTAssertFalse(engine.particles.contains { $0.debris })
    }
    func testMovingRightCreatesLeftwardInertia() {
        let engine = SnowEngine(width: 400, height: 300)
        engine.updateSurfaces([SurfaceDescriptor(id: 1, x: 50, y: 120, width: 200)], elapsed: 0.1)
        engine.addParticle(Particle(x: 55, y: 117, vy: 30))
        run(engine, seconds: 0.2)
        engine.updateSurfaces([SurfaceDescriptor(id: 1, x: 100, y: 120, width: 200)], elapsed: 0.1)
        XCTAssertLessThan(engine.piles[1]!.lateralVelocity, 0)
        run(engine, seconds: 0.2)
        XCTAssertTrue(engine.particles.contains { $0.debris && $0.vx < 0 })
    }
    func testDepthIsCapped() {
        let engine = SnowEngine(width: 400, height: 300)
        engine.updateSurfaces([SurfaceDescriptor(id: 1, x: 100, y: 120, width: 200)], elapsed: 0.1)
        for _ in 0..<1000 {
            engine.addParticle(Particle(x: 150, y: 104, vy: 180))
            engine.advance(by: 1.0 / 120)
        }
        XCTAssertLessThanOrEqual(engine.piles[1]!.heights.max()!, engine.maxDepth)
    }
    func testSpeedChangesMotionNotGravity() {
        let slow = SnowEngine(width: 400, height: 300), fast = SnowEngine(width: 400, height: 300)
        slow.speed = 0.5; fast.speed = 2
        for e in [slow, fast] { e.addParticle(Particle(x: 200, y: 10, vy: 20)) }
        run(slow, seconds: 1); run(fast, seconds: 1)
        XCTAssertEqual(slow.particles[0].y, 20, accuracy: 0.1)
        XCTAssertEqual(fast.particles[0].y, 50, accuracy: 0.1)
    }
    func testParticlePoolAndWakeCatchupAreBounded() {
        let engine = SnowEngine(width: 10000, height: 10000)
        engine.intensity = .heavy; engine.particleLimit = 80
        engine.seedSky(); engine.advance(by: 3600)
        XCTAssertLessThanOrEqual(engine.particles.count, 80)
        XCTAssertLessThan(engine.time, 0.11)
        XCTAssertTrue(engine.particles.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }
    func testPassiveSaverHasNoAccumulation() {
        let engine = SnowEngine(width: 400, height: 300)
        engine.accumulationEnabled = false
        engine.updateSurfaces([SurfaceDescriptor(id: 1, x: 0, y: 50, width: 400)], elapsed: 0.1)
        engine.addParticle(Particle(x: 100, y: 45, vy: 40))
        run(engine, seconds: 0.4)
        XCTAssertEqual(engine.piles[1]!.volume, 0)
    }
    func testFullscreenBlockerPreventsAccumulation() {
        let engine = SnowEngine(width: 400, height: 300)
        engine.updateSurfaces([SurfaceDescriptor(id: 1, x: 0, y: 120, width: 400)], elapsed: 0.1)
        engine.blockers = [SnowRect(x: 0, y: 0, width: 400, height: 300)]
        engine.addParticle(Particle(x: 100, y: 117, vy: 40))
        run(engine, seconds: 0.4)
        XCTAssertEqual(engine.piles[1]!.volume, 0)
    }
}
