/// Compare with the last analyzed frame, so small changes can accumulate.
struct FrameChangeGate {
    private var baseline: [UInt8]?
    mutating func reset() { baseline = nil }
    mutating func recordAnalyzed(_ signature: [UInt8]) { baseline = signature }
    func shouldAnalyze(_ signature: [UInt8]) -> Bool {
        guard let baseline, baseline.count == signature.count else { return true }
        return zip(baseline, signature).lazy.filter { abs(Int($0) - Int($1)) > 6 }.prefix(3).count == 3
    }
}
