import SwiftUI

enum CrewPickTheme {
    static let accent = Color(red: 0.88, green: 0.35, blue: 0.21)
    static let accentSoft = Color(red: 0.98, green: 0.91, blue: 0.88)
    static let success = Color(red: 0.21, green: 0.52, blue: 0.36)
    static let warning = Color(red: 0.77, green: 0.52, blue: 0.11)
    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 14
    static let screenPadding: CGFloat = 16
}

struct WarmCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: CrewPickTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CrewPickTheme.cardRadius, style: .continuous)
                    .stroke(.separator.opacity(0.45), lineWidth: 1)
            }
    }
}

extension View {
    func warmCard() -> some View { modifier(WarmCardModifier()) }
}

