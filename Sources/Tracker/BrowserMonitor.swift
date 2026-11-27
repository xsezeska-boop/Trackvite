import AppKit
import ApplicationServices

/// Reads browser chrome/document metadata only, never traverses page content.
@MainActor
final class BrowserMonitor {
    nonisolated static var browsers: Set<String> { BrowserRegistry.shared.ids }
    var onPage: ((BrowserPage?, String, Bool) -> Void)?
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var watched: [AXUIElement] = []
    private var timer: Timer?
    private var work: Task<Void, Never>?
    private var bundleID = ""
    private var automationDenied: Set<String> = []
    private var pid: pid_t?
    private var version = UUID()
    private var reading = false
    private var lastRead = Date.distantPast

    func retryPermissions() {
        automationDenied.removeAll()
        // Rebuild AX observers as well as retrying the browser connection.
        let app = pid.flatMap { NSRunningApplication(processIdentifier: $0) }
        stop()
        start(app)
    }

    func start(_ app: NSRunningApplication?) {
        if let url = app?.bundleURL { BrowserRegistry.shared.register(url) }
        if let app, pid == app.processIdentifier { scheduleRead(); return }
        stop()
        guard let app, Self.browsers.contains(app.bundleIdentifier ?? "") else { return }
        bundleID = app.bundleIdentifier ?? ""
        pid = app.processIdentifier
        application = AXUIElementCreateApplication(app.processIdentifier)
        if let application {
            AXUIElementSetMessagingTimeout(application, 0.08)
            var created: AXObserver?
            let callback: AXObserverCallback = { _, _, _, pointer in
                guard let pointer else { return }
                let monitor = Unmanaged<BrowserMonitor>.fromOpaque(pointer).takeUnretainedValue()
                Task { @MainActor in monitor.scheduleRead() }
            }
            if AXObserverCreate(app.processIdentifier, callback, &created) == .success, let created {
                observer = created
                let context = Unmanaged.passUnretained(self).toOpaque()
                for name in [kAXFocusedWindowChangedNotification, kAXFocusedUIElementChangedNotification] {
                    AXObserverAddNotification(created, application, name as CFString, context)
                }
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
            }
        }
        // Fallback for browsers that don't send address/tab accessibility events.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scheduleRead() }
        }
        timer?.tolerance = 1
        scheduleRead()
    }

    func stop() {
        version = UUID()
        work?.cancel()
        work = nil
        timer?.invalidate()
        timer = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        application = nil
        watched = []
        pid = nil
    }

    private func scheduleRead() {
        guard work == nil, !reading, let pid else { return }
        let token = version
        work = Task { [weak self] in
            guard let self else { return }
            let delay = max(0.2, 0.75 - Date().timeIntervalSince(self.lastRead))
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) } catch { return }
            guard token == self.version else { return }
            self.work = nil
            self.reading = true
            self.lastRead = Date()
            let bundle = self.bundleID
            let allowAutomation = !self.automationDenied.contains(bundle)
            let result = await Task.detached(priority: .background) {
                let ax = Self.read(pid)
                if ax.page != nil { return ax }
                return Self.readAutomation(bundle, elements: ax.elements, allowed: allowAutomation)
            }.value
            self.reading = false
            guard token == self.version,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            self.watch(result.elements)
            if result.denied { self.automationDenied.insert(bundle) }
            self.onPage?(result.page, result.message, result.page != nil || result.emptyTab)
        }
    }

    private func watch(_ elements: [AXUIElement]) {
        guard let observer else { return }
        for element in watched {
            for name in [kAXValueChangedNotification, kAXTitleChangedNotification] {
                AXObserverRemoveNotification(observer, element, name as CFString)
            }
        }
        watched = elements
        for element in elements {
            for name in [kAXValueChangedNotification, kAXTitleChangedNotification] {
                AXObserverAddNotification(observer, element, name as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
        }
    }

    private struct Result {
        let page: BrowserPage?
        let elements: [AXUIElement]
        var denied = false
        var emptyTab = false
        var message = "Tab connected"
    }

    nonisolated private static func read(_ pid: pid_t) -> Result {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.08)
        func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var output: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &output) == .success else { return nil }
            return output
        }
        guard let raw = value(app, kAXFocusedWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return Result(page: nil, elements: [], message: "Tab unavailable")
        }
        let window = unsafeBitCast(raw, to: AXUIElement.self)
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var targets = [window]
        let title = String((value(window, kAXTitleAttribute) as? String ?? "").prefix(256))
        var addressPage: BrowserPage?
        let deadline = Date().addingTimeInterval(0.35)
        var index = 0
        while index < queue.count && index < 100 && Date() < deadline {
            let (element, depth) = queue[index]
            index += 1
            let role = value(element, kAXRoleAttribute) as? String ?? ""
            for name in (role == "AXWindow" || role == "AXWebArea") ? [kAXDocumentAttribute, kAXURLAttribute] : [] {
                let rawURL = value(element, name)
                let text = (rawURL as? String) ?? (rawURL as? URL)?.absoluteString
                if let text, let page = BrowserPage.parse(text, title: title) {
                    targets.append(element)
                    return Result(page: page, elements: targets)
                }
            }
            // Do not descend into the web page, including links, forms and passwords.
            if role == "AXWebArea" { continue }
            if role == kAXTextFieldRole || role == kAXComboBoxRole {
                let label = [kAXIdentifierAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute]
                    .compactMap { value(element, $0) as? String }.joined(separator: " ").lowercased()
                if ["address", "адрес", "omnibox", "url", "location"].contains(where: label.contains) {
                    targets.append(element)
                    // Ignore an address being edited; it may not be a loaded page.
                    if (value(element, kAXFocusedAttribute) as? Bool) != true,
                       let text = value(element, kAXValueAttribute) as? String {
                        addressPage = BrowserPage.parse(text, title: title) ?? BrowserPage.parse("https://" + text, title: title)
                    }
                }
                continue
            }
            if depth < 6, let children = value(element, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(max(0, 100 - queue.count)).map { ($0, depth + 1) })
            }
        }
        return Result(page: addressPage, elements: Array(targets.prefix(4)), message: addressPage == nil ? "Tab unavailable" : "Tab connected")
    }
    nonisolated private static func readAutomation(_ bundle: String, elements: [AXUIElement], allowed: Bool) -> Result {
        let safari = BrowserRegistry.shared.scripting(bundle) == .safari
        let chromium = BrowserRegistry.shared.scripting(bundle) == .chromium
        guard safari || chromium else {
            return Result(page: nil, elements: elements, message: "Tab unavailable. Allow Accessibility or use Safari or Chrome.")
        }
        guard allowed else {
            return Result(page: nil, elements: elements, message: "Allow browser access in System Settings → Privacy & Security → Automation.")
        }
        let expression = safari ? "{URL of current tab of front window, name of current tab of front window}" : "{URL of active tab of front window, title of active tab of front window}"
        let source = "with timeout of 2 seconds\ntell application id \(BrowserTabInterrupter.quote(bundle))\nif (count of windows) is 0 then return {}\nreturn \(expression)\nend tell\nend timeout"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let denied = (error[NSAppleScript.errorNumber] as? Int) == -1743
            return Result(page: nil, elements: elements, denied: denied,
                message: denied ? "Allow browser access in Settings." : "Browser tab unavailable (error \(error[NSAppleScript.errorNumber] ?? "unknown")).")
        }
        let url = result?.atIndex(1)?.stringValue ?? ""
        let title = result?.atIndex(2)?.stringValue ?? ""
        let page = BrowserPage.parse(url, title: title)
        return Result(page: page, elements: elements, emptyTab: url.hasPrefix("about:") || url.hasPrefix("chrome:") || url.hasPrefix("edge:") || url.hasPrefix("safari:") || (result != nil && result?.numberOfItems == 0), message: page == nil ? "No website in the active tab." : "Tab connected")
    }

}
