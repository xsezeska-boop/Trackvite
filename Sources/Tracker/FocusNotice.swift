import SwiftUI

struct FocusNotice: View {
    let title: String
    let text: String
    let task: String
    let finish: () -> Void
    var dismiss: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "scope")
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(.green)
                    .frame(width: 34, height: 34)
                    .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(task).font(.system(size: 12)).lineLimit(1)
                    Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Button(action: dismiss) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }.buttonStyle(ClickTargetButtonStyle()).help("Dismiss notification")
                    .accessibilityLabel("Dismiss notification")
            }
            Button(action: finish) {
                Text("Finish task").font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }.buttonStyle(ClickTargetButtonStyle())
        }.padding(16).frame(width: 360, height: 168)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}
