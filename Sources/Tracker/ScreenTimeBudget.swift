import Foundation

struct ScreenTimeRule: Identifiable, Equatable {
    let id: String
    let name: String
    let isSite: Bool
    var minutes: Int
    var enabled = true
}

/// Bounded daily counters, separate from task statistics and the clearable activity view.
struct ScreenTimeBudget {
    private(set) var day: Date = .distantPast
    private var apps: [String: Double] = [:]
    private var sites: [String: Double] = [:]
    mutating func rollDay(_ now: Date, calendar: Calendar = .current) {
        let next = calendar.startOfDay(for: now)
        if next != day { day = next; apps.removeAll(); sites.removeAll() }
    }
    mutating func record(from: Date, to: Date, app: String, domain: String?, idle: Bool, calendar: Calendar = .current) {
        rollDay(to, calendar: calendar)
        let seconds = to.timeIntervalSince(max(from, day))
        guard !idle, seconds.isFinite, seconds > 0 else { return }
        if apps[app] != nil || apps.count < 512 { apps[app, default: 0] += seconds }
        if let domain, sites[domain] != nil || sites.count < 512 { sites[domain, default: 0] += seconds }
    }
    func used(_ rule: ScreenTimeRule) -> Double {
        if !rule.isSite { return apps[rule.id] ?? 0 }
        return sites.reduce(0) { $0 + (($1.key == rule.id || $1.key.hasSuffix("." + rule.id)) ? $1.value : 0) }
    }
    func remaining(_ rule: ScreenTimeRule) -> Double { max(0, Double(rule.minutes * 60) - used(rule)) }
    func matches(_ rule: ScreenTimeRule, app: String, domain: String?) -> Bool {
        guard rule.enabled else { return false }
        if !rule.isSite { return rule.id == app }
        guard let domain else { return false }
        return domain == rule.id || domain.hasSuffix("." + rule.id)
    }
}
