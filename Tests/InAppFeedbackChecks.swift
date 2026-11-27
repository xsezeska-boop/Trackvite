import AppKit
@main struct InAppFeedbackChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("trackvite-feedback-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var permission = TrackingPermissionState.denied
        let tracker = ActivityTracker(store: LocalStateStore(url: folder.appendingPathComponent("state.json")), permissionProbe: { permission })
        tracker.toggle() // Start tracking must reach the model even when access is missing.
        assert(!tracker.isTracking && tracker.notice?.action == .settings)
        assert(tracker.notice?.title == "Permissions required")
        tracker.clearCache()
        let first = tracker.notice!.id
        tracker.clearCache()
        let second = tracker.notice!.id
        tracker.dismissNotice(first)
        assert(tracker.notice?.id == second) // An old dismissal cannot hide a newer action.
        tracker.screenEnabled = true
        assert(tracker.notice?.action == .settings)
        permission = TrackingPermissionState(accessibility: true, screen: true, browser: true)
        tracker.refreshPermissions()
        tracker.featureFeedback("Restriction saved", requiresScreenTime: true)
        assert(tracker.notice?.detail.contains("Enable Screen Time") == true && tracker.notice?.action == .startTracking)
        assert(!tracker.isTracking) // Notifications must not silently enable capture.
        let prompt = tracker.notice!.id
        permission.screen = false
        assert(tracker.performNoticeAction(prompt) == "Settings")
        assert(!tracker.isTracking && tracker.notice?.action == .settings) // Recheck permission at action time.
        tracker.focus.add(FocusPlan(title: "Guidance test", detail: "", start: Date(), minutes: 10, daily: false, blockedApps: [], blockedSites: []))
        assert(tracker.notice?.action == .settings)
        assert(tracker.focus.plans.isEmpty && tracker.focus.active.isEmpty) // Denied Start must not create a running task.
        tracker.limits.add(apps: [], sites: ["example.com"], minutes: 0)
        assert(tracker.notice?.action == .settings)
        tracker.limits.remove(tracker.limits.rules[0])
        assert(tracker.notice?.title == "Restriction removed")
        tracker.flushSavedState(); tracker.focus.shutdown()
        print("PASS: repeat actions, stale dismissal safety, Screen Time guidance, no silent activation, permission recheck on toast action, task and restriction feedback")
    }
}
