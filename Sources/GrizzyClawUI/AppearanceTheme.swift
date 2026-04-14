import AppKit
import GrizzyClawCore
import SwiftUI

/// Wraps secondary `Window` content so `preferredColorScheme` updates when `config.yaml` changes.
/// `GrizzyClawRootScene` only holds `@StateObject session`; child `Window` builders do not always
/// re-subscribe to `session.configStore` unless this wrapper holds `@ObservedObject configStore`.
public struct AppThemedWindowRoot<Content: View>: View {
    @ObservedObject public var configStore: ConfigStore
    @ViewBuilder public var content: () -> Content

    public init(configStore: ConfigStore, @ViewBuilder content: @escaping () -> Content) {
        self.configStore = configStore
        self.content = content
    }

    public var body: some View {
        content()
            .preferredColorScheme(AppearanceTheme.resolvedColorScheme(for: configStore.snapshot.theme))
    }
}

/// Maps `config.yaml` `theme` / `font_*` / `compact_mode` to SwiftUI `ColorScheme`, chrome colors, and `NSFont`.
public enum AppearanceTheme {
    // MARK: - Color scheme (main + auxiliary windows)

    /// Matches Python `apply_appearance_settings` theme IDs. `nil` = follow system (**Auto**).
    public static func resolvedColorScheme(for theme: String) -> ColorScheme? {
        switch normalize(theme) {
        case "light", "high contrast light", "solarized light":
            return .light
        case "dark", "high contrast dark", "nord", "solarized dark", "dracula", "monokai":
            return .dark
        case "auto (system)":
            return nil
        default:
            return nil
        }
    }

    /// Dark/light for UI that must combine **Auto** with the live `colorScheme` (e.g. Browser, Memory).
    public static func isEffectivelyDark(theme: String, colorScheme: ColorScheme) -> Bool {
        if let resolved = resolvedColorScheme(for: theme) {
            return resolved == .dark
        }
        return colorScheme == .dark
    }

    private static func normalize(_ theme: String) -> String {
        theme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Chrome (chat + sidebar) for named palettes

    /// Main chat / detail background. Falls back to system `textBackgroundColor` for Light / Dark / Auto.
    public static func chatBackground(theme: String) -> Color {
        switch normalize(theme) {
        case "nord":
            return Color(red: 46 / 255, green: 52 / 255, blue: 64 / 255) // Nord0 #2E3440
        case "dracula":
            return Color(red: 40 / 255, green: 42 / 255, blue: 54 / 255) // #282a36
        case "monokai":
            return Color(red: 39 / 255, green: 40 / 255, blue: 34 / 255) // #272822
        case "solarized dark":
            return Color(red: 0, green: 43 / 255, blue: 54 / 255) // base03 #002b36
        case "solarized light":
            return Color(red: 253 / 255, green: 246 / 255, blue: 227 / 255) // base3 #fdf6e3
        default:
            return Color(nsColor: .textBackgroundColor)
        }
    }

    /// Left sidebar; slightly lifted from chat for named themes.
    public static func sidebarBackground(theme: String, colorScheme: ColorScheme) -> Color {
        switch normalize(theme) {
        case "nord":
            return Color(red: 59 / 255, green: 66 / 255, blue: 82 / 255) // Nord1 #3B4252
        case "dracula":
            return Color(red: 33 / 255, green: 34 / 255, blue: 44 / 255) // #21222c
        case "monokai":
            return Color(red: 30 / 255, green: 31 / 255, blue: 28 / 255)
        case "solarized dark":
            return Color(red: 7 / 255, green: 54 / 255, blue: 66 / 255) // base02 #073642
        case "solarized light":
            return Color(red: 238 / 255, green: 232 / 255, blue: 213 / 255) // base2 #eee8d5
        default:
            return colorScheme == .dark
                ? Color(red: 0.176, green: 0.176, blue: 0.176)
                : Color(red: 0.96, green: 0.96, blue: 0.97)
        }
    }

    public static func sidebarBorder(theme: String, colorScheme: ColorScheme) -> Color {
        switch normalize(theme) {
        case "nord", "dracula", "monokai", "solarized dark":
            return Color.white.opacity(0.06)
        case "solarized light":
            return Color(red: 0.85, green: 0.82, blue: 0.75)
        default:
            return colorScheme == .dark
                ? Color.white.opacity(0.08)
                : Color(red: 0.9, green: 0.9, blue: 0.92)
        }
    }

    // MARK: - Typography (config.yaml `font_family`, `font_size`)

    public static func nsFont(family: String, size: CGFloat) -> NSFont {
        let f = family.trimmingCharacters(in: .whitespacesAndNewlines)
        switch f {
        case "System Default", "SF Pro":
            return NSFont.systemFont(ofSize: size)
        case "Helvetica":
            return NSFont(name: "Helvetica", size: size) ?? NSFont.systemFont(ofSize: size)
        case "Arial":
            return NSFont(name: "Arial", size: size) ?? NSFont.systemFont(ofSize: size)
        case "Inter":
            return NSFont(name: "Inter", size: size)
                ?? NSFont(name: "Inter-Regular", size: size)
                ?? NSFont.systemFont(ofSize: size)
        default:
            return NSFont.systemFont(ofSize: size)
        }
    }

    /// Base size from config, clamped for sanity.
    public static func baseFontSize(_ snapshot: UserConfigSnapshot) -> CGFloat {
        CGFloat(min(22, max(10, snapshot.fontSize)))
    }

    /// Scale relative to configured base (`font_size` in YAML).
    public static func scaledSize(_ snapshot: UserConfigSnapshot, delta: CGFloat) -> CGFloat {
        baseFontSize(snapshot) + delta
    }

    /// SwiftUI font for labels using `font_family` + scaled size from `font_size`.
    public static func swiftUIFont(_ snapshot: UserConfigSnapshot, delta: CGFloat, weight: Font.Weight = .regular) -> Font {
        let size = scaledSize(snapshot, delta: delta)
        let fam = snapshot.fontFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        switch fam {
        case "System Default", "SF Pro":
            return .system(size: size, weight: weight)
        case "Helvetica":
            return .custom("Helvetica", size: size).weight(weight)
        case "Arial":
            return .custom("Arial", size: size).weight(weight)
        case "Inter":
            return .custom("Inter", size: size).weight(weight)
        default:
            return .system(size: size, weight: weight)
        }
    }
}
