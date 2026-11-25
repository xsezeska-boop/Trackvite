import SwiftUI

struct TaskJourneyView: View {
    let journey: TaskJourney
    @State private var expanded = false
    var body: some View {
        if !journey.entries.isEmpty {
            Divider().opacity(0.4)
            HStack {
                Text("Task activity").font(.system(size: 13, weight: .semibold))
                Spacer()
                if journey.entries.count > 3 {
                    Button(expanded ? "Less" : "Show all") { expanded.toggle() }
                        .font(.caption).buttonStyle(ClickTargetButtonStyle())
                }
            }
            ForEach(Array(journey.entries.suffix(expanded ? 60 : 3).reversed())) { entry in
                HStack(alignment: .top, spacing: 12) {
                    Text(entry.date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "en_GB"))))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 43)
                    Circle().fill(color(entry.kind)).frame(width: 6, height: 6).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.label).font(.system(size: 12)).lineLimit(1)
                        if !entry.event { Text(entry.kind.rawValue).font(.system(size: 10)).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 4)
                    if !entry.event {
                        Text("\(Int(entry.seconds) / 60)m \(Int(entry.seconds) % 60)s")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
    }
    private func color(_ kind: FocusActivityKind) -> Color {
        switch kind {
        case .work: .green
        case .distraction: .orange
        case .idle: .gray
        case .other: .secondary
        }
    }
}
