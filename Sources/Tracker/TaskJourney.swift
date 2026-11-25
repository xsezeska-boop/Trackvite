import Foundation

struct TaskJourneyEntry: Identifiable {
    var id = UUID()
    let date: Date
    var end: Date
    let source: String
    let label: String
    let kind: FocusActivityKind
    var seconds: Double
    let event: Bool
}
struct TaskJourney {
    private(set) var entries: [TaskJourneyEntry] = []
    mutating func record(from: Date, to: Date, source: String, label: String, kind: FocusActivityKind) {
        let seconds = to.timeIntervalSince(from)
        guard seconds.isFinite, seconds > 0 else { return }
        if let last = entries.last, !last.event, last.source == source, last.kind == kind,
           abs(from.timeIntervalSince(last.end)) < 0.1 {
            entries[entries.count - 1].end = to
            entries[entries.count - 1].seconds += seconds
        } else {
            entries.append(TaskJourneyEntry(date: from, end: to, source: source,
                label: String(label.prefix(180)), kind: kind, seconds: seconds, event: false))
        }
        trim()
    }
    mutating func event(_ label: String, kind: FocusActivityKind = .other, at date: Date = Date()) {
        entries.append(TaskJourneyEntry(date: date, end: date, source: "event", label: String(label.prefix(180)), kind: kind, seconds: 0, event: true))
        trim()
    }
    private mutating func trim() { if entries.count > 60 { entries.removeFirst(entries.count - 60) } }
}
