import Foundation
import Yams

/// API keys and other secrets read from `config.yaml` for LLM calls only — do not log or expose in UI.
public struct UserConfigSecrets: Sendable {
    public var openaiApiKey: String?
    public var anthropicApiKey: String?
    public var openrouterApiKey: String?
    public var cursorApiKey: String?
    public var opencodeZenApiKey: String?
    public var lmstudioApiKey: String?
    public var lmstudioV1ApiKey: String?
    public var customProviderApiKey: String?

    public static let empty = UserConfigSecrets(
        openaiApiKey: nil,
        anthropicApiKey: nil,
        openrouterApiKey: nil,
        cursorApiKey: nil,
        opencodeZenApiKey: nil,
        lmstudioApiKey: nil,
        lmstudioV1ApiKey: nil,
        customProviderApiKey: nil
    )

    public init(
        openaiApiKey: String?,
        anthropicApiKey: String?,
        openrouterApiKey: String?,
        cursorApiKey: String?,
        opencodeZenApiKey: String?,
        lmstudioApiKey: String?,
        lmstudioV1ApiKey: String?,
        customProviderApiKey: String?
    ) {
        self.openaiApiKey = openaiApiKey
        self.anthropicApiKey = anthropicApiKey
        self.openrouterApiKey = openrouterApiKey
        self.cursorApiKey = cursorApiKey
        self.opencodeZenApiKey = opencodeZenApiKey
        self.lmstudioApiKey = lmstudioApiKey
        self.lmstudioV1ApiKey = lmstudioV1ApiKey
        self.customProviderApiKey = customProviderApiKey
    }

    init(parsing dict: [String: Any]) {
        func s(_ k: String) -> String? {
            guard let v = dict[k], !(v is NSNull) else { return nil }
            if let str = v as? String {
                let t = str.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            return nil
        }

        self.init(
            openaiApiKey: s("openai_api_key"),
            anthropicApiKey: s("anthropic_api_key"),
            openrouterApiKey: s("openrouter_api_key"),
            cursorApiKey: s("cursor_api_key"),
            opencodeZenApiKey: s("opencode_zen_api_key"),
            lmstudioApiKey: s("lmstudio_api_key"),
            lmstudioV1ApiKey: s("lmstudio_v1_api_key"),
            customProviderApiKey: s("custom_provider_api_key")
        )
    }

    /// Non-empty Keychain values override YAML (same account names as `config.yaml` keys).
    public func mergedWithKeychain() -> UserConfigSecrets {
        func pick(_ yaml: String?, _ account: GrizzyClawKeychain.Account) -> String? {
            if let k = GrizzyClawKeychain.string(for: account) { return k }
            return yaml
        }

        return UserConfigSecrets(
            openaiApiKey: pick(openaiApiKey, .openaiApiKey),
            anthropicApiKey: pick(anthropicApiKey, .anthropicApiKey),
            openrouterApiKey: pick(openrouterApiKey, .openrouterApiKey),
            cursorApiKey: pick(cursorApiKey, .cursorApiKey),
            opencodeZenApiKey: pick(opencodeZenApiKey, .opencodeZenApiKey),
            lmstudioApiKey: pick(lmstudioApiKey, .lmstudioApiKey),
            lmstudioV1ApiKey: pick(lmstudioV1ApiKey, .lmstudioV1ApiKey),
            customProviderApiKey: pick(customProviderApiKey, .customProviderApiKey)
        )
    }
}

extension UserConfigLoader {
    /// Loads API keys from the same `config.yaml` used by the Python app (never print these values).
    public static func loadSecrets(at url: URL = GrizzyClawPaths.configYAML) throws -> UserConfigSecrets {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }
        guard let yamlText = String(data: try Data(contentsOf: url), encoding: .utf8) else {
            throw UserConfigLoader.LoadError.notUTF8(url)
        }
        let parsed = try Yams.load(yaml: yamlText)
        let dict = (parsed as? [String: Any]) ?? [:]
        return UserConfigSecrets(parsing: dict)
    }

    /// YAML secrets plus Keychain overrides (preferred when a Keychain item exists).
    public static func loadSecretsWithKeychain(at url: URL = GrizzyClawPaths.configYAML) throws -> UserConfigSecrets {
        try loadSecrets(at: url).mergedWithKeychain()
    }
}
