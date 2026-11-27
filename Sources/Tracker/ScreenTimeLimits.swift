import AppKit
import SwiftUI
import Combine

@MainActor
final class ScreenTimeLimits: ObservableObject {
    @Published private(set) var rules: [ScreenTimeRule] = []
    @Published private(set) var budget = ScreenTimeBudget()
    @Published private(set) var message = ""
    var onFeedback: ((String, Bool) -> Void)?
    var onDeadline: (() -> Void)?
    var onChange: (() -> Void)?
    private var enabled = false
    private var panels: [NSPanel] = []
    private var shown: String?
    private var deadline: Timer?
    private var job: Task<Void, Never>?
    private var version = UUID()

    func restore(_ state: SavedState) {
        rules = state.rules
        budget = state.budget
        budget.rollDay(Date())
    }
    func add(apps: [FocusAppItem], sites: Set<String>, minutes: Int) {
        guard (0...1440).contains(minutes) else { return }
        let targets = apps.filter { !BrowserMonitor.browsers.contains($0.id) }.map {
            ScreenTimeRule(id: $0.id, name: $0.name, isSite: false, minutes: minutes)
        } + sites.sorted().map { ScreenTimeRule(id: $0, name: $0, isSite: true, minutes: minutes) }
        for rule in targets {
            if let i = rules.firstIndex(where: { $0.id == rule.id && $0.isSite == rule.isSite }) { rules[i] = rule }
            else if rules.count < 64 { rules.append(rule) }
        }
        changed()
        onFeedback?("Restriction saved", true)
    }
    func remove(_ rule: ScreenTimeRule) { rules.removeAll { $0.id == rule.id && $0.isSite == rule.isSite }; changed(); onFeedback?("Restriction removed", false) }
    func toggle(_ rule: ScreenTimeRule) {
        guard let i = rules.firstIndex(of: rule) else { return }
        rules[i].enabled.toggle(); changed()
        onFeedback?(rules[i].enabled ? "Restriction enabled" : "Restriction disabled", rules[i].enabled)
    }
    private func changed() {
        version = UUID(); job?.cancel(); job = nil
        dismiss(); message = ""; onChange?()
    }
    func record(from: Date, to: Date, app: String, domain: String?, idle: Bool) {
        guard enabled else { return }
        var next = budget
        next.record(from: from, to: to, app: app, domain: domain, idle: idle)
        budget = next
    }
    func setEnabled(_ value: Bool) {
        enabled = value
        if !value { version = UUID(); job?.cancel(); job = nil; dismiss(); deadline?.invalidate(); deadline = nil }
    }
    func check(app: NSRunningApplication?, domain: String?, idle: Bool = false) {
        deadline?.invalidate(); deadline = nil
        var next = budget; next.rollDay(Date()); budget = next
        guard enabled, let app, let bundle = app.bundleIdentifier,
              bundle != Bundle.main.bundleIdentifier else { dismiss(); return }
        let matching = rules.filter { budget.matches($0, app: bundle, domain: domain) }
        if let rule = matching.first(where: { budget.remaining($0) <= 0 }) {
            if rule.isSite { dismiss(); closeSite(app: app, rule: rule) }
            else { show(rule) }
        } else {
            dismiss()
            if !idle, let seconds = matching.map({ budget.remaining($0) }).min(), seconds > 0 {
                deadline = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
                    Task { @MainActor in self?.onDeadline?() }
                }
            }
        }
    }
    private func closeSite(app: NSRunningApplication, rule: ScreenTimeRule) {
        guard job == nil, let bundle = app.bundleIdentifier else { return }
        let token = version
        job = Task {
            defer { if token == version { job = nil } }
            let (page, failure) = await Task.detached(priority: .utility) { BrowserTabInterrupter.read(bundle) }.value
            guard token == version, enabled, !Task.isCancelled else { return }
            guard let page else { report(failure); return }
            guard let domain = WebsiteLedger.domain(page.url),
                  rules.contains(where: { budget.matches($0, app: bundle, domain: domain) && budget.remaining($0) <= 0 }),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
            let result = await Task.detached(priority: .utility) { BrowserTabInterrupter.closeTab(bundle, expected: page.url) }.value
            guard token == version, !Task.isCancelled else { return }
            report(result)
        }
    }
    private func report(_ result: BrowserTabInterrupter.Result) {
        switch result {
        case .changed: message = "Daily limit reached. The active site tab was closed."
        case .denied: message = "Allow browser access in Settings to enforce website limits."
        case .unsupported: message = "Tab limits support Safari and Chrome-based browsers."
        case .failed: message = "Could not close the tab. Check browser access in Settings."
        case .stale: break
        }
    }
    private func dismiss() {
        guard shown != nil else { return }
        shown = nil; panels.forEach { $0.orderOut(nil) }
    }
    private func show(_ rule: ScreenTimeRule) {
        guard shown != rule.id else { return }
        shown = rule.id
        if panels.count != NSScreen.screens.count {
            panels.forEach { $0.orderOut(nil) }
            panels = NSScreen.screens.map { screen in
                let panel = LimitPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.level = .floating; panel.hidesOnDeactivate = false
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                panel.isReleasedWhenClosed = false
                return panel
            }
        }
        for (panel, screen) in zip(panels, NSScreen.screens) {
            panel.setFrame(screen.frame, display: false)
            panel.contentView = FirstClickHostingView(rootView: LimitReachedView(rule: rule) { [weak self] in self?.toggle(rule) }.preferredColorScheme(.dark))
            panel.orderFrontRegardless()
        }
        panels.first?.makeKey()
    }
}
private final class LimitPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
private struct LimitReachedView: View {
    let rule: ScreenTimeRule
    let disable: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            ApplicationIcon(bundleID: rule.id, name: rule.name)
            Text(rule.minutes == 0 ? "App blocked" : "Daily limit reached").font(.title)
            Text(rule.name).font(.title3).foregroundStyle(.secondary)
            Text(rule.minutes == 0 ? "Blocked until you turn off this limit" : "Available again tomorrow").foregroundStyle(.secondary)
            Button("Turn off limit", action: disable).buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(red: 0.065, green: 0.075, blue: 0.085))
    }
}
