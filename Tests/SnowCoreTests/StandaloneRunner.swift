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
        tests.testSnowCapsAreRoundedAtBothPhysicalEdges(); print("PASS testSnowCapsAreRoundedAtBothPhysicalEdges")
        tests.testFullWidthDockWorksWithoutAccessibilityIcons(); print("PASS testFullWidthDockWorksWithoutAccessibilityIcons")
        tests.testDockOnlyModeHasFiniteBoundsAndJoinedInnerEdges(); print("PASS testDockOnlyModeHasFiniteBoundsAndJoinedInnerEdges")
        tests.testClosedWindowSnowCanLandOnDock(); print("PASS testClosedWindowSnowCanLandOnDock")
        tests.testOccluderDoesNotRemoveTheWholeSnowColumn(); print("PASS testOccluderDoesNotRemoveTheWholeSnowColumn")
        tests.testCoveredBankTopDoesNotCollectVisibleSnow(); print("PASS testCoveredBankTopDoesNotCollectVisibleSnow")
        tests.testShrinkingWindowRemovesSupportBeyondNewRightEdge(); print("PASS testShrinkingWindowRemovesSupportBeyondNewRightEdge")
        print("All 20 physics checks passed.")
    }
}
#endif
