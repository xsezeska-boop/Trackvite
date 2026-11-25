/// Coalesces repeated browser/activation callbacks into one presentation operation.
struct FocusPresentationState {
    enum Change: Equatable { case none, show, update, hide }
    private(set) var key: String?
    mutating func set(_ next: String?) -> Change {
        guard key != next else { return .none }
        let previous = key
        key = next
        if next == nil { return .hide }
        return previous == nil ? .show : .update
    }
}
