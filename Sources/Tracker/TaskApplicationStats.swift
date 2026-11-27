import Foundation

struct TaskApplicationStats: Identifiable, Codable {
    let id: String
    let name: String
    var totals = FocusActivityTotals()
    var sites: [String: FocusActivityTotals] = [:]
    mutating func add(kind: FocusActivityKind, seconds: Double, domain: String?) {
        guard seconds.isFinite, seconds > 0 else { return }
        totals.add(kind, seconds: seconds)
        if let domain, sites[domain] != nil || sites.count < 32 {
            var stats = sites[domain] ?? FocusActivityTotals()
            stats.add(kind, seconds: seconds)
            sites[domain] = stats
        }
    }
}

struct TrackingDestinations {
    let screenTimeEnabled: Bool
    let taskActive: Bool
    var permissionsGranted = true
    var needsObservation: Bool { permissionsGranted && (screenTimeEnabled || taskActive) }
}
