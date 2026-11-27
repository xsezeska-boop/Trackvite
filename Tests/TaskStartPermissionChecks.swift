import AppKit
@main struct TaskStartPermissionChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("trackvite-task-start-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let tracker = ActivityTracker(store: LocalStateStore(url: root.appendingPathComponent("state.json")), permissionProbe: { .denied })
        let immediate = FocusPlan(title: "Blocked start", detail: "", start: Date(), minutes: 10, daily: false, blockedApps: [], blockedSites: [])
        tracker.focus.add(immediate)
        assert(tracker.focus.plans.isEmpty && tracker.focus.active.isEmpty && tracker.notice?.action == .settings)
        let scheduled = FocusPlan(title: "Scheduled", detail: "", start: Date().addingTimeInterval(3600), minutes: 10, daily: false, blockedApps: [], blockedSites: [])
        tracker.focus.add(scheduled)
        assert(tracker.focus.plans.count == 1 && tracker.focus.active.isEmpty)
        tracker.focus.startNow(scheduled.id)
        assert(tracker.focus.plans[0].start == scheduled.start && tracker.focus.active.isEmpty)
        var edited = scheduled; edited.start = Date()
        tracker.focus.update(edited)
        assert(tracker.focus.plans[0].start == scheduled.start)
        var saved = SavedState(); saved.plans = [immediate]
        tracker.focus.restore(saved)
        tracker.focus.evaluate() // Scheduled timer / restored session path must also be gated.
        assert(tracker.focus.active.isEmpty)
        tracker.focus.recordActivity(from: Date().addingTimeInterval(-5), to: Date(), app: "editor", domain: nil, idle: false, appName: "Editor")
        assert(tracker.focus.activity.isEmpty)
        tracker.flushSavedState(); tracker.focus.shutdown()
        print("PASS: denied new task, Start existing task, editing into active window, restored task, scheduled evaluation and accounting; future schedules remain editable")
    }
}
