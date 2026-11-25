import Foundation

enum FocusActivityKind: String {
    case work = "Focused"
    case distraction = "Distracted"
    case other = "Other"
    case idle = "Idle"
}
struct FocusActivityTotals {
    var work: Double = 0
    var distraction: Double = 0
    var other: Double = 0
    var idle: Double = 0
    var measured: Double { work + distraction + other + idle }
    mutating func add(_ kind: FocusActivityKind, seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        switch kind {
        case .work: work += seconds
        case .distraction: distraction += seconds
        case .other: other += seconds
        case .idle: idle += seconds
        }
    }
    static func classify(plan: FocusPlan, app: String, domain: String?, idle: Bool) -> FocusActivityKind {
        if idle { return .idle }
        if plan.blockedApps.contains(app) || domain.map({ plan.blocks(domain: $0) }) == true { return .distraction }
        return plan.workApps.contains(app) ? .work : .other
    }
}

