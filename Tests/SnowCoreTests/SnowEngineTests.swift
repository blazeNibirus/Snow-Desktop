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
    func testSnowCapsAreRoundedAtBothPhysicalEdges() {
        XCTAssertEqual(SnowBankProfile.edgeFactor(x: 0, width: 200), 0)
        XCTAssertEqual(SnowBankProfile.edgeFactor(x: 200, width: 200), 0)
        XCTAssertEqual(SnowBankProfile.edgeFactor(x: 100, width: 200), 1)
        XCTAssertLessThan(SnowBankProfile.edgeFactor(x: 0.01, width: 200), 0.00001)
        XCTAssertEqual(SnowBankProfile.edgeFactor(x: 0, width: 200, roundLeft: false, roundRight: false), 1)
    }
    func testFullWidthDockWorksWithoutAccessibilityIcons() {
        let shelves = DockLayout.surfaces(frame: SnowRect(x: 0, y: 0, width: 400, height: 300),
            workArea: SnowRect(x: 0, y: 24, width: 400, height: 216), icons: [], fullWidth: true)
        XCTAssertEqual(shelves.count, 1)
        XCTAssertEqual(shelves[0].y, 240)
        XCTAssertEqual(shelves[0].width, 400)
    }
    func testDockOnlyModeHasFiniteBoundsAndJoinedInnerEdges() {
        let shelves = DockLayout.surfaces(frame: SnowRect(x: 0, y: 0, width: 400, height: 300),
            workArea: SnowRect(x: 0, y: 24, width: 400, height: 216),
            icons: [SnowRect(x: 120, y: 250, width: 40, height: 40),
                    SnowRect(x: 170, y: 250, width: 40, height: 40)], fullWidth: false)
        XCTAssertEqual(shelves.count, 2)
        XCTAssertFalse(shelves.contains { $0.supports(10) || $0.supports(390) })
        XCTAssertFalse(shelves[0].roundRight)
        XCTAssertFalse(shelves[1].roundLeft)
        XCTAssertEqual(shelves[0].x + shelves[0].width, shelves[1].x)
    }
    func testClosedWindowSnowCanLandOnDock() {
        let e = SnowEngine(width: 400, height: 300)
        let window = SurfaceDescriptor(id: 1, x: 100, y: 120, width: 200)
        let dock = SurfaceDescriptor(id: 2, x: 100, y: 260, width: 200, kind: .dock)
        e.updateSurfaces([window, dock], elapsed: 0.1)
        for _ in 0..<20 { e.addParticle(Particle(x: 200, y: 110, vy: 60)) }
        run(e, seconds: 0.3)
        XCTAssertGreaterThan(e.piles[1]!.volume, 0)
        e.updateSurfaces([dock], elapsed: 0.1)
        run(e, seconds: 2)
        XCTAssertGreaterThan(e.piles[2]!.volume, 0)
    }
    func testOccluderDoesNotRemoveTheWholeSnowColumn() {
        let bank = SnowRect(x: 0, y: 100, width: 100, height: 14)
        let front = SnowRect(x: 0, y: 80, width: 40, height: 25)
        let visible = bank.subtracting(front)
        XCTAssertTrue(visible.contains { $0.contains(x: 20, y: 110) })
        XCTAssertFalse(visible.contains { $0.contains(x: 20, y: 102) })
        XCTAssertTrue(visible.contains { $0.contains(x: 60, y: 102) })
    }
    func testCoveredBankTopDoesNotCollectVisibleSnow() {
        let e = SnowEngine(width: 400, height: 300)
        e.updateSurfaces([SurfaceDescriptor(id: 1, x: 100, y: 120, width: 200,
            occluders: [SnowRect(x: 100, y: 80, width: 200, height: 40)])], elapsed: 0.1)
        e.addParticle(Particle(x: 200, y: 117, vy: 40))
        run(e, seconds: 0.4)
        XCTAssertEqual(e.piles[1]!.volume, 0)
    }
    func testShrinkingWindowRemovesSupportBeyondNewRightEdge() {
        let e = SnowEngine(width: 400, height: 300)
        e.updateSurfaces([SurfaceDescriptor(id: 1, x: 50, y: 120, width: 250)], elapsed: 0.1)
        e.addParticle(Particle(x: 250, y: 117, vy: 40))
        run(e, seconds: 0.2)
        e.updateSurfaces([SurfaceDescriptor(id: 1, x: 50, y: 120, width: 120)], elapsed: 0.1)
        XCTAssertFalse(e.piles[1]!.surface.supports(250))
        XCTAssertEqual(e.piles[1]!.height(at: 250), 0)
        XCTAssertTrue(e.particles.contains { $0.debris && $0.x > 170 })
    }

}
