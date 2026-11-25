import Foundation

struct FocusPlan: Identifiable {
    var id = UUID()
    var title: String
    var detail: String
    var start: Date
    var minutes: Int
    var daily: Bool
    var blockedApps: [String]
    var blockedSites: [String]
    var workApps: [String] = []
    var materials: [URL] = []
    var enabled = true
    var completed = false

    mutating func normalizeWorkspace() {
        workApps = Array(Set(workApps)).sorted().prefix(20).map { $0 }
        blockedApps = Array(Set(blockedApps).subtracting(workApps)).sorted()
        var seen = Set<URL>()
        materials = materials.filter { $0.isFileURL && seen.insert($0).inserted }.prefix(10).map { $0 }

    }

    func activeWindow(at now: Date, calendar: Calendar = .current) -> DateInterval? {
        windows(near: now, calendar: calendar).first { $0.start <= now && now < $0.end }
    }
    func nextBoundary(after now: Date, calendar: Calendar = .current) -> Date? {
        windows(near: now, calendar: calendar).flatMap { [$0.start, $0.end] }.filter { $0 > now }.min()
    }
    private func windows(near now: Date, calendar: Calendar) -> [DateInterval] {
        guard enabled, !completed, minutes > 0 else { return [] }
        if !daily { return [DateInterval(start: start, duration: Double(minutes * 60))] }
        let time = calendar.dateComponents([.hour, .minute, .second], from: start)
        return (-1...2).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let begin = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                    second: time.second ?? 0, of: day), begin >= start else { return nil }
            return DateInterval(start: begin, duration: Double(minutes * 60))
        }
    }
    static func domains(_ text: String) -> [String] {
        Array(Set(text.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " }).compactMap {
            let input = String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            return WebsiteLedger.domain(input.contains("://") ? input : "https://" + input)
        })).sorted()
    }
    func blocks(domain: String) -> Bool {
        blockedSites.contains { domain == $0 || domain.hasSuffix("." + $0) }
    }
}
