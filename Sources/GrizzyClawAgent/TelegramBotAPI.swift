import Foundation
import GrizzyClawCore

/// Minimal Telegram Bot API client used by the native Swift Telegram service
/// (replaces the Python daemon's `gateway` + webhook/polling loop for basic chat).
public enum TelegramBotAPI {
    public struct Message: Sendable {
        public let updateId: Int64
        public let chatId: Int64
        public let text: String
        public let from: String?
        public let messageId: Int64?
    }

    public enum APIError: LocalizedError, Sendable {
        case emptyToken
        case invalidURL(String)
        case httpError(Int, String)
        case telegramError(Int, String)
        case decode(String)

        public var errorDescription: String? {
            switch self {
            case .emptyToken:
                return "Telegram bot token is empty (set `telegram_bot_token` in ~/.grizzyclaw/config.yaml)."
            case .invalidURL(let s):
                return "Invalid Telegram API URL: \(s)"
            case .httpError(let code, let msg):
                return "Telegram HTTP \(code): \(msg)"
            case .telegramError(let code, let desc):
                return "Telegram error \(code): \(desc)"
            case .decode(let m):
                return "Telegram decode error: \(m)"
            }
        }
    }

    /// Calls `getMe` and returns the bot's username on success (used for connection test / status).
    public static func getMe(token: String, session: URLSession = .shared) async throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIError.emptyToken }
        guard let url = URL(string: "https://api.telegram.org/bot\(trimmed)/getMe") else {
            throw APIError.invalidURL("getMe")
        }
        GrizzyClawLog.debug("TelegramBotAPI.getMe → GET \(url.absoluteString.replacingOccurrences(of: trimmed, with: "<TOKEN>"))")
        let (data, resp) = try await session.data(from: url)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        GrizzyClawLog.debug("TelegramBotAPI.getMe ← HTTP \(status) bytes=\(data.count)")
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            GrizzyClawLog.error("TelegramBotAPI.getMe HTTP \(status) body=\(body)")
            throw APIError.httpError(status, body)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decode("getMe: not JSON object")
        }
        if let ok = obj["ok"] as? Bool, !ok {
            let desc = obj["description"] as? String ?? "unknown"
            let code = obj["error_code"] as? Int ?? -1
            throw APIError.telegramError(code, desc)
        }
        let result = obj["result"] as? [String: Any]
        return (result?["username"] as? String) ?? (result?["first_name"] as? String) ?? "bot"
    }

    /// `getUpdates` with long-poll timeout. Returns `[Message]` (only `text` messages) and the new offset.
    public static func getUpdates(
        token: String,
        offset: Int64?,
        timeoutSeconds: Int,
        session: URLSession
    ) async throws -> (messages: [Message], nextOffset: Int64) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIError.emptyToken }
        var components = URLComponents(
            string: "https://api.telegram.org/bot\(trimmed)/getUpdates"
        )
        guard components != nil else { throw APIError.invalidURL("getUpdates") }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "timeout", value: String(timeoutSeconds)),
            URLQueryItem(name: "allowed_updates", value: "[\"message\"]"),
        ]
        if let off = offset {
            queryItems.append(URLQueryItem(name: "offset", value: String(off)))
        }
        components?.queryItems = queryItems
        guard let url = components?.url else { throw APIError.invalidURL("getUpdates") }

        var req = URLRequest(url: url)
        req.timeoutInterval = TimeInterval(timeoutSeconds + 10)

        let redacted = url.absoluteString.replacingOccurrences(of: trimmed, with: "<TOKEN>")
        GrizzyClawLog.debug("TelegramBotAPI.getUpdates → GET \(redacted)")
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        GrizzyClawLog.debug("TelegramBotAPI.getUpdates ← HTTP \(status) bytes=\(data.count)")
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            GrizzyClawLog.error("TelegramBotAPI.getUpdates HTTP \(status) body=\(body)")
            throw APIError.httpError(status, body)
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.decode("getUpdates: not JSON object")
        }
        if let ok = obj["ok"] as? Bool, !ok {
            let desc = obj["description"] as? String ?? "unknown"
            let code = obj["error_code"] as? Int ?? -1
            GrizzyClawLog.error("TelegramBotAPI.getUpdates telegram error \(code): \(desc)")
            throw APIError.telegramError(code, desc)
        }
        let rawUpdates = (obj["result"] as? [[String: Any]]) ?? []
        var messages: [Message] = []
        var maxUpdateId: Int64 = offset ?? 0
        for u in rawUpdates {
            guard let updateId = (u["update_id"] as? NSNumber)?.int64Value else { continue }
            if updateId + 1 > maxUpdateId { maxUpdateId = updateId + 1 }
            guard let m = u["message"] as? [String: Any] else { continue }
            guard let text = m["text"] as? String, !text.isEmpty else { continue }
            guard let chat = m["chat"] as? [String: Any],
                  let chatId = (chat["id"] as? NSNumber)?.int64Value else { continue }
            let fromUser = m["from"] as? [String: Any]
            let fromName: String? = {
                if let u = fromUser?["username"] as? String, !u.isEmpty { return u }
                if let f = fromUser?["first_name"] as? String, !f.isEmpty { return f }
                return nil
            }()
            let msgId = (m["message_id"] as? NSNumber)?.int64Value
            messages.append(
                Message(
                    updateId: updateId,
                    chatId: chatId,
                    text: text,
                    from: fromName,
                    messageId: msgId
                )
            )
        }
        let next = offset.map { max($0, maxUpdateId) } ?? maxUpdateId
        return (messages, next)
    }

    /// Sends a plain text message. Telegram limits message text to 4096 characters; longer text is split.
    public static func sendMessage(
        token: String,
        chatId: Int64,
        text: String,
        replyToMessageId: Int64? = nil,
        session: URLSession = .shared
    ) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIError.emptyToken }
        guard let url = URL(string: "https://api.telegram.org/bot\(trimmed)/sendMessage") else {
            throw APIError.invalidURL("sendMessage")
        }

        let chunks = Self.splitForTelegram(text)
        GrizzyClawLog.debug(
            "TelegramBotAPI.sendMessage chat=\(chatId) chunks=\(chunks.count) totalLen=\(text.count) replyTo=\(replyToMessageId.map(String.init) ?? "nil")"
        )
        for (i, chunk) in chunks.enumerated() {
            var body: [String: Any] = [
                "chat_id": chatId,
                "text": chunk,
                "disable_web_page_preview": true,
            ]
            if i == 0, let r = replyToMessageId {
                body["reply_to_message_id"] = r
                body["allow_sending_without_reply"] = true
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await session.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            GrizzyClawLog.debug("TelegramBotAPI.sendMessage chunk#\(i + 1)/\(chunks.count) chat=\(chatId) ← HTTP \(status)")
            guard (200..<300).contains(status) else {
                let bodyStr = String(data: data, encoding: .utf8) ?? ""
                GrizzyClawLog.error("TelegramBotAPI.sendMessage HTTP \(status) chat=\(chatId) body=\(bodyStr)")
                throw APIError.httpError(status, bodyStr)
            }
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let ok = obj["ok"] as? Bool, !ok
            {
                let desc = obj["description"] as? String ?? "unknown"
                let code = obj["error_code"] as? Int ?? -1
                GrizzyClawLog.error("TelegramBotAPI.sendMessage telegram error \(code) chat=\(chatId): \(desc)")
                throw APIError.telegramError(code, desc)
            }
        }
    }

    /// Clears a previously-set webhook so `getUpdates` long-polling can receive messages
    /// (Telegram refuses `getUpdates` when a webhook URL is active).
    public static func deleteWebhook(token: String, session: URLSession = .shared) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIError.emptyToken }
        guard let url = URL(string: "https://api.telegram.org/bot\(trimmed)/deleteWebhook?drop_pending_updates=false") else {
            throw APIError.invalidURL("deleteWebhook")
        }
        GrizzyClawLog.debug("TelegramBotAPI.deleteWebhook → GET /deleteWebhook")
        let (data, resp) = try await session.data(from: url)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        GrizzyClawLog.debug("TelegramBotAPI.deleteWebhook ← HTTP \(status)")
        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            GrizzyClawLog.error("TelegramBotAPI.deleteWebhook HTTP \(status) body=\(body)")
            throw APIError.httpError(status, body)
        }
        if let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let ok = obj["ok"] as? Bool, !ok
        {
            let desc = obj["description"] as? String ?? "unknown"
            let code = obj["error_code"] as? Int ?? -1
            GrizzyClawLog.error("TelegramBotAPI.deleteWebhook telegram error \(code): \(desc)")
            throw APIError.telegramError(code, desc)
        }
    }

    /// Telegram maxes out at ~4096 chars per message; split on paragraph/line boundaries when possible.
    private static func splitForTelegram(_ text: String) -> [String] {
        let limit = 4000
        if text.count <= limit { return [text] }
        var chunks: [String] = []
        var remaining = text[...]
        while remaining.count > limit {
            let end = remaining.index(remaining.startIndex, offsetBy: limit)
            var cut = end
            if let nl = remaining[remaining.startIndex..<end].lastIndex(of: "\n") {
                cut = remaining.index(after: nl)
            }
            chunks.append(String(remaining[remaining.startIndex..<cut]))
            remaining = remaining[cut...]
        }
        if !remaining.isEmpty {
            chunks.append(String(remaining))
        }
        return chunks
    }
}
