import SwiftUI
import AppKit

struct FocusWorkAppsPicker: View {
    let apps: [FocusAppItem]
    @Binding var selected: Set<String>
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    private let tint = Color(red: 0.65, green: 0.88, blue: 0.49)
    private var visibleApps: [FocusAppItem] {
        let extras = selected.subtracting(Set(apps.map(\.id))).sorted().map { id in
            FocusAppItem(id: id, name: NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id, running: false)
        }
        return (apps + extras).filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Work apps").font(.title2).fontWeight(.semibold)
                    Text("Choose the apps you need for this task.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent).tint(tint)
            }
            TextField("Search", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 10)], spacing: 10) {
                    ForEach(visibleApps) { app in
                        let chosen = selected.contains(app.id)
                        Button {
                            if chosen { selected.remove(app.id) } else if selected.count < 20 { selected.insert(app.id) }
                        } label: {
                            VStack(spacing: 9) {
                                ZStack(alignment: .topTrailing) {
                                    ApplicationIcon(bundleID: app.id, name: app.name)
                                    if chosen { Image(systemName: "checkmark.circle.fill").foregroundStyle(tint).offset(x: 12, y: -4) }
                                }
                                Text(app.name).font(.caption).lineLimit(1)
                            }.padding(15).frame(maxWidth: .infinity)
                                .background(chosen ? tint.opacity(0.1) : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(chosen ? tint.opacity(0.7) : .clear))
                        }.buttonStyle(ClickTargetButtonStyle()).disabled(!chosen && selected.count >= 20)
                            .help(app.name).accessibilityValue(chosen ? "Selected" : "Not selected")
                    }
                }.padding(3)
            }
            HStack {
                Text("Selected: \(selected.count) of 20").font(.caption).foregroundStyle(.secondary)
                Button("Reset") { selected.removeAll() }.buttonStyle(ClickTargetButtonStyle()).font(.caption)
                Spacer()
            }
            Text("Work apps count toward focus time. Website rules still apply.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(26).frame(width: 730, height: 560).preferredColorScheme(.dark)
    }
}
