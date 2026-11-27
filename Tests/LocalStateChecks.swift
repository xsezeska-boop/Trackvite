import AppKit
@main struct LocalStateChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("trackvite-state-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalStateStore(url: folder.appendingPathComponent("state.json"))
        let initial = try store.load(); assert(initial == nil)
        let plan = FocusPlan(title: "Restore test", detail: "", start: Date().addingTimeInterval(3600), minutes: 90,
                             daily: true, blockedApps: ["chat"], blockedSites: ["example.com"], workApps: ["editor"])
        var state = SavedState()
        state.plans = [plan]
        state.history = [ActivitySample(date: Date().addingTimeInterval(-86400), app: "Editor", bundleID: "editor", title: "Window", seconds: 125, idle: false)]
        state.taskTotals[plan.id] = FocusActivityTotals(work: 125)
        var app = TaskApplicationStats(id: "editor", name: "Editor")
        app.add(kind: .work, seconds: 125, domain: "example.com")
        state.taskApps[plan.id] = ["editor": app]
        state.rules = [ScreenTimeRule(id: "example.com", name: "example.com", isSite: true, minutes: 0)]
        let page = BrowserPage.parse("https://example.com/path?private=1", title: "Example")!
        state.sites.add(page, seconds: 50)
        let now = Date()
        state.budget.record(from: now.addingTimeInterval(-20), to: now, app: "editor", domain: "example.com", idle: false)
        try store.save(state)
        let loaded = try store.load()!
        assert(loaded.plans[0].id == plan.id && loaded.plans[0].workApps == ["editor"])
        assert(loaded.taskApps[plan.id]?["editor"]?.sites["example.com"]?.work == 125)
        assert(loaded.history[0].seconds == 125 && loaded.sites.rows[0].seconds == 50)
        assert(loaded.rules[0].minutes == 0 && loaded.budget.remaining(loaded.rules[0]) == 0)
        let mode = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as! NSNumber
        assert(mode.intValue == 0o600)
        let tracker = ActivityTracker(store: store)
        assert(tracker.focus.plans[0].id == plan.id && tracker.activeSeconds == 125)
        assert(tracker.limits.rules[0].minutes == 0 && !tracker.isTracking)
        tracker.focus.toggle(plan.id)
        tracker.flushSavedState()
        let flushed = try store.load()!; assert(flushed.plans[0].enabled == false)
        assert(flushed.history[0].seconds == 125) // Offline time was not credited.
        tracker.focus.shutdown()
        let before = try Data(contentsOf: store.url)
        var invalid = state; invalid.version = 999
        do { try store.save(invalid); assertionFailure("Unknown version must not save") } catch {}
        let after = try Data(contentsOf: store.url); assert(after == before)
        try Data("invalid JSON".utf8).write(to: store.url)
        let damaged = ActivityTracker(store: store)
        damaged.flushSavedState()
        let corrupt = try String(contentsOf: store.url, encoding: .utf8); assert(corrupt == "invalid JSON")
        damaged.focus.shutdown()
        try Data(repeating: 0, count: LocalStateStore.maxBytes + 1).write(to: store.url)
        do { _ = try store.load(); assertionFailure("Oversized data must not load") } catch {}
        print("PASS: JSON round-trip, task/app/site statistics, zero limits, private file permissions, real tracker restore/flush, offline accounting, unsupported versions, corruption preservation and size limit")
    }
}
