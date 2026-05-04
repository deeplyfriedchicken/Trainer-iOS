import SwiftUI

// MARK: - Colors

extension Color {
    static let appBg       = Color(hex: "070712")
    static let cardBg      = Color.white.opacity(0.05)
    static let neonPink    = Color(hex: "FD6DBB")
    static let neonCyan    = Color(hex: "34FDFE")
    static let neonGreen   = Color(hex: "4ade80")
    static let neonRed     = Color(hex: "f87171")
    static let neonOrange  = Color(hex: "fb923c")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Avatar palette (5 slots, cycles)

struct AvatarColor {
    let bg: Color
    let border: Color
    let text: Color
}

let avatarPalette: [AvatarColor] = [
    AvatarColor(bg: Color(hex: "FD6DBB").opacity(0.15), border: Color(hex: "FD6DBB").opacity(0.30), text: .neonPink),
    AvatarColor(bg: Color(hex: "34FDFE").opacity(0.12), border: Color(hex: "34FDFE").opacity(0.25), text: .neonCyan),
    AvatarColor(bg: Color(hex: "4ade80").opacity(0.12), border: Color(hex: "4ade80").opacity(0.25), text: .neonGreen),
    AvatarColor(bg: Color(hex: "fb923c").opacity(0.12), border: Color(hex: "fb923c").opacity(0.25), text: .neonOrange),
    AvatarColor(bg: Color(hex: "a78bfa").opacity(0.12), border: Color(hex: "a78bfa").opacity(0.25), text: Color(hex: "a78bfa")),
]

func paletteColor(_ index: Int) -> AvatarColor {
    avatarPalette[index % avatarPalette.count]
}

// MARK: - Glass modifier

struct GlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.white.opacity(0.12), lineWidth: 1))
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassBackground(cornerRadius: cornerRadius))
    }
}

// MARK: - Fonts (SF Pro stand-ins for design fonts)

extension Font {
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}
