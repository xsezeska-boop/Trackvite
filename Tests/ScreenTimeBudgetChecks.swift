import Foundation
@main struct ScreenTimeBudgetChecks {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = Date(timeIntervalSince1970: 1_700_006_400) // fixed UTC day boundary
        let day = calendar.startOfDay(for: midnight)
        var budget = ScreenTimeBudget()
        let blocked = ScreenTimeRule(id: "editor", name: "Editor", isSite: false, minutes: 0)
        assert(budget.remaining(blocked) == 0)
        assert(budget.matches(blocked, app: "editor", domain: nil))
        let app = ScreenTimeRule(id: "editor", name: "Editor", isSite: false, minutes: 1)
        var site = ScreenTimeRule(id: "example.com", name: "example.com", isSite: true, minutes: 1)
        budget.record(from: day, to: day.addingTimeInterval(30), app: "editor", domain: "example.com", idle: false, calendar: calendar)
        budget.record(from: day.addingTimeInterval(30), to: day.addingTimeInterval(50), app: "editor", domain: "m.example.com", idle: false, calendar: calendar)
        budget.record(from: day.addingTimeInterval(50), to: day.addingTimeInterval(70), app: "editor", domain: "example.com", idle: true, calendar: calendar)
        assert(budget.used(app) == 50 && budget.used(site) == 50)
        assert(budget.remaining(app) == 10 && budget.remaining(site) == 10)
        assert(budget.matches(site, app: "browser", domain: "deep.m.example.com"))
        assert(!budget.matches(site, app: "browser", domain: "badexample.com"))
        assert(!budget.matches(site, app: "browser", domain: nil))
        site.enabled = false
        assert(!budget.matches(site, app: "browser", domain: "example.com"))
        budget.record(from: day.addingTimeInterval(70), to: day.addingTimeInterval(100), app: "editor", domain: "example.com", idle: false, calendar: calendar)
        assert(budget.remaining(app) == 0)
        budget.rollDay(day.addingTimeInterval(86400), calendar: calendar)
        assert(budget.used(app) == 0 && budget.remaining(app) == 60)
        assert(budget.remaining(blocked) == 0) // Zero allowance stays blocked after midnight.
        // An interval spanning midnight counts only time spent in the new day.
        budget.record(from: day.addingTimeInterval(86390), to: day.addingTimeInterval(86420), app: "editor", domain: nil, idle: false, calendar: calendar)
        assert(budget.used(app) == 20)
        budget.record(from: day.addingTimeInterval(86440), to: day.addingTimeInterval(86430), app: "editor", domain: nil, idle: false, calendar: calendar)
        assert(budget.used(app) == 20)
        print("PASS: cumulative daily budgets, subdomains, idle exclusion, disabled rules, exhaustion, midnight reset and crossing, invalid intervals")
    }
}
