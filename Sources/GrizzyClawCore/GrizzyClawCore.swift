import Foundation

/// Shared metadata and future core types for the native macOS app.
public enum AppInfo {
    /// Short version from `CFBundleShortVersionString`, or `0.1.0` when running without a bundle (e.g. `swift run`).
    public static var marketingVersion: String {
        if let s = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s
        }
        return "0.1.0"
    }

    /// Build/revision label from `CFBundleVersion`, or `"dev"` when absent.
    public static var buildVersion: String {
        if let s = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s
        }
        return "dev"
    }

    public static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.grizzyclaw.macos"
    }

    public static var versionLabel: String {
        "\(marketingVersion) (\(buildVersion))"
    }
}

