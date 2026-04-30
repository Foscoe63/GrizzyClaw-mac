import Foundation
import Yams

/// Subset of `~/.grizzyclaw/config.yaml` used by the native Swift Telegram service (no Python daemon required).
public struct TelegramConfig: Sendable, Equatable {
    public var botToken: String?
    public var webhookURL: String?
    public var proxy: String?

    public init(botToken: String? = nil, webhookURL: String? = nil, proxy: String? = nil) {
        self.botToken = botToken
        self.webhookURL = webhookURL
        self.proxy = proxy
    }

    /// Extract the bot id prefix from a `123456:AAAA…` token for display; never returns the secret tail.
    public static func botIdPrefix(token: String) -> String? {
        let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first, !first.isEmpty else { return nil }
        return String(first)
    }
}

extension UserConfigLoader {
    /// Reads Telegram keys (`telegram_bot_token`, `telegram_webhook_url`, `telegram_proxy`) from `config.yaml`.
    public static func loadTelegramConfig(at url: URL = GrizzyClawPaths.configYAML) throws -> TelegramConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return TelegramConfig()
        }
        guard let yamlText = String(data: try Data(contentsOf: url), encoding: .utf8) else {
            throw UserConfigLoader.LoadError.notUTF8(url)
        }
        let parsed = try Yams.load(yaml: yamlText)
        let dict = (parsed as? [String: Any]) ?? [:]
        func s(_ k: String) -> String? {
            guard let v = dict[k], !(v is NSNull) else { return nil }
            if let str = v as? String {
                let t = str.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            return nil
        }
        return TelegramConfig(
            botToken: s("telegram_bot_token"),
            webhookURL: s("telegram_webhook_url"),
            proxy: s("telegram_proxy")
        )
    }
}
