import SwiftUI
import UIKit

/// Shared look: one dark palette, system fonts (SF Pro / SF Mono). See docs/superpowers/specs/2026-11-24-ui-notes.md.
extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    static let night = Color(hex: 0x15131F)   // background
    static let panel = Color(hex: 0x1F1C2E)   // panels
    static let haze = Color(hex: 0xC8B8FF)    // primary accent (lilac)
    static let amber = Color(hex: 0xFFB547)   // "you're here", playhead, live
    static let tone = Color(hex: 0x6FE3B4)    // chord tone, pass, success
    static let color = Color(hex: 0x8FB4FF)   // color tone
    static let clash = Color(hex: 0xFF7A6B)   // clash, fail
    static let ink = Color(hex: 0xECEBF5)     // text
    static let mute = Color(hex: 0x8D89A6)    // secondary text
}

enum Theme {
    /// Titles and stage numbers: SF Pro Rounded semibold.
    static func title(_ size: CGFloat = 20) -> Font { .system(size: size, weight: .semibold, design: .rounded) }
    /// Body text: SF Pro.
    static func body(_ size: CGFloat = 16) -> Font { .system(size: size, weight: .regular) }
    /// Note names, numbers, chord symbols: SF Mono.
    static func mono(_ size: CGFloat = 14, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Minimum touch target.
    static let minTarget: CGFloat = 44

    static func lightHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// Scales to 0.96 while pressed and gives a light haptic on touch-down.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Theme.lightHaptic() }
            }
    }
}
