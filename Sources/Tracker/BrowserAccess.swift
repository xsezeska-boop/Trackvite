import AppKit
import ApplicationServices
import Combine

struct BrowserAccessStatus: Identifiable, Equatable {
    let id: String
    let name: String
    let code: OSStatus
    var embedded = false
    var allowed: Bool { code == noErr }
    var label: String { allowed ? "Allowed" : code == -600 ? "Not running" : code == -25212 ? "Accessibility" : code == -1743 ? "Not allowed" : "Not connected" }
}

@MainActor
final class BrowserAccess: ObservableObject {
    @Published private(set) var browsers: [BrowserAccessStatus] = []
    func refresh() {
        BrowserRegistry.shared.refresh()
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let updated = BrowserRegistry.shared.installed.map { browser in
            BrowserAccessStatus(id: browser.id, name: browser.name,
                code: running.contains(browser.id) ? (browser.scripting == .accessibility ? -25212 : Self.permission(browser.id, request: false)) : -600, embedded: browser.embedded)
        }
        if browsers != updated { browsers = updated }
    }
    func connect(_ id: String, completion: @escaping () -> Void) {
        Task {
            _ = await Task.detached(priority: .userInitiated) { Self.permission(id, request: true) }.value
            refresh(); completion()
        }
    }
    static func trackingAccessAllowed() -> Bool {
        let installed = BrowserRegistry.shared.installed.filter { $0.scripting != .accessibility }
        var codes: [String: OSStatus] = [:]
        for browser in installed { codes[browser.id] = permission(browser.id, request: false) }
        guard codes.values.contains(noErr) else { return false }
        if let current = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           BrowserRegistry.shared.ids.contains(current), BrowserRegistry.shared.scripting(current) != .accessibility {
            return codes[current] == noErr
        }
        return true
    }
    nonisolated private static func permission(_ id: String, request: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: id)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), request)
    }
}
