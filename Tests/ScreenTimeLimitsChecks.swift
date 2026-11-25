import AppKit
@main struct ScreenTimeLimitsChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let limits = ScreenTimeLimits()
        limits.add(apps: [.init(id: "com.apple.Safari", name: "Safari", running: false),
                          .init(id: "test.editor", name: "Editor", running: false)], sites: ["example.com"], minutes: 1)
        assert(limits.rules.count == 2) // A website limit must never become a whole-browser limit.
        let rule = limits.rules.first { !$0.isSite }!
        let end = Date()
        limits.record(from: end.addingTimeInterval(-10), to: end, app: rule.id, domain: nil, idle: false)
        assert(limits.budget.used(rule) == 0) // Off by default, independent of running tasks.
        limits.setEnabled(true)
        limits.record(from: end.addingTimeInterval(-10), to: end, app: rule.id, domain: nil, idle: false)
        let used = limits.budget.used(rule)
        assert(used > 0 && used <= 10)
        limits.setEnabled(false)
        limits.record(from: end, to: end.addingTimeInterval(10), app: rule.id, domain: nil, idle: false)
        assert(limits.budget.used(rule) == used)
        limits.add(apps: [.init(id: rule.id, name: "Editor", running: false)], sites: [], minutes: 2)
        assert(limits.rules.count == 2 && limits.rules.first { $0.id == rule.id }?.minutes == 2)
        assert(limits.budget.used(rule) == used) // Editing never resets today's allowance.
        limits.remove(limits.rules.first { $0.isSite }!)
        assert(limits.rules.count == 1)
        print("PASS: browsers excluded from app limits, off by default, pause/resume accounting, editing preserves usage, removal")
    }
}
