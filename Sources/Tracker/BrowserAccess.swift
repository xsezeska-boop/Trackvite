import AppKit
import ApplicationServices
import Combine

struct BrowserAccessStatus: Identifiable, Equatable {
    let id: String
    let name: String
    let code: OSStatus
    var allowed: Bool { code == noErr }
    var label: String { allowed ? "Allowed" : code == -1743 ? "Not allowed" : "Not connected" }
}

@MainActor
final class BrowserAccess: ObservableObject {
    @Published private(set) var browsers: [BrowserAccessStatus] = []
    func refresh() {
        let updated: [BrowserAccessStatus] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier, BrowserMonitor.browsers.contains(id),
                  id != "org.mozilla.firefox", id != "company.thebrowser.Browser" else { return nil }
            return BrowserAccessStatus(id: id, name: app.localizedName ?? id, code: Self.permission(id, request: false))
        }.sorted { $0.name < $1.name }
        if browsers != updated { browsers = updated }
    }
    func connect(_ id: String, completion: @escaping () -> Void) {
        Task {
            _ = await Task.detached(priority: .userInitiated) { Self.permission(id, request: true) }.value
            refresh(); completion()
        }
    }
    nonisolated private static func permission(_ id: String, request: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: id)
        return AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), request)
    }
}
