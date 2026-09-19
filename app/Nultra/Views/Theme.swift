import SwiftUI

 enum Theme {
    static let background = Color(red: 0.025, green: 0.050, blue: 0.090)
    static let surface = Color(red: 0.060, green: 0.095, blue: 0.135)
    static let mint = Color(red: 0.64, green: 0.96, blue: 0.81)
    static let muted = Color(red: 0.59, green: 0.67, blue: 0.72)
 }

struct Panel: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(20)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.07), lineWidth: 1))
    }
}

extension View {
    func panel() -> some View { modifier(Panel()) }
    @ViewBuilder func asciiEntry() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
        #else
        self
        #endif
    }
}

struct PrimaryButton: ButtonStyle {
    var subdued = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
            .foregroundColor(subdued ? Theme.mint : Theme.background)
            .background(subdued ? Theme.mint.opacity(0.10) : Theme.mint,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
