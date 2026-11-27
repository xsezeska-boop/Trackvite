import AppKit
import SwiftUI
import Combine

@MainActor
final class FocusManager: ObservableObject {
    @Published private(set) var plans: [FocusPlan] = []
    @Published private(set) var active: [FocusPlan] = []
    @Published private(set) var message = "Choose a task and a time."
    @Published var browserStatus = "Website blocking requires browser access."
    @Published private(set) var applications: [UUID: [String: TaskApplicationStats]] = [:]
    @Published private(set) var activity: [UUID: FocusActivityTotals] = [:]
    private var trackingAccess = true
    func setTrackingAccess(_ allowed: Bool) {
        guard trackingAccess != allowed else { return }
        trackingAccess = allowed
        if !allowed {
            tabVersion = UUID(); tabJob?.cancel(); tabJob = nil
            dismissReminder(); closeShield()
            active.removeAll()
        } else {
            evaluate()
        }
    }
    var authorizeStart: (() -> Bool)?
    var executionAllowed: (() -> Bool)?
    private func requestStart() -> Bool { authorizeStart?() ?? trackingAccess }
    var onFeedback: ((String) -> Void)?
    var beforeStateChange: (() -> Void)?
    var onStateChange: (() -> Void)?
    private var tabJob: Task<Void, Never>?
    private var tabVersion = UUID()
    private var reminder: NSPanel?
    private var noticeDismissTimer: Timer?
    private var noticeKey: String?
    private var timer: Timer?
    private var skipped: [UUID: Date] = [:]
    private var panels: [NSPanel] = []
    private var presentation = FocusPresentationState()
    private var observers: [NSObjectProtocol] = []
    private var siteState: FocusSiteState = .pending
    private var browserPID: pid_t?
    private var lastForegroundPID: pid_t?

