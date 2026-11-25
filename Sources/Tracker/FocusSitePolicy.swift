enum FocusSiteState: Equatable {
    case pending, unavailable, noWebsite
    case website(String)
}
enum FocusAccessDecision: Equatable { case allow, blockApp, blockSite, checking, permissionRequired }
enum FocusSitePolicy {
    static func decide(plans: [FocusPlan], bundleID: String, isBrowser: Bool, state: FocusSiteState) -> FocusAccessDecision {
        guard !plans.isEmpty else { return .allow }
        if !isBrowser && plans.contains(where: { $0.blockedApps.contains(bundleID) }) { return .blockApp }
        guard isBrowser, plans.contains(where: { !$0.blockedSites.isEmpty }) else { return .allow }
        switch state {
        case .pending: return .checking
        case .unavailable: return .permissionRequired
        case .noWebsite: return .allow
        case .website(let domain): return plans.contains(where: { $0.blocks(domain: domain) }) ? .blockSite : .allow
        }
    }
}
