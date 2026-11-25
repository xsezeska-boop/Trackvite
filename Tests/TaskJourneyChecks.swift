import Foundation
@main
struct TaskJourneyChecks {
    static func main() {
        var trail = TaskJourney()
        let start = Date(timeIntervalSince1970: 1000)
        trail.record(from: start, to: start.addingTimeInterval(5), source: "editor", label: "Редактор", kind: .work)
        trail.record(from: start.addingTimeInterval(5), to: start.addingTimeInterval(10), source: "editor", label: "Редактор", kind: .work)
        assert(trail.entries.count == 1 && trail.entries[0].seconds == 10)
        trail.record(from: start.addingTimeInterval(10), to: start.addingTimeInterval(13), source: "browser:youtube.com", label: "YouTube", kind: .distraction)
        assert(trail.entries.count == 2)
        trail.event("Учёт на паузе", at: start.addingTimeInterval(13))
        trail.record(from: start.addingTimeInterval(13), to: start.addingTimeInterval(15), source: "browser:youtube.com", label: "YouTube", kind: .distraction)
        assert(trail.entries.count == 4 && trail.entries[2].event)
        let before = trail.entries.count
        trail.record(from: start, to: start, source: "bad", label: "bad", kind: .other)
        assert(trail.entries.count == before)
        for i in 0..<100 { trail.event("Переход \(i)") }
        assert(trail.entries.count == 60 && trail.entries.last?.label == "Переход 99")
        print("PASS: continuous intervals merged, app/site switches kept, pause events separate, invalid duration rejected, bounded 60-entry history")
    }
}
