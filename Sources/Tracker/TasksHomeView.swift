import SwiftUI

private struct TaskEditorRequest: Identifiable {
    let id = UUID()
    let plan: FocusPlan?
}

struct TasksHomeView: View {
    @ObservedObject var focus: FocusManager
    @ObservedObject var tracker: ActivityTracker
    let now: Date
    @State private var editor: TaskEditorRequest?
    @State private var report: FocusPlan?
    private let tint = Color(red: 0.65, green: 0.88, blue: 0.49)
    private var waiting: [FocusPlan] {
        focus.plans.filter { !isActive($0) && !$0.completed && ($0.daily || $0.start.addingTimeInterval(Double($0.minutes * 60)) > now) }
    }
    private var hasResult: Bool {
        focus.plans.contains { ($0.completed || (!$0.daily && $0.start.addingTimeInterval(Double($0.minutes * 60)) <= now)) && focus.activity[$0.id] != nil }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text(!focus.active.isEmpty ? "Your task, live." : "Make time for what matters.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button { editor = TaskEditorRequest(plan: nil) } label: {
                    Label("New task", systemImage: "plus").padding(.horizontal, 14).padding(.vertical, 9)
                        .foregroundStyle(.black).background(tint, in: Capsule())
                }.buttonStyle(ClickTargetButtonStyle())
            }
            if !focus.active.isEmpty || hasResult {
                TaskActivityCard(focus: focus, tracker: tracker, now: now) { editor = TaskEditorRequest(plan: nil) }
            }
            if focus.plans.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "checklist").font(.system(size: 38)).foregroundStyle(tint.opacity(0.8))
                    Text("What are you working on?").font(.title3).fontWeight(.medium)
                    Text("Create a task to see your time and app usage here.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 65)
            }
            if focus.active.count > 1 {
                Text("Also in progress").font(.headline)
                ForEach(Array(focus.active.dropFirst())) { plan in row(plan) }
            }
            if !waiting.isEmpty {
                Text("Upcoming").font(.headline)
                ForEach(waiting) { plan in row(plan) }
            }
            let done = focus.plans.filter { plan in
                !isActive(plan) && (plan.completed || (!plan.daily && plan.start.addingTimeInterval(Double(plan.minutes * 60)) <= now))
            }
            if !done.isEmpty {
                DisclosureGroup("Completed · \(done.count)") {
                    VStack(spacing: 8) { ForEach(done.reversed()) { plan in row(plan) } }.padding(.top, 12)
                }.font(.callout).foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editor) { request in FocusView(focus: focus, initialPlan: request.plan) }
        .sheet(item: $report) { plan in
            TaskReportView(focus: focus, plan: plan)
        }
    }
    private func isActive(_ plan: FocusPlan) -> Bool { focus.active.contains { $0.id == plan.id } }
    private func row(_ plan: FocusPlan) -> some View {
        HStack(spacing: 12) {
            Image(systemName: plan.completed ? "checkmark.circle.fill" : "circle.dotted")
                .font(.title3).foregroundStyle(plan.completed ? tint : .secondary)
            Button {
                if focus.activity[plan.id] != nil { report = plan } else { editor = TaskEditorRequest(plan: plan) }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(plan.title).fontWeight(.medium).lineLimit(1)
                    Text("\(plan.start.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "en_GB")))) · \(plan.minutes)m\(plan.daily ? " · daily" : "")\(!plan.enabled ? " · off" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(ClickTargetButtonStyle())
            if isActive(plan) {
                Button("Finish") { focus.finishTask(plan.id) }
            } else if !plan.completed {
                Button("Start") { focus.startNow(plan.id) }
            }
            Menu {
                if focus.activity[plan.id] != nil { Button("View activity") { report = plan } }
                Button("Edit") { editor = TaskEditorRequest(plan: plan) }
                Button(plan.enabled ? "Disable schedule" : "Enable schedule") { focus.toggle(plan.id) }
                if plan.completed { Button("Start again") { focus.startNow(plan.id) } }
                Button("Delete", role: .destructive) { focus.remove(plan.id) }
            } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 32)
        }.padding(12).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct TaskReportView: View {
    @ObservedObject var focus: FocusManager
    let plan: FocusPlan
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(plan.title).font(.title2).fontWeight(.semibold).lineLimit(2)
                Spacer()
                Button("Done") { dismiss() }
            }
            let stats = focus.activity[plan.id] ?? FocusActivityTotals()
            HStack {
                value("Focused", stats.work)
                value("Distracted", stats.distraction)
                value("Other", stats.other)
                value("Idle", stats.idle)
            }
            ScrollView { TaskApplicationStatsView(focus: focus, planID: plan.id) }
        }.padding(26).frame(width: 700, height: 500).preferredColorScheme(.dark)
    }
    private func value(_ name: String, _ seconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(Int(seconds) / 60)m \(Int(seconds) % 60)s").font(.headline).monospacedDigit()
            Text(name).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
