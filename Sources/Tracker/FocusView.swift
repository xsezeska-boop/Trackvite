import SwiftUI
import AppKit

private let focusAccent = Color(red: 0.65, green: 0.88, blue: 0.49)
private let focusSurface = Color(red: 0.105, green: 0.12, blue: 0.135)

struct FocusView: View {
    @ObservedObject var focus: FocusManager
    var initialPlan: FocusPlan? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var catalog = FocusAppCatalog.shared
    @State private var initialized = false
    @State private var editingID: UUID?
    @State private var title = ""
    @State private var detail = ""
    @State private var workApps: Set<String> = []
    @State private var materials: [URL] = []
    @State private var start = Date().addingTimeInterval(3600)
    @State private var hoursText = "0"
    @State private var minutesText = "0"
    @State private var daily = false
    @State private var later = false
    @State private var selectedSites: Set<String> = ["vk.com", "instagram.com", "tiktok.com", "x.com", "reddit.com", "facebook.com", "youtube.com"]
    @State private var selectedApps: Set<String> = []
    @State private var error = ""
    @State private var choosing = false
    @State private var choosingTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(initialPlan == nil ? "New task" : "Edit task").font(.title2).fontWeight(.semibold)
                Spacer()
                Button("Cancel") { dismiss() }
            }.padding(.horizontal, 24).padding(.top, 20)
            ScrollView { form.padding(.horizontal, 20).padding(.bottom, 20) }
        }.frame(width: 730, height: 680).preferredColorScheme(.dark)
    }
    private var form: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Task name").fontWeight(.semibold)
                    TextField("e.g. Build the home screen", text: $title).textFieldStyle(.roundedBorder)
                }
                workspaceEditor
                HStack(spacing: 8) {
                    Text("Duration").foregroundStyle(.secondary)
                    TextField("0", text: $hoursText).frame(width: 48)
                        .accessibilityLabel("Hours")
                    Text("h").foregroundStyle(.secondary)
                    TextField("0", text: $minutesText).frame(width: 48)
                        .accessibilityLabel("Minutes")
                    Text("min").foregroundStyle(.secondary)
                    Spacer()

                }.textFieldStyle(.roundedBorder)
                HStack {
                    Text("Start").foregroundStyle(.secondary)
                    Spacer()
                    Picker("Start", selection: $later) {
                        Text("Now").tag(false)
                        Text("Schedule").tag(true)
                    }.pickerStyle(.segmented).frame(width: 205).labelsHidden()
                }
                if !later { Toggle("Repeat daily", isOn: $daily).toggleStyle(.checkbox).font(.callout).foregroundStyle(.secondary) }
                if later {
                    HStack {
                        DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                        Spacer()
                        Toggle("Repeat daily", isOn: $daily).toggleStyle(.checkbox)
                    }.font(.callout)
                }
                Divider().opacity(0.4)
                Button { choosing = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised.fill").foregroundStyle(focusAccent).font(.title3)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Block distractions").fontWeight(.medium).foregroundStyle(.primary)
                            Text("Apps: \(selectedApps.count) · websites: \(selectedSites.count)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: -5) {
                            ForEach(Array(selectedApps.sorted().prefix(4)), id: \.self) { id in
                                ApplicationIcon(bundleID: id, name: appName(id)).padding(3)
                                    .background(focusSurface, in: RoundedRectangle(cornerRadius: 9))
                            }
                        }
                        Text("Choose").foregroundStyle(focusAccent)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
                    }.padding(.vertical, 3).contentShape(Rectangle())
                }.buttonStyle(ClickTargetButtonStyle())
                if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
                HStack {
                    Label("Task activity is tracked automatically", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(action: save) {
                        Label(editingID != nil ? "Save" : later ? "Schedule" : "Start task",
                              systemImage: later ? "calendar.badge.clock" : "play.fill")
                            .fontWeight(.semibold).padding(.horizontal, 22).padding(.vertical, 12)
                            .foregroundStyle(.black).background(focusAccent, in: Capsule())
                    }.buttonStyle(ClickTargetButtonStyle())
                }
            }.padding(26).background(focusSurface, in: RoundedRectangle(cornerRadius: 20))
            DisclosureGroup("About blocking") {
                Text("Apps are covered by a focus screen. Supported browsers close the active blocked tab after detection; a page may load first. Browser access is required. Keep Trackvite open.")
                    .font(.caption).lineSpacing(4).padding(.top, 8)
                if !focus.active.isEmpty { Text(focus.browserStatus).font(.caption).padding(.top, 5) }
            }.font(.caption).foregroundStyle(.secondary)
        }
        .task { await catalog.load() }
        .onAppear { if !initialized { initialized = true; if let initialPlan { edit(initialPlan) } } }
        .sheet(isPresented: $choosing) {
            DistractionPicker(apps: catalog.apps, loading: catalog.loading,
                selectedApps: $selectedApps, selectedSites: $selectedSites)
        }
        .sheet(isPresented: $choosingTarget) { FocusWorkAppsPicker(apps: catalog.apps, selected: $workApps) }
        .onChange(of: workApps) { _, values in selectedApps.subtract(values) }
    }
    private var workspaceEditor: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("Work apps", systemImage: "square.stack.3d.up").fontWeight(.medium)
                Spacer()
                Button("Choose apps") { choosingTarget = true }
            }
            if workApps.isEmpty {
                Text("Choose all the apps you need.").font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading) {
                    ForEach(workApps.sorted(), id: \.self) { id in
                        HStack(spacing: 8) {
                            ApplicationIcon(bundleID: id, name: appName(id))
                            Text(appName(id)).font(.caption).lineLimit(1)
                            Spacer(minLength: 0)
                            Button { workApps.remove(id) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(ClickTargetButtonStyle())
                        }.padding(8).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            Button("Attach files or folders", systemImage: "paperclip", action: chooseMaterials).font(.caption)
            ForEach(materials, id: \.self) { url in
                HStack {
                    Image(systemName: "doc").foregroundStyle(.secondary)
                    Text(url.lastPathComponent).font(.caption).lineLimit(1)
                    Spacer()
                    Button { materials.removeAll { $0 == url } } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }.buttonStyle(ClickTargetButtonStyle())
                }
            }

        }.padding(16).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
    }
    private var durationMinutes: Int? {
        guard let hours = Int(hoursText.trimmingCharacters(in: .whitespaces)),
              let minutes = Int(minutesText.trimmingCharacters(in: .whitespaces)),
              (0...12).contains(hours), (0...59).contains(minutes),
              (1...720).contains(hours * 60 + minutes) else { return nil }
        return hours * 60 + minutes
    }
    private func setDuration(_ value: Int) {
        hoursText = String(value / 60)
        minutesText = String(value % 60)
    }
    private func appName(_ id: String) -> String { catalog.apps.first { $0.id == id }?.name ?? id }
    private func save() {
        guard let minutes = durationMinutes else {
            error = "Enter 1 minute to 12 hours. Minutes must be between 0 and 59."
            return
        }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Enter a task name."; return }
        if !workApps.isDisjoint(with: selectedApps) {
            selectedApps.subtract(workApps)
        }
        let begin = later ? start : Date()
        guard !later || begin > Date() || (editingID != nil && begin.addingTimeInterval(Double(minutes * 60)) > Date()) else {
            error = "Choose a future time or Now."; return
        }
        guard editingID != nil || focus.plans.count < 100 else { error = "You can keep up to 100 tasks."; return }
        var plan = FocusPlan(title: String(title.prefix(256)), detail: String(detail.prefix(1000)),
            start: begin, minutes: minutes, daily: daily, blockedApps: selectedApps.sorted(), blockedSites: selectedSites.sorted(), workApps: workApps.sorted(), materials: materials)
        if let editingID {
            plan.id = editingID
            if let old = focus.plans.first(where: { $0.id == editingID }) { plan.enabled = old.enabled; plan.completed = old.completed }
            focus.update(plan)
        } else { focus.add(plan) }
        dismiss()
    }
    private func edit(_ plan: FocusPlan) {
        editingID = plan.id; title = plan.title; detail = plan.detail; workApps = Set(plan.workApps); materials = plan.materials
        start = plan.start; setDuration(plan.minutes); daily = plan.daily; later = true
        selectedSites = Set(plan.blockedSites); selectedApps = Set(plan.blockedApps)
        error = ""
    }
    private func chooseMaterials() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true; picker.canChooseFiles = true; picker.allowsMultipleSelection = true
        picker.prompt = "Attach"
        if picker.runModal() == .OK {
            for url in picker.urls where !materials.contains(url) && materials.count < 10 { materials.append(url) }
        }
    }
}
