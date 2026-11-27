import SwiftUI

struct TaskActivityCard: View {
    @ObservedObject var focus: FocusManager
    @ObservedObject var tracker: ActivityTracker
    let now: Date
    let chooseTask: () -> Void
    private let tint = Color(red: 0.65, green: 0.88, blue: 0.49)
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let plan = focus.active.first {
                HStack {
                    Label("IN PROGRESS", systemImage: "scope").font(.caption).foregroundStyle(tint)
                    Spacer()
                    if focus.active.count > 1 { Text("Also active: \(focus.active.count - 1)").font(.caption).foregroundStyle(.secondary) }
                    Button("Finish task") { focus.finishTask(plan.id) }.buttonStyle(.borderedProminent).tint(tint)
                }
                Text(plan.title).font(.system(size: 25, weight: .semibold)).lineLimit(2)
                if !plan.detail.isEmpty { Text(plan.detail).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                if let window = plan.activeWindow(at: now) {
                    HStack {
                        Text("Remaining \(time(max(0, window.end.timeIntervalSince(now))))").monospacedDigit()
                        Spacer()
                        Text("Until \(window.end.formatted(.dateTime.hour().minute().locale(Locale(identifier: "en_GB"))))").foregroundStyle(.secondary)
                    }.font(.callout)
                    ProgressView(value: min(1, max(0, now.timeIntervalSince(window.start) / window.duration))).tint(tint)
                }
                HStack(spacing: 10) {
                    Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(tint)
                    Text(tracker.trackingAllowed ? (tracker.currentPage?.title ?? tracker.currentApp) : "Tracking paused — permissions required").lineLimit(1)
                    Spacer()
                    Text(tracker.taskActivityKind?.rawValue ?? "Not tracked").foregroundStyle(.secondary)
                }.font(.caption)
                totals(focus.activity[plan.id] ?? FocusActivityTotals())
                TaskApplicationStatsView(focus: focus, planID: plan.id)
            } else if let plan = focus.plans.reversed().first(where: {
                $0.completed || (!$0.daily && $0.start.addingTimeInterval(Double($0.minutes * 60)) <= now)
            }), let stats = focus.activity[plan.id] {
                Label("COMPLETED", systemImage: "checkmark.circle").font(.caption).foregroundStyle(tint)
                HStack {
                    Text(plan.title).font(.title3).fontWeight(.semibold)
                    Spacer()
                }
                totals(stats)
                TaskApplicationStatsView(focus: focus, planID: plan.id)
            } else {
                HStack(spacing: 16) {
                    Image(systemName: "scope").font(.system(size: 28)).foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Make time for a task").font(.headline)
                        Text("Start a task to see where your time goes.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose task", action: chooseTask).buttonStyle(.borderedProminent).tint(tint)
                }
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.105, green: 0.12, blue: 0.135), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.045)))
    }
    private func totals(_ stats: FocusActivityTotals) -> some View {
        HStack(spacing: 18) {
            stat("Focused", stats.work, tint)
            stat("Distracted", stats.distraction, .orange)
            stat("Other", stats.other, .secondary)
            stat("Idle", stats.idle, .secondary)
        }
    }
    private func stat(_ label: String, _ seconds: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(time(seconds)).font(.system(size: 18, weight: .medium)).monospacedDigit().foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary).help("Based on your selected work apps and blocked distractions.")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func time(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return value >= 3600 ? "\(value / 3600)h \((value / 60) % 60)m" : "\(value / 60)m \(value % 60)s"
    }
}
