@main
struct FocusSitePolicyChecks {
    static func main() {
        let plan = FocusPlan(title: "Project", detail: "", start: .distantPast, minutes: 60, daily: false,
                             blockedApps: ["com.example.game"], blockedSites: ["youtube.com"])
        func decision(_ state: FocusSiteState, browser: Bool = true, bundle: String = "com.apple.Safari") -> FocusAccessDecision {
            FocusSitePolicy.decide(plans: [plan], bundleID: bundle, isBrowser: browser, state: state)
        }
        assert(decision(.pending) == .checking)
        assert(decision(.unavailable) == .permissionRequired)
        assert(decision(.website("youtube.com")) == .blockSite)
        assert(decision(.website("m.youtube.com")) == .blockSite)
        assert(decision(.website("notyoutube.com")) == .allow)
        assert(decision(.website("example.com")) == .allow)
        assert(decision(.noWebsite) == .allow)
        assert(decision(.pending, browser: false) == .allow)
        assert(decision(.pending, browser: false, bundle: "com.example.game") == .blockApp)
        assert(FocusSitePolicy.decide(plans: [], bundleID: "com.apple.Safari", isBrowser: true, state: .unavailable) == .allow)
        var browserSelected = plan
        browserSelected.blockedApps = ["com.apple.Safari"]
        assert(FocusSitePolicy.decide(plans: [browserSelected], bundleID: "com.apple.Safari", isBrowser: true, state: .website("example.com")) == .allow)
        print("PASS: pending/unreadable states are distinct; browser app selection does not block allowed pages; blocked domains/subdomains, allowed sites, internal tabs, apps, ended session")
    }
}
