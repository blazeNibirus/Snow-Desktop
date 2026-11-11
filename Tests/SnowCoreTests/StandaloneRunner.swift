#if STANDALONE_TESTS
@main struct PhysicsTestRunner {
    static func main() {
        let tests = SnowEngineTests()
        tests.testVisibleIntervalsSubtractFrontWindows(); print("PASS testVisibleIntervalsSubtractFrontWindows")
        tests.testMaximizedWindowCoversWorkArea(); print("PASS testMaximizedWindowCoversWorkArea")
        tests.testFullscreenMaskPreservesForegroundWindow(); print("PASS testFullscreenMaskPreservesForegroundWindow")
        tests.testSnowLandsOnlyOnShelf(); print("PASS testSnowLandsOnlyOnShelf")
        tests.testDockGapsHaveNoFloor(); print("PASS testDockGapsHaveNoFloor")
        tests.testHiddenPortionCannotCollectSnow(); print("PASS testHiddenPortionCannotCollectSnow")
        tests.testClosedWindowReleasesSnow(); print("PASS testClosedWindowReleasesSnow")
        tests.testMovingRightCreatesLeftwardInertia(); print("PASS testMovingRightCreatesLeftwardInertia")
        tests.testDepthIsCapped(); print("PASS testDepthIsCapped")
        tests.testSpeedChangesMotionNotGravity(); print("PASS testSpeedChangesMotionNotGravity")
        tests.testParticlePoolAndWakeCatchupAreBounded(); print("PASS testParticlePoolAndWakeCatchupAreBounded")
        tests.testPassiveSaverHasNoAccumulation(); print("PASS testPassiveSaverHasNoAccumulation")
        tests.testFullscreenBlockerPreventsAccumulation(); print("PASS testFullscreenBlockerPreventsAccumulation")
        print("All 13 physics checks passed.")
    }
}
#endif
