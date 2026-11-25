import AppKit
import Combine

struct FocusAppItem: Identifiable, Sendable {
    let id: String
    let name: String
    let running: Bool
}

@MainActor
final class FocusAppCatalog: ObservableObject {
    static let shared = FocusAppCatalog()
    @Published private(set) var apps: [FocusAppItem] = []
    @Published private(set) var loading = false
    private var loaded = false

    func load() async {
        guard !loaded, !loading else { return }
        loading = true
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
            .compactMap { app -> FocusAppItem? in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { return nil }
                return FocusAppItem(id: id, name: app.localizedName ?? id, running: true)
            }
        apps = running.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let ownID = Bundle.main.bundleIdentifier
        let found = await Task.detached(priority: .utility) {
            var result: [String: FocusAppItem] = [:]
            var budget = 600
            func scan(_ folder: URL, depth: Int) {
                guard budget > 0, let files = try? FileManager.default.contentsOfDirectory(at: folder,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return }
                for file in files where budget > 0 {
                    budget -= 1
                    if file.pathExtension.lowercased() == "app" {
                        guard let bundle = Bundle(url: file), let id = bundle.bundleIdentifier, id != ownID else { continue }
                        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                            ?? file.deletingPathExtension().lastPathComponent
                        result[id] = FocusAppItem(id: id, name: name, running: false)
                    } else if depth < 2, let values = try? file.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                              values.isDirectory == true, values.isSymbolicLink != true {
                        scan(file, depth: depth + 1)
                    }
                }
            }
            for root in [URL(fileURLWithPath: "/Applications"),
                         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
                         URL(fileURLWithPath: "/System/Applications")] { scan(root, depth: 0) }
            for app in running { result[app.id] = app }
            return result.values.sorted {
                if $0.running != $1.running { return $0.running }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }.value
        apps = found
        loading = false
        loaded = true
    }
}
