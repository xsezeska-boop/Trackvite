import Foundation

@main
struct FocusPlanChecks {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        }
        var plan = FocusPlan(title: "Проект", detail: "", start: date(25, 12), minutes: 50,
                             daily: false, blockedApps: ["org.test.social"], blockedSites: ["vk.com"])
        assert(plan.activeWindow(at: date(25, 11, 59), calendar: calendar) == nil)
        assert(plan.activeWindow(at: date(25, 12), calendar: calendar) != nil)
        assert(plan.activeWindow(at: date(25, 12, 49), calendar: calendar) != nil)
        assert(plan.activeWindow(at: date(25, 12, 50), calendar: calendar) == nil)
        assert(plan.nextBoundary(after: date(25, 11), calendar: calendar) == date(25, 12))
        assert(plan.nextBoundary(after: date(25, 12), calendar: calendar) == date(25, 12, 50))
        assert(plan.nextBoundary(after: date(25, 13), calendar: calendar) == nil)
        assert(plan.blocks(domain: "m.vk.com"))
        assert(!plan.blocks(domain: "notvk.com"))
        assert(!plan.blocks(domain: "vk.com.evil.example"))
        assert(FocusPlan.domains("https://www.VK.com/feed, youtube.com") == ["vk.com", "youtube.com"])
        plan.daily = true
        assert(plan.activeWindow(at: date(26, 12, 10), calendar: calendar) != nil)
        assert(plan.nextBoundary(after: date(26, 13), calendar: calendar) == date(27, 12))
        assert(plan.activeWindow(at: date(24, 12, 10), calendar: calendar) == nil)
        plan.start = date(25, 23, 30); plan.minutes = 120
        assert(plan.activeWindow(at: date(26, 0, 30), calendar: calendar) != nil)
        assert(plan.activeWindow(at: date(26, 1, 30), calendar: calendar) == nil)
        plan.enabled = false
        assert(plan.activeWindow(at: date(26, 0, 30), calendar: calendar) == nil)
        assert(plan.nextBoundary(after: date(26, 0), calendar: calendar) == nil)
        plan.enabled = true; plan.completed = true
        assert(plan.activeWindow(at: date(26, 0, 30), calendar: calendar) == nil)
        print("PASS: scheduled start/end, automatic release boundaries, daily repeat, midnight, disabled/completed goals, exact subdomain matching")
    }
}
