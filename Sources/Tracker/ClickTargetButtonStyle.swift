import SwiftUI

/// The complete label (text, icon and padding) is one target, including transparent gaps.
struct ClickTargetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .frame(minWidth: 28, minHeight: 28)
            .background(Color.white.opacity(0.001))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
