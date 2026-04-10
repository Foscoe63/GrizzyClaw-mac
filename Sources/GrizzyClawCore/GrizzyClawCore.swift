import Foundation

/// Shared metadata and future core types for the native macOS app.
public enum AppInfo {
    public static let marketingVersion = "0.1.0"
    public static let developmentStage = "dev"

    /// Placeholder; set in Xcode target / Info.plist when you add a proper `.app` bundle.
    public static let bundleIdentifier = "com.grizzyclaw.macos"

    public static var versionLabel: String {
        "\(marketingVersion)-\(developmentStage)"
    }
}