    init() {
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.shutdown() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        })
    }
    func restore(_ state: SavedState) {
        plans = state.plans
        activity = state.taskTotals
        applications = state.taskApps
        evaluate()
    }
    func add(_ input: FocusPlan) {
        var plan = input
        plan.normalizeWorkspace()
        guard plans.count < 100 else { message = "You can keep up to 100 tasks."; return }
        guard !plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...720).contains(plan.minutes) else { return }
        if plan.activeWindow(at: Date()) != nil && !requestStart() { return }
        plans.append(plan)
        evaluate()
        onFeedback?(plan.activeWindow(at: Date()) == nil ? "Task scheduled" : "Task started")
    }
    func update(_ input: FocusPlan) {
        var plan = input
        plan.normalizeWorkspace()
        guard let index = plans.firstIndex(where: { $0.id == plan.id }), (1...720).contains(plan.minutes) else { return }
        if plan.activeWindow(at: Date()) != nil && !requestStart() { return }
        plans[index] = plan
        skipped[plan.id] = nil
        evaluate()
        onFeedback?("Task updated")
    }
    func shutdown() {
        timer?.invalidate()
        tabJob?.cancel()
        dismissReminder()
        closeShield()
        panels.removeAll()
    }
    func remove(_ id: UUID) { plans.removeAll { $0.id == id }; skipped[id] = nil; evaluate(); activity[id] = nil; applications[id] = nil; onFeedback?("Task deleted") }
    func toggle(_ id: UUID) {
        guard let index = plans.firstIndex(where: { $0.id == id }) else { return }
        var next = plans[index]; next.enabled.toggle()
        if next.activeWindow(at: Date()) != nil && !requestStart() { return }
        plans[index] = next
        evaluate()
        onFeedback?(plans[index].enabled ? "Schedule enabled" : "Schedule disabled")
    }
    func complete(_ id: UUID) {
        guard let index = plans.firstIndex(where: { $0.id == id }) else { return }
        var next = plans[index]; next.completed.toggle()
        if next.activeWindow(at: Date()) != nil && !requestStart() { return }
        plans[index] = next
        evaluate()
    }
    func startNow(_ id: UUID) {
        guard let index = plans.firstIndex(where: { $0.id == id }), requestStart() else { return }
        plans[index].start = Date()
        plans[index].enabled = true
        plans[index].completed = false
        skipped[id] = nil
        evaluate()
        onFeedback?("Task started")
    }
    func finishTask(_ id: UUID) {
        guard let index = plans.firstIndex(where: { $0.id == id }), !plans[index].completed else { return }
        plans[index].completed = true
        evaluate()
        onFeedback?("Task finished")
    }
    func stopCurrent() {
        let now = Date()
        for plan in active { skipped[plan.id] = plan.activeWindow(at: now)?.end }
        evaluate()
    }
    func evaluate() {
        beforeStateChange?()
        timer?.invalidate()
        tabVersion = UUID()
        tabJob?.cancel()
        tabJob = nil
        dismissReminder()
        noticeKey = nil
        let previous = Set(active.map(\.id))
        let now = Date()
        skipped = skipped.filter { $0.value > now }
        let eligible = plans.filter { $0.activeWindow(at: now) != nil && skipped[$0.id] == nil }
        let canExecute = trackingAccess && (executionAllowed?() ?? true)
        active = canExecute ? eligible : []
        if !canExecute, !eligible.isEmpty { onFeedback?("Permissions required") }
        // Preserve an existing shield while rules are recalculated; don't flash it off/on.
        if active.isEmpty { closeShield() }
        if active.isEmpty { message = "No active task." }
        else { message = "Focusing on: \(active.map(\.title).joined(separator: ", ")). Restrictions end automatically." }
        let next = plans.compactMap { $0.nextBoundary(after: now) }.min()
        if let next {
            timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.evaluate() }
            }
            RunLoop.main.add(timer!, forMode: .common)
        }
        onStateChange?()
        if trackingAccess, let app = NSWorkspace.shared.frontmostApplication { check(app: app) }
        if presentation.key == nil, active.contains(where: { !previous.contains($0.id) }) {
            onFeedback?("Task started")
            if trackingAccess && (!NSApplication.shared.isActive || onFeedback == nil) {
                showReminder("Task started", text: "Distractions are blocked for this task.")
            }
        }
    }
    func clearActivity() { activity.removeAll(); applications.removeAll() }
    func recordActivity(from start: Date, to end: Date, app: String, domain: String?, idle: Bool, appName: String) {
        guard trackingAccess, end > start else { return }
        for plan in active {
            guard let window = plan.activeWindow(at: start) ?? plan.activeWindow(at: end.addingTimeInterval(-0.001)) else { continue }
            let seconds = min(end, window.end).timeIntervalSince(max(start, window.start))
            guard seconds > 0 else { continue }
            var totals = activity[plan.id] ?? FocusActivityTotals()
            totals.add(FocusActivityTotals.classify(plan: plan, app: app, domain: domain, idle: idle), seconds: seconds)
            activity[plan.id] = totals
            var apps = applications[plan.id] ?? [:]
            if apps[app] != nil || apps.count < 128 {
                var stats = apps[app] ?? TaskApplicationStats(id: app, name: String(appName.prefix(128)))
                stats.add(kind: FocusActivityTotals.classify(plan: plan, app: app, domain: domain, idle: idle), seconds: seconds, domain: domain)
                apps[app] = stats
                applications[plan.id] = apps
            }
        }
    }
    func check(app: NSRunningApplication, domain: String? = nil, domainResolved: Bool = false, siteReadable: Bool = true) {
        guard trackingAccess, !active.isEmpty, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        if domainResolved || domain != nil {
            browserPID = app.processIdentifier
            siteState = domain.map(FocusSiteState.website) ?? (siteReadable ? .noWebsite : .unavailable)
        }
        let state: FocusSiteState = browserPID == app.processIdentifier ? siteState : .pending
        let decision = FocusSitePolicy.decide(plans: active, bundleID: app.bundleIdentifier ?? "",
            isBrowser: BrowserMonitor.browsers.contains(app.bundleIdentifier ?? ""), state: state)
        let reason: String
        let notice: String?
        switch decision {
        case .allow: closeShield(); return
        case .blockApp: reason = app.localizedName ?? "App"; notice = nil
        case .blockSite:
            closeShield()
            if case .website(let domain) = state { interruptTab(app: app, domain: domain) }
            return
        case .checking:
            closeShield()
            return
        case .permissionRequired:
            closeShield()
            browserStatus = "Tab address unavailable. Allow browser access in Settings."
            return
        }
        showShield(reason: reason, target: "\(app.processIdentifier):\(reason)", notice: notice)
    }
    private func interruptTab(app: NSRunningApplication, domain: String) {
        guard tabJob == nil, let bundle = app.bundleIdentifier else { return }
        let version = tabVersion
        tabJob = Task {
            defer { if version == tabVersion { tabJob = nil } }
            let (page, failure) = await Task.detached(priority: .utility) { BrowserTabInterrupter.read(bundle) }.value
            guard !Task.isCancelled, version == tabVersion, !active.isEmpty else { return }
            guard let page else { reportTabResult(failure, domain: domain); return }
            guard let actual = WebsiteLedger.domain(page.url), active.contains(where: { $0.blocks(domain: actual) }),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
            let result = await Task.detached(priority: .utility) { BrowserTabInterrupter.closeTab(bundle, expected: page.url) }.value
            guard !Task.isCancelled, version == tabVersion else { return }
            reportTabResult(result, domain: actual)
        }
    }
    private func reportTabResult(_ result: BrowserTabInterrupter.Result, domain: String) {
        switch result {
        case .changed:
            browserStatus = "Closed blocked tab: \(domain). Other tabs remain available."
            showReminder("Website blocked", text: "\(domain) · " + (active.first?.title ?? ""))
        case .denied:
            browserStatus = "Allow Trackvite to control this browser in System Settings → Privacy & Security → Automation."
            showReminder("Browser access needed", text: browserStatus)
        case .unsupported:
            browserStatus = "Tab blocking supports Safari and Chrome-based browsers."
        case .failed: browserStatus = "Could not close the tab. Check browser access in Settings."
        case .stale: break // The user already switched to another page: leave it alone.
        }
    }
    func dismissReminder() {
        noticeDismissTimer?.invalidate()
        noticeDismissTimer = nil
        reminder?.orderOut(nil)
        reminder = nil
    }
    private func showReminder(_ title: String, text: String) {
        let key = title + text
        guard noticeKey != key else { return }
        noticeKey = key
        dismissReminder()
        guard let screen = NSScreen.main else { return }
        guard let plan = active.first else { return }
        let panel = NoticePanel(contentRect: NSRect(x: screen.visibleFrame.maxX - 382, y: screen.visibleFrame.maxY - 190, width: 360, height: 168),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = FirstClickHostingView(rootView: FocusNotice(title: title, text: text, task: plan.title,
            finish: { [weak self] in self?.finishTask(plan.id) }, dismiss: { [weak self] in self?.dismissReminder() }).preferredColorScheme(.dark))
        reminder = panel
        panel.orderFrontRegardless()
        noticeDismissTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismissReminder() }
        }
    }
    func foregroundChanged(_ app: NSRunningApplication) {
        guard trackingAccess else { return }
        let changed = lastForegroundPID != app.processIdentifier
        lastForegroundPID = app.processIdentifier
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        if changed { siteState = .pending; browserPID = app.processIdentifier }
        check(app: app)
    }
    private func closeShield() {
        guard presentation.set(nil) != .none else { return }
        for panel in panels { panel.orderOut(nil) }
    }
    private func showShield(reason: String, introduction: Bool = false, target: String = "intro", notice: String? = nil) {
        guard let plan = active.first else { return }
        let end = active.compactMap { $0.activeWindow(at: Date())?.end }.max() ?? Date()
        let key = active.map { $0.id.uuidString + $0.title + $0.detail }.sorted().joined(separator: ",")
            + ":" + target + ":" + String(end.timeIntervalSinceReferenceDate)
        guard presentation.set(key) != .none else { return }
        let screens = NSScreen.screens
        if panels.count != screens.count {
            for panel in panels { panel.orderOut(nil) }
            panels = screens.map { screen in
                let panel = FocusPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.level = .floating
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                return panel
            }
        }
        for (panel, screen) in zip(panels, screens) {
            panel.setFrame(screen.frame, display: false)
            panel.contentView = FirstClickHostingView(rootView: FocusShield(title: plan.title, detail: plan.detail,
                reason: reason, introduction: introduction, notice: notice, end: end, finish: { [weak self] in self?.finishTask(plan.id) }).preferredColorScheme(.dark)
                .environment(\.locale, Locale(identifier: "en_GB")))
            panel.orderFrontRegardless()
        }
        // A non-activating panel takes keyboard focus without activating Tracker or hiding the source app.
        panels.first?.makeKey()
    }

}

private final class FocusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct FocusShield: View {
    let title: String
    let detail: String
    let reason: String
    let introduction: Bool
    let notice: String?
    let end: Date
    let finish: () -> Void
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "scope").font(.system(size: 56)).foregroundStyle(.green)
            Text("Time to focus").font(.title2)
            Text(title).font(.system(size: 34, weight: .semibold)).multilineTextAlignment(.center)
            if !detail.isEmpty { Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            Text(introduction ? "Your task has started." : "«\(reason)» is blocked").foregroundStyle(.secondary)
            if let notice { Text(notice).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.center).frame(maxWidth: 650) }
            Text("Blocked until \(end.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "en_GB"))))")
            Button("Finish task", action: finish).buttonStyle(.borderedProminent).tint(.green)
            Text("Your app stays open.").font(.caption).foregroundStyle(.secondary)
        }.padding(60).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.06, green: 0.08, blue: 0.09))
    }
}
