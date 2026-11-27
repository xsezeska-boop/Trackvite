import Foundation

struct SavedState: Codable {
    var version = 1
    var tracking = false
    var screenText = false
    var exclusions = "com.apple.keychainaccess, com.1password.1password, com.agilebits.onepassword7"
    var history: [ActivitySample] = []
    var sites = WebsiteLedger()
    var switches = 0
    var plans: [FocusPlan] = []
    var taskTotals: [UUID: FocusActivityTotals] = [:]
    var taskApps: [UUID: [String: TaskApplicationStats]] = [:]
    var rules: [ScreenTimeRule] = []
    var budget = ScreenTimeBudget()

    func validate() throws {
        func valid(_ totals: FocusActivityTotals) -> Bool {
            [totals.work, totals.distraction, totals.other, totals.idle, totals.measured].allSatisfy { $0.isFinite && $0 >= 0 }
        }
        guard version == 1, history.count <= 720, sites.totals.count <= 256,
              plans.count <= 100, Set(plans.map(\.id)).count == plans.count,
              taskTotals.count <= 100, taskApps.count <= 100, rules.count <= 64,
              exclusions.count <= 8192, switches >= 0, budget.isValidSavedState,
              history.allSatisfy({ $0.seconds.isFinite && $0.seconds >= 0 && $0.app.count <= 256 && $0.title.count <= 512 }),
              sites.rows.allSatisfy({ $0.seconds.isFinite && $0.seconds >= 0 && $0.page.id.count <= 2048 && $0.page.title.count <= 256 }),
              plans.allSatisfy({ (1...720).contains($0.minutes) && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.title.count <= 256 && $0.detail.count <= 1000 && $0.workApps.count <= 20 && $0.materials.count <= 10 }),
              taskTotals.values.allSatisfy(valid),
              taskApps.values.allSatisfy({ apps in apps.count <= 128 && apps.values.allSatisfy { app in app.sites.count <= 32 && valid(app.totals) && app.sites.values.allSatisfy(valid) } }),
              rules.allSatisfy({ (0...1440).contains($0.minutes) && !$0.id.isEmpty && $0.id.count <= 2048 }),
              Set(rules.map(\.id)).count == rules.count else { throw LocalStateStore.Failure.invalid }
    }
}

/// One bounded JSON snapshot. No database, recordings, cloud or append-only log.
struct LocalStateStore {
    enum Failure: Error { case oversized, invalid }
    static let maxBytes = 12 * 1024 * 1024
    let url: URL
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Trackvite", isDirectory: true).appendingPathComponent("state.json")
    }
    func load() throws -> SavedState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= Self.maxBytes else { throw Failure.oversized }
        let state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
        try state.validate()
        return state
    }
    func save(_ state: SavedState) throws {
        try state.validate()
        let data = try JSONEncoder().encode(state)
        guard data.count <= Self.maxBytes else { throw Failure.oversized }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // The private directory also protects the temporary file used by atomic replacement.
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
