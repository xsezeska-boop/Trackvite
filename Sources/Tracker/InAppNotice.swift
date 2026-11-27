import SwiftUI

struct InAppNotice: Identifiable {
    enum Action { case settings, screenTime, startTracking }
    let id = UUID()
    let title: String
    var symbol = "checkmark.circle.fill"
    var detail = ""
    var action: Action? = nil
}

struct InAppNoticeView: View {
    let notice: InAppNotice
    let dismiss: () -> Void
    var performAction: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Image(systemName: notice.symbol).font(.system(size: 21))
                    .foregroundStyle(Color(red: 0.65, green: 0.88, blue: 0.49))
                Text(notice.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
                Spacer(minLength: 8)
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }.buttonStyle(ClickTargetButtonStyle()).help("Dismiss").accessibilityLabel("Dismiss notification")
            }
            if !notice.detail.isEmpty {
                Text(notice.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 33)
            }
            if let action = notice.action {
                HStack {
                    Spacer()
                    Button(action == .settings ? "Open Settings" : action == .startTracking ? "Enable Screen Time" : "Open Screen Time", action: performAction)
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }.padding(14).frame(width: 340)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.3), radius: 18, y: 6)
            .accessibilityElement(children: .contain)
    }
}
