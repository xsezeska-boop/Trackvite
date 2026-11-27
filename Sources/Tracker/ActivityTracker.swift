import AppKit
import ApplicationServices
import ScreenCaptureKit

import Combine

struct ActivitySample: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let app: String
    let bundleID: String
    let title: String
    let seconds: Double
    let idle: Bool
}

struct ApplicationActivity: Identifiable {
    let id: String
    let name: String
    let active: Double
    let idle: Double
    var total: Double { active + idle }
}

struct AppUsage: Identifiable {
    let id: String
    let name: String
    let seconds: Double
}

@MainActor
final class ActivityTracker: ObservableObject {
    @Published private(set) var isTracking = false
    @Published private(set) var trackingPermissions = TrackingPermissionState.denied
    var trackingAllowed: Bool { trackingPermissions.allowed }
    @Published private(set) var notice: InAppNotice?
    @Published private(set) var samples: [ActivitySample] = []
    @Published private(set) var currentApp = "Ready"
    @Published private(set) var currentTitle = "Start tracking to see your activity."
    @Published private(set) var latestText = "Screen text is off."
    @Published var screenEnabled = false {
        didSet {
            configureStream(); markSavedStateDirty()
            if !restoringState, oldValue != screenEnabled {
                if screenEnabled { featureFeedback("Screen text enabled", requiresScreenTime: true) }
                else { notice = InAppNotice(title: "Screen text disabled") }
            }
        }
    }
    @Published var excludedBundles = "com.apple.keychainaccess, com.1password.1password, com.agilebits.onepassword7" {
        didSet { updateForeground(); configureStream(); markSavedStateDirty() }
    }
    @Published private(set) var screenStats = "Screen text is paused"
    @Published private(set) var status = "Data is saved locally."
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published private(set) var screenGranted = CGPreflightScreenCaptureAccess()
    @Published private(set) var runningApps: [String] = []
    @Published private(set) var currentPage: BrowserPage?
    var currentSite: String? { currentPage?.domain }
    @Published private(set) var siteStatus = "Connect your browser in Settings."
    @Published private(set) var websites: [WebsiteUsage] = []
    let focus = FocusManager()
    let limits = ScreenTimeLimits()
    private var siteLedger = WebsiteLedger()
    private let browserMonitor = BrowserMonitor()
    private var history: [ActivitySample] = []
    private var sleeping = false
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var lastTick = Date()
    private var foreground: NSRunningApplication?
    private let analyzer = LiveScreenAnalyzer()
    private var stream: SCStream?
    private var streamSetup: Task<Void, Never>?
    private var streamVersion = UUID()
    private var destinations: TrackingDestinations { TrackingDestinations(screenTimeEnabled: isTracking, taskActive: !focus.active.isEmpty, permissionsGranted: trackingAllowed) }
    private var collecting: Bool { destinations.needsObservation }
    private var observedSwitches = 0
    private var generation = UUID()
    private var observation: NSObjectProtocol?

    private let permissionProbe: @MainActor () -> TrackingPermissionState
    private var reconcilingPermissions = false
    private let stateStore: LocalStateStore
    private let saveQueue = DispatchQueue(label: "trackvite.local-state", qos: .utility)
    private var saveTimer: Timer?
    private var stateDirty = false
    private var restoringState = true
    private var persistenceReady = true

