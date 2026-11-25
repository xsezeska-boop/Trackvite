/// Wall-time scheduling budget, not a guarantee of a CPU percentage.
enum OCRBudget {
    static func interval(duration: Double, constrained: Bool) -> Double {
        // At most ~10% OCR wall-time duty, ~5% when constrained.
        max(constrained ? 8 : 3, duration * (constrained ? 20 : 10))
    }
}
