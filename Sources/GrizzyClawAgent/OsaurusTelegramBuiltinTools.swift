import Foundation
import GrizzyClawCore

enum OsaurusTelegramBuiltinTools {
    static func result(tool: String, arguments: [String: Any]) async -> String {
        let composite = "osaurus.telegram.\(tool)"
        switch tool {
        case "health":
            return await callTelegram(
                composite: composite, token: token(arguments), method: "getMe", query: [:])
        case "telegram_send":
            let chat =
                OsaurusBuiltinToolArguments.string(from: arguments, keys: ["chat_id", "chat", "to"])
                ?? ""
            let text =
                OsaurusBuiltinToolArguments.string(from: arguments, keys: ["text", "message", "body"])
                ?? ""
            guard !chat.isEmpty, !text.isEmpty else {
                return ToolEnvelope.failure(
                    tool: composite,
                    kind: "invalid_args",
                    message: "Provide `chat_id` and `text`.",
                    field: "chat_id"
                )
            }
            var q: [String: String] = ["chat_id": chat, "text": text]
            if let mode = OsaurusBuiltinToolArguments.string(from: arguments, keys: ["parse_mode"]) {
                q["parse_mode"] = mode
            }
            return await callTelegram(
                composite: composite, token: token(arguments), method: "sendMessage", query: q)
        case "telegram_list_chats":
            return await callTelegram(
                composite: composite, token: token(arguments), method: "getUpdates", query: [:])
        case "telegram_get_chat_history", "telegram_send_file", "telegram_set_reaction", "webhook":
            return ToolEnvelope.failure(
                tool: composite,
                kind: "not_available_builtin",
                message:
                    "This Telegram Bot API surface is not implemented in Grizzy's built-in driver yet. Use `telegram_send`, `telegram_list_chats` (getUpdates), or `health` (getMe).",
                retryable: false
            )
        default:
            return ToolEnvelope.failure(
                tool: composite,
                kind: "unknown_tool",
                message: "Unknown osaurus.telegram tool `\(tool)`."
            )
        }
    }

    private static func token(_ arguments: [String: Any]) -> String? {
        if let t = OsaurusBuiltinToolArguments.string(from: arguments, keys: ["token", "bot_token"]),
            !t.isEmpty
        {
            return t
        }
        return ProcessInfo.processInfo.environment["GRIZZY_TELEGRAM_BOT_TOKEN"]
    }

    private static func callTelegram(
        composite: String,
        token: String?,
        method: String,
        query: [String: String]
    ) async -> String {
        guard let token, !token.isEmpty else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "missing_secret",
                message:
                    "Set `token` in the tool arguments or configure the `GRIZZY_TELEGRAM_BOT_TOKEN` environment variable for Grizzy.",
                field: "token",
                retryable: false
            )
        }
        var comp = URLComponents(string: "https://api.telegram.org/bot\(token)/\(method)")!
        if !query.isEmpty {
            comp.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comp.url else {
            return ToolEnvelope.failure(tool: composite, kind: "invalid_url", message: "Bad Telegram URL.")
        }
        guard case .allowed(let safe) = GrizzyOutboundHTTPURLPolicy.validateAgentHTTPURL(url.absoluteString)
        else {
            return ToolEnvelope.failure(tool: composite, kind: "invalid_url", message: "Bad Telegram URL.")
        }
        do {
            let res = try await OsaurusBuiltinHTTPClient.perform(
                url: safe,
                method: "GET",
                headers: [:],
                body: nil,
                maxBodyBytes: 2 * 1024 * 1024
            )
            let text =
                String(data: res.body, encoding: .utf8)
                ?? ""
            return ToolEnvelope.success(
                tool: composite,
                result: ["status": res.status, "body": text]
            )
        } catch {
            return ToolEnvelope.fromError(error, tool: composite)
        }
    }
}