    init(store: LocalStateStore = LocalStateStore(), permissionProbe: @escaping @MainActor () -> TrackingPermissionState = { TrackingPermissionState.current() }) {
        self.permissionProbe = permissionProbe
        stateStore = store
        focus.setTrackingAccess(false)
        BrowserRegistry.shared.refresh()
        refreshEnvironment()
        limits.onFeedback = { [weak self] title, required in
            self?.featureFeedback(title, requiresScreenTime: required)
        }
        focus.authorizeStart = { [weak self] in
            guard let self else { return false }
            self.refreshPermissions()
            guard self.trackingAllowed else { self.showPermissionNotice(); return false }
            return true
        }
        focus.executionAllowed = { [weak self] in self?.permissionProbe().allowed == true }
        focus.onFeedback = { [weak self] title in
            guard let self, !self.restoringState else { return }
            if title == "Permissions required" || (!self.focus.active.isEmpty && !self.trackingAllowed) { self.showPermissionNotice() }
            else { self.notice = InAppNotice(title: title) }
        }
        limits.onDeadline = { [weak self] in self?.refreshLiveDisplay() }
        limits.onChange = { [weak self] in
            guard let self else { return }
            if self.collecting { self.account() }
            self.checkLimits()
            self.markSavedStateDirty()
        }
        focus.beforeStateChange = { [weak self] in
            guard let self, self.collecting else { return }
            self.account()
        }
        focus.onStateChange = { [weak self] in
            guard let self else { return }
            self.markSavedStateDirty()
            self.refreshPermissions()
            self.syncObservation()
            self.updateBrowserMonitor(for: NSWorkspace.shared.frontmostApplication)
            if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier == self.foreground?.processIdentifier {
                self.focus.check(app: app, domain: self.currentSite)
            }
        }
        browserMonitor.onPage = { [weak self] page, message, readable in
            guard let self else { return }
            self.refreshPermissions()
            guard self.trackingAllowed, !self.sleeping,
                  let app = NSWorkspace.shared.frontmostApplication,
                  BrowserMonitor.browsers.contains(app.bundleIdentifier ?? "") else { return }
            if self.focus.browserStatus != message { self.focus.browserStatus = message }
            self.focus.check(app: app, domain: page?.domain, domainResolved: true, siteReadable: readable)
            guard self.collecting, !self.excluded(app), self.foreground?.processIdentifier == app.processIdentifier else { return }
            if self.currentPage != page {
                self.account()
                self.currentPage = page
                if self.isTracking, let page { self.siteLedger.add(page, seconds: 0) }
                self.publishHistory()
            }
            self.checkLimits()
            if self.siteStatus != message { self.siteStatus = message }
        }
        analyzer.onText = { [weak self] token, text, stats in
            Task { @MainActor in
                guard let self, self.permissionProbe().allowed, self.trackingAllowed, self.isTracking, self.screenEnabled, self.generation == token,
                      let app = self.foreground, !self.excluded(app),
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
                self.latestText = text.isEmpty ? "No text detected." : text
                self.screenStats = stats
            }
        }
        analyzer.onError = { [weak self] message in
            Task { @MainActor in self?.screenStats = "Capture stopped: \(message)" }
        }
        let center = NSWorkspace.shared.notificationCenter
        lifecycleObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.account()
                self.browserMonitor.stop()
                self.flushSavedState()
                self.sleeping = true
                self.configureStream()
            }
        })
        lifecycleObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sleeping = false
                self.lastTick = Date()
                self.updateBrowserMonitor(for: NSWorkspace.shared.frontmostApplication)
                self.configureStream()
            }
        })
        lifecycleObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions(); self?.retryBrowserAccess(); self?.publishHistory() }
        })
        observation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.activate(app) }
        }
        lifecycleObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushSavedState() }
        })
        do {
            if let state = try stateStore.load() {
                history = state.history
                siteLedger = state.sites
                observedSwitches = state.switches
                screenEnabled = state.screenText
                excludedBundles = state.exclusions
                limits.restore(state)
                focus.restore(state)
                publishHistory()
                lastTick = Date() // Never account time while the application was closed.
                setTracking(state.tracking)
            }
        } catch {
            persistenceReady = false // Preserve an unreadable file; never silently overwrite it.
            notice = InAppNotice(title: "Saved data could not be loaded. Existing file was kept.", symbol: "exclamationmark.triangle.fill")
        }
        restoringState = false
        refreshPermissions()
    }

    var activeSeconds: Double { samples.filter { !$0.idle }.reduce(0) { $0 + $1.seconds } }
    var idleSeconds: Double { samples.filter(\.idle).reduce(0) { $0 + $1.seconds } }
    var switches: Int { observedSwitches }
    var currentBundleID: String? { foreground?.bundleIdentifier }
    var usage: [AppUsage] {
        let apps = Dictionary(grouping: samples.filter { !$0.idle && !BrowserMonitor.browsers.contains($0.bundleID) }, by: \.bundleID)
            .map { AppUsage(id: $0.key, name: $0.value.first?.app ?? "Unknown app", seconds: $0.value.reduce(0) { $0 + $1.seconds }) }
        let pages = websites.map { AppUsage(id: "page:" + $0.id, name: $0.page.title, seconds: $0.seconds) }
        return (apps + pages).sorted { $0.seconds > $1.seconds }
    }
    var applicationActivity: [ApplicationActivity] {
        Dictionary(grouping: samples.filter { !BrowserMonitor.browsers.contains($0.bundleID) }, by: \.bundleID).map { bundle, entries in
            ApplicationActivity(id: bundle, name: entries.first?.app ?? "Unknown app",
                active: entries.filter { !$0.idle }.reduce(0) { $0 + $1.seconds },
                idle: entries.filter { $0.idle }.reduce(0) { $0 + $1.seconds })
        }.sorted {
            $0.name == $1.name ? $0.id < $1.id : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    var environment: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion) · CPU cores: \(ProcessInfo.processInfo.activeProcessorCount) · memory: \(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB"
    }

    func toggle() { setTracking(!isTracking) }
    private func setTracking(_ enabled: Bool) {
        refreshPermissions()
        guard !enabled || trackingAllowed else {
            showPermissionNotice()
            return
        }
        guard enabled != isTracking else { return }
        if collecting { account() }
        isTracking = enabled
        markSavedStateDirty()
        limits.setEnabled(enabled)
        generation = UUID()
        syncObservation()
        configureStream()
        status = enabled ? "Screen Time is tracking." : "Screen Time is paused."
        publishHistory()
        if !restoringState {
            notice = InAppNotice(title: enabled ? "Screen Time enabled" : "Screen Time paused",
                symbol: enabled ? "play.circle.fill" : "pause.circle.fill",
                detail: enabled ? "" : "Daily restrictions and screen text are paused.")
        }
    }
    private func syncObservation() {
        if collecting {
            if timer == nil {
                lastTick = Date()
                if let app = NSWorkspace.shared.frontmostApplication { activate(app) }
                timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.heartbeat() }
                }
                timer?.tolerance = 5
            }
        } else {
            timer?.invalidate(); timer = nil
            browserMonitor.stop(); currentPage = nil; foreground = nil
        }
        updateBrowserMonitor(for: NSWorkspace.shared.frontmostApplication)
    }

    private var idle: Bool {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState,
            eventType: CGEventType(rawValue: UInt32.max)!) >= 60
    }

    private func account() {
        let now = Date()
        let intervalStart = lastTick
        let elapsed = now.timeIntervalSince(lastTick)
        lastTick = now
        refreshPermissions()
        guard collecting, !sleeping, let app = foreground, !excluded(app), elapsed > 0, elapsed < 60 else { return }
        let isIdle = idle
        markSavedStateDirty()
        if isTracking {
            record(app: app, seconds: elapsed, isIdle: isIdle)
            limits.record(from: intervalStart, to: now, app: app.bundleIdentifier ?? "", domain: currentSite, idle: isIdle)
        }
        focus.recordActivity(from: intervalStart, to: now, app: app.bundleIdentifier ?? "pid:\(app.processIdentifier)", domain: currentSite, idle: isIdle, appName: app.localizedName ?? "App")
        if isTracking, let currentPage, BrowserMonitor.browsers.contains(app.bundleIdentifier ?? "") {
            siteLedger.add(currentPage, seconds: elapsed)
        }
    }

    var taskActivityKind: FocusActivityKind? {
        guard collecting, let plan = focus.active.first, let app = foreground, !excluded(app) else { return nil }
        return FocusActivityTotals.classify(plan: plan, app: app.bundleIdentifier ?? "pid:\(app.processIdentifier)", domain: currentSite, idle: idle)
    }

    private func record(app: NSRunningApplication, seconds: Double, isIdle: Bool) {
        let bundle = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
        // Accumulate by app identity and idle category, never by visit/window.
        if let index = history.firstIndex(where: { $0.bundleID == bundle && $0.idle == isIdle }) {
            let previous = history[index]
            history[index] = ActivitySample(id: previous.id, date: previous.date,
                app: previous.app, bundleID: bundle, title: currentTitle,
                seconds: previous.seconds + seconds, idle: isIdle)
        } else {
            history.append(ActivitySample(date: Date(), app: String((app.localizedName ?? "Unknown app").prefix(256)),
                bundleID: bundle, title: currentTitle, seconds: seconds, idle: isIdle))
        }
        if history.count > 720 { history.removeFirst(history.count - 720) }
    }

    private func activate(_ app: NSRunningApplication) {
        if let url = app.bundleURL { BrowserRegistry.shared.register(url) }
        refreshPermissions()
        guard trackingAllowed else { return }
        focus.foregroundChanged(app)
        guard collecting else { updateBrowserMonitor(for: app); return }
        account() // Finish the PREVIOUS app before switching, including sub-second visits.
        if isTracking, let previous = foreground, previous.processIdentifier != app.processIdentifier,
           !excluded(previous), !excluded(app) { observedSwitches += 1 }
        currentPage = nil
        updateBrowserMonitor(for: app)
        foreground = app
        generation = UUID()

        lastTick = Date()
        currentApp = excluded(app) ? "Excluded app" : app.localizedName ?? "Unknown app"
        currentTitle = excluded(app) ? "App excluded from tracking" : String(windowTitle(for: app).prefix(512))
        if app.bundleIdentifier != Bundle.main.bundleIdentifier {
            latestText = excluded(app) ? "App excluded from tracking" : "Waiting for screen changes…"
        }
        if isTracking, !excluded(app) { record(app: app, seconds: 0, isIdle: false) }
        publishHistory()
        checkLimits()
        updateAnalyzerContext()
    }

    private func updateBrowserMonitor(for app: NSRunningApplication?) {
        guard trackingAllowed, !sleeping, let app else { browserMonitor.stop(); return }
        let needsFocus = !focus.active.isEmpty
        browserMonitor.start((isTracking && !excluded(app)) || needsFocus ? app : nil)
    }

    private func heartbeat() {
        guard collecting else { return }
        account()
        checkLimits()
        if NSApplication.shared.isActive { publishHistory() }
        if NSApplication.shared.isActive, let app = foreground, !excluded(app) {
            let title = String(windowTitle(for: app).prefix(512))
            if title != currentTitle {
                currentTitle = title

            }
        }

    }

    // Called once a second only by a visible dashboard. No capture, OCR or AX calls.
    func refreshLiveDisplay() {
        refreshPermissions()
        guard collecting, !sleeping else { return }
        account()
        checkLimits()
        publishHistory()
    }

    private func publishHistory() {
        markSavedStateDirty()
        samples = history
        websites = siteLedger.rows
    }

    private func updateAnalyzerContext() {
        generation = UUID()
        let allowed = trackingAllowed && isTracking && !sleeping && screenEnabled && foreground.map { !excluded($0) && $0.bundleIdentifier != Bundle.main.bundleIdentifier } == true
        analyzer.setContext(generation, enabled: allowed)
    }

    private func configureStream() {
        streamVersion = UUID()
        let version = streamVersion
        streamSetup?.cancel()
        let old = stream
        stream = nil
        analyzer.setContext(UUID(), enabled: false)
        latestText = screenEnabled ? "Waiting for screen changes…" : "Screen text is off."
        screenStats = "Screen text is paused"
        streamSetup = Task {
            if let old { try? await old.stopCapture() }
            guard !Task.isCancelled, version == streamVersion, trackingAllowed, isTracking, !sleeping, screenEnabled else { return }
            guard CGPreflightScreenCaptureAccess() else {
                screenStats = "Allow Screen Recording in Settings to read screen text."
                return
            }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard !Task.isCancelled, version == streamVersion, let display = content.displays.first(where: {
                    $0.displayID == CGMainDisplayID()
                }) else { return }
                let hidden = content.applications.filter { app in
                    app.bundleIdentifier == Bundle.main.bundleIdentifier || excludedBundles.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.contains(app.bundleIdentifier)
                }
                let filter = SCContentFilter(display: display, excludingApplications: hidden, exceptingWindows: [])
                let config = SCStreamConfiguration()
                let scale = min(1.0, 1280.0 / Double(display.width), 800.0 / Double(display.height))
                config.width = max(1, Int(Double(display.width) * scale))
                config.height = max(1, Int(Double(display.height) * scale))
                config.minimumFrameInterval = CMTime(value: 1, timescale: 4)
                config.queueDepth = 3
                config.showsCursor = false
                config.capturesAudio = false
                let live = SCStream(filter: filter, configuration: config, delegate: analyzer)
                try live.addStreamOutput(analyzer, type: .screen, sampleHandlerQueue: analyzer.queue)
                stream = live
                updateAnalyzerContext()
                try await live.startCapture()
                guard !Task.isCancelled, version == streamVersion else {
                    try? await live.stopCapture()
                    return
                }
                screenStats = "Reading text when the screen changes"
            } catch {
                if version == streamVersion { screenStats = "Screen capture unavailable. Error \((error as NSError).code)" }
            }
        }
    }

    private func checkLimits() {
        guard trackingAllowed else { limits.setEnabled(false); return }
        limits.check(app: foreground ?? NSWorkspace.shared.frontmostApplication, domain: currentSite, idle: idle)
    }

    func refreshPermissions() {
        guard !reconcilingPermissions else { return }
        reconcilingPermissions = true
        defer { reconcilingPermissions = false }
        let next = permissionProbe()
        let previous = trackingPermissions
        if next != previous { trackingPermissions = next }
        if accessibilityGranted != next.accessibility { accessibilityGranted = next.accessibility }
        if screenGranted != next.screen { screenGranted = next.screen }
        if (requestedPermission == "Accessibility" && next.accessibility) || (requestedPermission == "ScreenCapture" && next.screen) {
            permissionHelp = ""; requestedPermission = nil
        }
        focus.setTrackingAccess(next.allowed)
        if !next.allowed {
            let wasTracking = isTracking
            if isTracking { isTracking = false }
            limits.setEnabled(false)
            timer?.invalidate(); timer = nil
            browserMonitor.stop()
            currentPage = nil; foreground = nil
            if currentApp != "Permission required" { currentApp = "Permission required" }
            if !currentTitle.isEmpty { currentTitle = "" }
            lastTick = Date()
            if previous.allowed || stream != nil {
                generation = UUID()
                configureStream()
            }
            analyzer.setContext(UUID(), enabled: false)
            let unavailable = "Tracking unavailable until all required permissions are allowed."
            if latestText != unavailable { latestText = unavailable }
            if wasTracking { markSavedStateDirty() }
            if previous.allowed && !restoringState { showPermissionNotice() }
            return
        }
        if !previous.allowed {
            lastTick = Date()
            syncObservation()
        }
        if previous.accessibility != next.accessibility { browserMonitor.retryPermissions() }
        if previous.screen != next.screen { screenRestartMayBeNeeded = false; configureStream() }
    }

    func retryBrowserAccess() {
        refreshPermissions()
        browserMonitor.retryPermissions()
        updateBrowserMonitor(for: NSWorkspace.shared.frontmostApplication)
    }

    func openPrivacy(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + pane) else { return }
        NSWorkspace.shared.open(url)
    }

    @Published private(set) var permissionHelp = ""
    private var requestedPermission: String?

    func showApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func restartApplication() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            Task { @MainActor [weak self] in
                if error == nil { NSApplication.shared.terminate(nil) }
                else { self?.permissionHelp = "Could not restart. Quit and reopen Trackvite." }
            }
        }
    }

    func requestAccessibility() {
        requestedPermission = "Accessibility"
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Accessibility")
        refreshPermissions()
        permissionHelp = accessibilityGranted ? "" : "Enable Trackvite in Accessibility. If it is missing, use + to add this app."
    }

    @Published private(set) var screenRestartMayBeNeeded = false
    func requestScreen() {
        requestedPermission = "ScreenCapture"
        _ = CGRequestScreenCaptureAccess()
        refreshPermissions()
        screenRestartMayBeNeeded = !screenGranted
        if !screenGranted {
            permissionHelp = "Enable Trackvite in Screen Recording, then restart if macOS asks."
            openPrivacy("ScreenCapture")
        }
    }

    func refreshEnvironment() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName).sorted()
    }

    private func excluded(_ app: NSRunningApplication) -> Bool {
        let exclusions = excludedBundles.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return exclusions.contains(app.bundleIdentifier ?? "")
    }

    func updateForeground() {
        guard collecting, let app = NSWorkspace.shared.frontmostApplication else { return }
        account()
        currentPage = nil
        updateBrowserMonitor(for: app)
        if excluded(app) {
            currentApp = "Excluded app"
            currentTitle = "App excluded from tracking."
            latestText = "Text hidden for excluded app."
        } else {
            currentApp = app.localizedName ?? "Unknown app"
            currentTitle = windowTitle(for: app)
        }
    }

    private func windowTitle(for app: NSRunningApplication) -> String {
        guard AXIsProcessTrusted() else { return "Allow Accessibility to read window titles." }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.3)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return "No window available" }
        var title: CFTypeRef?
        let focusedWindow = unsafeBitCast(window, to: AXUIElement.self)
        guard AXUIElementCopyAttributeValue(focusedWindow, kAXTitleAttribute as CFString, &title) == .success else {
            return "Window title unavailable"
        }
        return title as? String ?? "Untitled window"
    }

    func showPermissionNotice() {
        let detail: String
        if !trackingPermissions.accessibility { detail = "Allow Accessibility in Settings to enable tracking." }
        else if !trackingPermissions.screen { detail = "Allow Screen Recording in Settings to enable tracking." }
        else { detail = "Open and connect a supported browser in Settings." }
        notice = InAppNotice(title: "Permissions required", symbol: "lock.fill", detail: detail, action: .settings)
    }

    func featureFeedback(_ title: String, requiresScreenTime: Bool) {
        guard !restoringState else { return }
        if requiresScreenTime { refreshPermissions() }
        if requiresScreenTime && !isTracking {
            notice = InAppNotice(title: title, symbol: "info.circle.fill",
                detail: "Enable Screen Time to use this feature.", action: trackingAllowed ? .startTracking : .settings)
            if !trackingAllowed { showPermissionNotice() }
        } else { notice = InAppNotice(title: title) }
    }

    func checkAccessWithFeedback() {
        retryBrowserAccess()
        if trackingAllowed { notice = InAppNotice(title: "All required permissions are allowed") }
        else { showPermissionNotice() }
    }

    func performNoticeAction(_ id: UUID) -> String? {
        guard let current = notice, current.id == id, let action = current.action else { return nil }
        notice = nil
        switch action {
        case .settings: return "Settings"
        case .screenTime: return "Screen Time"
        case .startTracking:
            setTracking(true)
            return trackingAllowed ? "Screen Time" : "Settings"
        }
    }

    func dismissNotice(_ id: UUID) {
        guard notice?.id == id else { return }
        notice = nil
    }

    private func snapshot() -> SavedState {
        SavedState(tracking: isTracking, screenText: screenEnabled, exclusions: excludedBundles,
                   history: history, sites: siteLedger, switches: observedSwitches,
                   plans: focus.plans, taskTotals: focus.activity, taskApps: focus.applications,
                   rules: limits.rules, budget: limits.budget)
    }

    private func markSavedStateDirty() {
        guard !restoringState, persistenceReady else { return }
        stateDirty = true
        guard saveTimer == nil else { return }
        saveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.saveTimer = nil
                self.saveState(synchronous: false)
            }
        }
        saveTimer?.tolerance = 3
    }

    private func saveState(synchronous: Bool) {
        guard persistenceReady, !restoringState else { return }
        guard stateDirty else {
            if synchronous { saveQueue.sync {} }
            return
        }
        stateDirty = false
        let state = snapshot()
        let store = stateStore
        if synchronous {
            saveQueue.sync {
                do { try store.save(state) }
                catch { stateDirty = true; notice = InAppNotice(title: "Could not save local data", symbol: "exclamationmark.triangle.fill") }
            }
        } else {
            saveQueue.async { [weak self] in
                do { try store.save(state) }
                catch {
                    Task { @MainActor in
                        self?.stateDirty = true
                        self?.notice = InAppNotice(title: "Could not save local data", symbol: "exclamationmark.triangle.fill")
                    }
                }
            }
        }
    }

    func flushSavedState() {
        if collecting { account() }
        saveTimer?.invalidate(); saveTimer = nil
        saveState(synchronous: true)
    }

    func clearCache() {
        ApplicationIcon.clearCache()
        LocalSiteIcons.shared.clearCache()
        notice = InAppNotice(title: "Cache cleared")
    }

    func clearHistory() {
        if collecting { account() }
        updateAnalyzerContext()
        history.removeAll()
        siteLedger.clear()
        publishHistory()
        observedSwitches = 0
        lastTick = Date()
        latestText = "Activity cleared."
    }

}
