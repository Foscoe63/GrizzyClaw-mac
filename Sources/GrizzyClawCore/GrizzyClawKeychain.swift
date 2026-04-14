import Foundation
import Security

/// Generic-password Keychain storage for API keys. Account strings match `config.yaml` field names (e.g. `openai_api_key`) so overrides are predictable.
public enum GrizzyClawKeychain {
    public static let service = "com.grizzyclaw.mac.apikeys"

    public enum Account: String, CaseIterable, Sendable {
        case openaiApiKey = "openai_api_key"
        case anthropicApiKey = "anthropic_api_key"
        case openrouterApiKey = "openrouter_api_key"
        case cursorApiKey = "cursor_api_key"
        case opencodeZenApiKey = "opencode_zen_api_key"
        case lmstudioApiKey = "lmstudio_api_key"
        case lmstudioV1ApiKey = "lmstudio_v1_api_key"
        case customProviderApiKey = "custom_provider_api_key"
    }

    /// Returns a non-empty UTF-8 string, or `nil` if missing / unreadable.
    public static func string(for account: Account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let s, !s.isEmpty else { return nil }
        return s
    }

    /// Stores a secret; pass `nil` or empty string to delete the item.
    @discardableResult
    public static func setString(_ value: String?, for account: Account) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return true
        }
        guard let data = value.data(using: .utf8) else { return false }
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let st = SecItemAdd(attrs as CFDictionary, nil)
        return st == errSecSuccess
    }
}
