import SwiftUI

private struct DistractionGroup: Identifiable {
    let id: String
    let symbol: String
    let sites: Set<String>
    let appIDs: Set<String>
    static let all: [DistractionGroup] = [
        .init(id: "Social", symbol: "bubble.left.and.bubble.right", sites: ["vk.com", "instagram.com", "tiktok.com", "x.com", "reddit.com", "facebook.com"], appIDs: ["com.atebits.Tweetie2"]),
        .init(id: "Video", symbol: "play.rectangle", sites: ["youtube.com", "twitch.tv", "netflix.com", "rutube.ru"], appIDs: ["com.netflix.Netflix"]),
        .init(id: "Messaging", symbol: "message", sites: ["web.telegram.org", "discord.com", "web.whatsapp.com"], appIDs: ["ru.keepcoder.Telegram", "org.telegram.desktop", "com.hnc.Discord", "net.whatsapp.WhatsApp"]),
        .init(id: "Games", symbol: "gamecontroller", sites: ["store.steampowered.com", "roblox.com"], appIDs: ["com.valvesoftware.steam", "com.roblox.RobloxPlayer", "com.epicgames.EpicGamesLauncher"])
    ]
}

struct DistractionPicker: View {
    let apps: [FocusAppItem]
    let loading: Bool
    @Binding var selectedApps: Set<String>
    @Binding var selectedSites: Set<String>
    var heading = "Block distractions"
    var subtitle = "Choose what to block during your task."
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var query = ""
    @State private var customSite = ""
    @State private var error = ""
    private let tint = Color(red: 0.65, green: 0.88, blue: 0.49)
    private var visibleApps: [FocusAppItem] {
        let extras = selectedApps.subtracting(Set(apps.map(\.id))).sorted().map { FocusAppItem(id: $0, name: $0, running: false) }
        return (apps + extras).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }
    private var sites: [String] {
        Array(Set(DistractionGroup.all.flatMap { Array($0.sites) }).union(selectedSites)).sorted()
            .filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(heading).font(.system(size: 25, weight: .semibold))
                    Text(subtitle).foregroundStyle(.secondary).font(.callout)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }.buttonStyle(ClickTargetButtonStyle()).help("Done")
            }
            HStack(spacing: 8) {
                ForEach(DistractionGroup.all) { group in
                    let chosen = group.sites.isSubset(of: selectedSites) && group.appIDs.intersection(Set(apps.map(\.id))).isSubset(of: selectedApps)
                    Button { toggle(group) } label: {
                        Label(group.id, systemImage: chosen ? "checkmark.circle.fill" : group.symbol)
                            .font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 10)
                            .foregroundStyle(chosen ? tint : .secondary)
                            .background(chosen ? tint.opacity(0.12) : Color.white.opacity(0.04), in: Capsule())
                    }.buttonStyle(ClickTargetButtonStyle())
                }
            }
            HStack {
                Picker("List", selection: $tab) {
                    Text("Apps").tag(0)
                    Text("Websites").tag(1)
                }.pickerStyle(.segmented).frame(width: 245).labelsHidden()
                Spacer()
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $query).textFieldStyle(.plain)
                }.padding(9).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9)).frame(width: 235)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 10)], spacing: 10) {
                    if tab == 0 {
                        ForEach(visibleApps) { app in
                            tile(name: app.name, selected: selectedApps.contains(app.id), subtitle: app.running ? "Running" : nil,
                                 action: { toggle(app.id, in: &selectedApps) }) {
                                ApplicationIcon(bundleID: app.id, name: app.name)
                            }
                            .disabled(BrowserMonitor.browsers.contains(app.id))
                            .opacity(BrowserMonitor.browsers.contains(app.id) ? 0.45 : 1)
                            .help(BrowserMonitor.browsers.contains(app.id) ? "Choose individual websites instead." : app.name)
                        }
                    } else {
                        ForEach(sites, id: \.self) { site in
                            tile(name: site, selected: selectedSites.contains(site), subtitle: nil,
                                 action: { toggle(site, in: &selectedSites) }) { WebsiteIcon(domain: site) }
                        }
                    }
                }.padding(2)
                if tab == 0 && loading { ProgressView("Loading apps…").padding() }
                if (tab == 0 && visibleApps.isEmpty && !loading) || (tab == 1 && sites.isEmpty) {
                    Text("No results.").foregroundStyle(.secondary).padding(30)
                }
            }.frame(maxHeight: .infinity)
            if tab == 1 {
                HStack {
                    TextField("Add website: example.com", text: $customSite).textFieldStyle(.roundedBorder).onSubmit(addSite)
                    Button("Add", action: addSite)
                }
                if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            HStack {
                Text("Selected: \(selectedApps.count) apps, \(selectedSites.count) websites").font(.caption).foregroundStyle(.secondary)
                Button("Reset") { selectedApps.removeAll(); selectedSites.removeAll() }.buttonStyle(ClickTargetButtonStyle()).font(.caption)
                Spacer()
                Button { dismiss() } label: {
                    Text("Done").fontWeight(.semibold).padding(.horizontal, 28).padding(.vertical, 10)
                        .foregroundStyle(.black).background(tint, in: Capsule())
                }.buttonStyle(ClickTargetButtonStyle())
            }
        }.padding(28).frame(width: 760, height: 660)
            .background(Color(red: 0.075, green: 0.085, blue: 0.095)).preferredColorScheme(.dark)
    }
    private func tile<Icon: View>(name: String, selected: Bool, subtitle: String?, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    icon().frame(width: 40, height: 36).padding(.top, 3)
                    if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(tint).offset(x: 12, y: -2) }
                }
                Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                Text(subtitle ?? " ").font(.system(size: 9)).foregroundStyle(.secondary)
            }.padding(12).frame(maxWidth: .infinity)
                .foregroundStyle(selected ? .primary : .secondary)
                .background(selected ? tint.opacity(0.08) : .white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? tint.opacity(0.7) : .white.opacity(0.04)))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(ClickTargetButtonStyle()).help(name).accessibilityLabel(name).accessibilityValue(selected ? "Selected" : "Not selected")
    }
    private func toggle(_ value: String, in values: inout Set<String>) {
        if values.contains(value) { values.remove(value) } else { values.insert(value) }
    }
    private func toggle(_ group: DistractionGroup) {
        let installed = group.appIDs.intersection(Set(apps.map(\.id)))
        if group.sites.isSubset(of: selectedSites) && installed.isSubset(of: selectedApps) {
            selectedSites.subtract(group.sites); selectedApps.subtract(installed)
        } else { selectedSites.formUnion(group.sites); selectedApps.formUnion(installed) }
    }
    private func addSite() {
        let value = customSite.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = FocusPlan.domains(value)
        guard parsed.count == 1, !value.contains(","), !value.contains(" ") else { error = "Enter one website address."; return }
        selectedSites.insert(parsed[0]); customSite = ""; error = ""
    }
}
