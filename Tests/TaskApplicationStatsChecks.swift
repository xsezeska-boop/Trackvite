import Foundation
@main struct TaskApplicationStatsChecks {
    static func main() {
        var app = TaskApplicationStats(id: "com.apple.Safari", name: "Safari")
        app.add(kind: .work, seconds: 120, domain: "docs.example.com")
        app.add(kind: .distraction, seconds: 30, domain: "youtube.com")
        app.add(kind: .idle, seconds: 45, domain: "youtube.com")
        app.add(kind: .other, seconds: 5, domain: nil)
        app.add(kind: .work, seconds: -1, domain: "invalid.example")
        assert(app.totals.measured == 200)
        assert(app.totals.work == 120 && app.totals.distraction == 30 && app.totals.idle == 45)
        assert(app.sites.count == 2 && app.sites["youtube.com"]?.measured == 75)
        for index in 0..<100 { app.add(kind: .other, seconds: 1, domain: "site\(index).example") }
        assert(app.sites.count == 32)
        assert(app.totals.measured == 300) // Total remains exact even after the domain detail cap.
        print("PASS: cumulative per-app time, distraction/idle, merged domains, invalid duration, bounded sites without losing app total")
    }
}
