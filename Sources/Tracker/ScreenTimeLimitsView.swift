import SwiftUI

struct ScreenTimeLimitsView: View {
    @ObservedObject var limits: ScreenTimeLimits
    let tracking: Bool
    @State private var adding = false
    @State private var editing: ScreenTimeRule?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily limits").font(.headline)
                    Text(tracking ? "Active time only · resets at midnight" : "Paused until you start Screen Time").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add limit", systemImage: "plus") { adding = true }.disabled(limits.rules.count >= 64)
            }
            if limits.rules.isEmpty { Text("Set a daily allowance for an app or website.").font(.callout).foregroundStyle(.secondary) }
            ForEach(limits.rules) { rule in
                HStack(spacing: 12) {
                    if rule.isSite { WebsiteIcon(domain: rule.id) }
                    else { ApplicationIcon(bundleID: rule.id, name: rule.name) }
                    VStack(alignment: .leading, spacing: 4) {
                        Button(rule.name) { editing = rule }.buttonStyle(ClickTargetButtonStyle()).fontWeight(.medium).help("Edit limit")
                        Text(!rule.enabled ? "Off" : "\(minutes(limits.budget.remaining(rule))) left of \(rule.minutes) min")
                            .font(.caption).foregroundStyle(rule.enabled && limits.budget.remaining(rule) <= 0 ? .orange : .secondary)
                    }
                    Spacer()
                    Toggle("Enable limit for \(rule.name)", isOn: Binding(get: { rule.enabled }, set: { _ in limits.toggle(rule) })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    Button { limits.remove(rule) } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }
                        .buttonStyle(ClickTargetButtonStyle()).help("Remove limit")
                }.padding(.vertical, 4)
            }
            if !limits.message.isEmpty { Text(limits.message).font(.caption).foregroundStyle(.orange) }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.105, green: 0.12, blue: 0.135), in: RoundedRectangle(cornerRadius: 16))
            .sheet(isPresented: $adding) { ScreenTimeLimitEditor(limits: limits) }
            .sheet(item: $editing) { rule in ScreenTimeLimitEditor(limits: limits, initialRule: rule) }
    }
    private func minutes(_ seconds: Double) -> String {
        if seconds <= 0 { return "0 min" }
        let value = Int(ceil(seconds / 60))
        return value >= 60 ? "\(value / 60)h \(value % 60)m" : "\(value) min"
    }
}

private struct ScreenTimeLimitEditor: View {
    @ObservedObject var limits: ScreenTimeLimits
    var initialRule: ScreenTimeRule? = nil
    @State private var initialized = false
    @ObservedObject private var catalog = FocusAppCatalog.shared
    @Environment(\.dismiss) private var dismiss
    @State private var apps: Set<String> = []
    @State private var sites: Set<String> = []
    @State private var hours = "0"
    @State private var minutes = "0"
    @State private var choosing = false
    private var duration: Int? {
        guard let h = Int(hours), let m = Int(minutes), (0...24).contains(h), (0...59).contains(m), (1...1440).contains(h * 60 + m) else { return nil }
        return h * 60 + m
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Text("Daily limit").font(.title2).fontWeight(.semibold); Spacer(); Button("Cancel") { dismiss() } }
            Button { choosing = true } label: {
                HStack {
                    Text(apps.isEmpty && sites.isEmpty ? "Choose apps and websites" : "\(apps.count) apps · \(sites.count) websites")
                    Spacer(); Image(systemName: "chevron.right")
                }.padding(14).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(ClickTargetButtonStyle())
            HStack {
                Text("Time per day"); Spacer()
                TextField("0", text: $hours).frame(width: 48).accessibilityLabel("Hours")
                Text("h")
                TextField("0", text: $minutes).frame(width: 48).accessibilityLabel("Minutes")
                Text("min")
            }.textFieldStyle(.roundedBorder)
            Text("Each selection gets this allowance. Website limits close the active tab in Safari and supported Chrome-based browsers after detection. Apps are covered by a limit screen.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button(initialRule == nil ? "Add limit" : "Save") {
                guard let duration else { return }
                limits.add(apps: catalog.apps.filter { apps.contains($0.id) }, sites: sites, minutes: duration)
                dismiss()
            }.buttonStyle(.borderedProminent).disabled(duration == nil || (apps.isEmpty && sites.isEmpty)) }
        }.padding(26).frame(width: 530).preferredColorScheme(.dark)
            .task { await catalog.load() }
            .onAppear {
                guard !initialized else { return }; initialized = true
                if let rule = initialRule {
                    if rule.isSite { sites = [rule.id] } else { apps = [rule.id] }
                    hours = String(rule.minutes / 60); minutes = String(rule.minutes % 60)
                }
            }
            .sheet(isPresented: $choosing) {
                DistractionPicker(apps: catalog.apps, loading: catalog.loading, selectedApps: $apps, selectedSites: $sites,
                                  heading: "Choose apps and websites", subtitle: "Each selection gets its own daily allowance.")
            }
    }
}
