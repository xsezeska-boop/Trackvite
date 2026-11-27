import AppKit
@main struct PermissionGateChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        for ax in [false, true] {
            for screen in [false, true] {
                for browser in [false, true] {
                    let state = TrackingPermissionState(accessibility: ax, screen: screen, browser: browser)
                    assert(state.allowed == (ax && screen && browser))
                }
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trackvite-permissions-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalStateStore(url: directory.appendingPathComponent("state.json"))
        let plan = FocusPlan(title: "Permission test", detail: "", start: Date().addingTimeInterval(-30), minutes: 60,
                             daily: false, blockedApps: [], blockedSites: [])
        var saved = SavedState()
        saved.tracking = true
        saved.plans = [plan]
        saved.history = [ActivitySample(date: Date(), app: "Editor", bundleID: "editor", title: "", seconds: 100, idle: false)]
        try store.save(saved)
        var permission = TrackingPermissionState.denied
        let tracker = ActivityTracker(store: store, permissionProbe: { permission })
        assert(!tracker.trackingAllowed && !tracker.isTracking)
        assert(tracker.focus.active.isEmpty) // A saved task cannot enter its running state without access.
        tracker.toggle()
        tracker.focus.recordActivity(from: Date().addingTimeInterval(-10), to: Date(), app: "editor", domain: nil, idle: false, appName: "Editor")
        tracker.refreshLiveDisplay()
        assert(!tracker.isTracking && tracker.activeSeconds == 100 && tracker.currentBundleID == nil)
        assert(tracker.focus.activity[plan.id] == nil)
        permission = TrackingPermissionState(accessibility: true, screen: true, browser: false)
        tracker.refreshPermissions(); tracker.toggle()
        assert(!tracker.trackingAllowed && !tracker.isTracking)
        // Test transition to full access without starting a real task/observer.
        tracker.focus.finishTask(plan.id)
        permission.browser = true
        tracker.refreshPermissions()
        assert(tracker.trackingAllowed && !tracker.isTracking)
        tracker.toggle()
        assert(tracker.isTracking)
        permission.screen = false
        tracker.refreshPermissions()
        assert(!tracker.trackingAllowed && !tracker.isTracking && tracker.currentBundleID == nil)
        tracker.flushSavedState()
        let restored = try store.load()!
        assert(restored.history[0].seconds == 100 && !restored.tracking)
        assert(restored.plans[0].completed)
        tracker.focus.shutdown()
        print("PASS: all 8 permission combinations, denied startup and restored sessions, task bypass blocked, missing browser access blocks start, full grant/revocation transitions, no unpermitted statistics persisted")
    }
}
