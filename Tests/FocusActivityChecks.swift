import Foundation
@main
struct FocusActivityChecks {
    static func main() {
        let plan = FocusPlan(title: "Задача", detail: "", start: .distantFuture, minutes: 30,
            daily: false, blockedApps: ["chat"], blockedSites: ["youtube.com"], workApps: ["editor", "browser"])
        assert(FocusActivityTotals.classify(plan: plan, app: "editor", domain: nil, idle: false) == .work)
        assert(FocusActivityTotals.classify(plan: plan, app: "browser", domain: "m.youtube.com", idle: false) == .distraction)
        assert(FocusActivityTotals.classify(plan: plan, app: "chat", domain: nil, idle: false) == .distraction)
        assert(FocusActivityTotals.classify(plan: plan, app: "unknown", domain: nil, idle: false) == .other)
        assert(FocusActivityTotals.classify(plan: plan, app: "editor", domain: nil, idle: true) == .idle)
        var stats = FocusActivityTotals()
        stats.add(.work, seconds: 12)
        stats.add(.distraction, seconds: 3)
        stats.add(.other, seconds: 5)
        stats.add(.idle, seconds: 4)
        stats.add(.work, seconds: -.infinity)
        stats.add(.work, seconds: -1)
        assert(stats.measured == 24 && stats.work == 12 && stats.distraction == 3 && stats.other == 5 && stats.idle == 4)
        for screen in [false, true] {
            for task in [false, true] {
                let destination = TrackingDestinations(screenTimeEnabled: screen, taskActive: task)
                assert(destination.needsObservation == (screen || task))
                assert(destination.screenTimeEnabled == screen)
                assert(destination.taskActive == task)
                let denied = TrackingDestinations(screenTimeEnabled: screen, taskActive: task, permissionsGranted: false)
                assert(!denied.needsObservation) // Tasks must never bypass the permission gate.
            }
        }
        print("PASS: task app classification, blocked sites take priority, idle/other separated, totals and invalid intervals")
    }
}
