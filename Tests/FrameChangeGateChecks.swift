
@main
struct FrameChangeGateChecks {
    static func assertFalse(_ value: Bool) { assert(!value) }
    static func main() {
        testFirstFrameAndResetRequireAnalysis()
        testSmallFlickerIsIgnoredButContentChangesPass()
        testChangesAccumulateAgainstAnalyzedFrame()
        assert(OCRBudget.interval(duration: 0.1, constrained: false) == 3)
        assert(OCRBudget.interval(duration: 0.5, constrained: false) == 5)
        assert(OCRBudget.interval(duration: 0.1, constrained: true) == 8)
        assert(OCRBudget.interval(duration: 0.5, constrained: true) == 10)
        print("PASS: first frame, reset, unchanged frames, flicker, meaningful change, cumulative change")
    }
    static func testFirstFrameAndResetRequireAnalysis() {
        var gate = FrameChangeGate()
        assert(gate.shouldAnalyze([10, 10, 10]))
        gate.recordAnalyzed([10, 10, 10])
        assertFalse(gate.shouldAnalyze([10, 10, 10]))
        gate.reset()
        assert(gate.shouldAnalyze([10, 10, 10]))
    }
    static func testSmallFlickerIsIgnoredButContentChangesPass() {
        var gate = FrameChangeGate()
        gate.recordAnalyzed([10, 10, 10, 10])
        assertFalse(gate.shouldAnalyze([200, 10, 10, 10]))
        assertFalse(gate.shouldAnalyze([16, 16, 16, 16]))
        assert(gate.shouldAnalyze([20, 20, 20, 10]))
    }
    static func testChangesAccumulateAgainstAnalyzedFrame() {
        var gate = FrameChangeGate()
        gate.recordAnalyzed([0, 0, 0])
        assertFalse(gate.shouldAnalyze([4, 4, 4]))
        assert(gate.shouldAnalyze([8, 8, 8]))
        gate.recordAnalyzed([8, 8, 8])
        assertFalse(gate.shouldAnalyze([8, 8, 8]))
        assert(gate.shouldAnalyze([8, 8, 8, 8]))
    }
}
