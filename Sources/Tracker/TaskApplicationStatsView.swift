import SwiftUI

struct TaskApplicationStatsView: View {
    @ObservedObject var focus: FocusManager
    let planID: UUID
    private var apps: [TaskApplicationStats] {
        Array((focus.applications[planID] ?? [:]).values).sorted {
            $0.totals.measured == $1.totals.measured ? $0.name < $1.name : $0.totals.measured > $1.totals.measured
        }
    }
    var body: some View { TaskUsageTable(apps: apps) }
}

struct TaskUsageTable: View {
    let apps: [TaskApplicationStats]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("App usage").font(.headline)
                Spacer()
                column("Total")
                column("Distracted")
                column("Idle")
            }.foregroundStyle(.secondary).padding(.vertical, 14)
            if apps.isEmpty {
                Text("App usage appears as you work.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
            }
            ForEach(apps) { app in
                Divider().opacity(0.35)
                HStack(spacing: 10) {
                    ApplicationIcon(bundleID: app.id, name: app.name)
                    Text(app.name).fontWeight(.medium).lineLimit(1)
                    Spacer(minLength: 8)
                    column(time(app.totals.measured))
                    column(time(app.totals.distraction), color: app.totals.distraction > 0 ? .orange : .secondary)
                    column(time(app.totals.idle), color: .secondary)
                }.padding(.vertical, 12)
                if !app.sites.isEmpty {
                    DisclosureGroup("\(app.sites.count) websites") {
                        ForEach(app.sites.keys.sorted(), id: \.self) { domain in
                            let site = app.sites[domain] ?? FocusActivityTotals()
                            HStack(spacing: 10) {
                                WebsiteIcon(domain: domain)
                                Text(domain).lineLimit(1)
                                Spacer(minLength: 8)
                                column(time(site.measured))
                                column(time(site.distraction), color: site.distraction > 0 ? .orange : .secondary)
                                column(time(site.idle), color: .secondary)
                            }.padding(.vertical, 6)
                        }
                    }.font(.caption).foregroundStyle(.secondary).padding(.leading, 42).padding(.bottom, 12)
                }
            }
        }
    }
    private func column(_ text: String, color: Color = .primary) -> some View {
        Text(text).font(.system(size: 12)).monospacedDigit().foregroundStyle(color)
            .frame(width: 82, alignment: .trailing)
    }
    private func time(_ value: Double) -> String {
        let n = max(0, Int(value))
        if n == 0 { return "—" }
        return n >= 3600 ? "\(n / 3600)h \(n % 3600 / 60)m" : n >= 60 ? "\(n / 60)m \(n % 60)s" : "\(n)s"
    }
}
