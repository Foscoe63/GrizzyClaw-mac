import SwiftUI

/// Full-window panel fill; use behind content after `.preferredColorScheme` so it matches Light/Dark/Auto.
public struct PreferencesPanelChromeBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(PreferencesTheme.panelFill(colorScheme))
            .ignoresSafeArea()
    }
}

/// Visual language aligned with GrizzyClaw (Qt) Preferences: dark chrome, purple accents, label / control columns.
enum PreferencesTheme {
    /// Trailing-aligned labels (matches Qt `QFormLayout` label column).
    static let labelColumnWidth: CGFloat = 220
    static let numericFieldWidth: CGFloat = 88
    static let horizontalInset: CGFloat = 40
    static let groupCornerRadius: CGFloat = 8

    /// Panel / header background (dark charcoal).
    static let panelBackgroundDark = Color(red: 0.11, green: 0.11, blue: 0.12)
    /// Light mode panel (matches system preferences feel).
    static let panelBackgroundLight = Color(red: 0.95, green: 0.95, blue: 0.97)
    /// Group box fill — dark.
    static let groupBackgroundDark = Color(red: 0.17, green: 0.17, blue: 0.19)
    static let groupBorderDark = Color(red: 0.23, green: 0.23, blue: 0.25)
    /// Group box — light.
    static let groupBackgroundLight = Color(red: 0.99, green: 0.99, blue: 1.0)
    static let groupBorderLight = Color(red: 0.82, green: 0.82, blue: 0.86)

    static func panelFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? panelBackgroundDark : panelBackgroundLight
    }

    static func groupFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? groupBackgroundDark : groupBackgroundLight
    }

    static func groupStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? groupBorderDark : groupBorderLight
    }

    /// Checkbox & control accent (purple, GrizzyClaw-style).
    static let accentPurple = Color(red: 0.58, green: 0.42, blue: 0.95)
    /// Selected tab pill (more saturated than accent-only opacity).
    static let tabSelectedFill = Color(red: 0.42, green: 0.28, blue: 0.68)
}
