import Foundation
import GrizzyClawCore

enum OsaurusResendBuiltinTools {
    static func result(tool: String, arguments: [String: Any]) async -> String {
        let composite = "osaurus.resend.\(tool)"
        switch tool {
        case "health":
            return await ping(composite: composite, arguments: arguments)
        case "resend_send":
            return await send(composite: composite, arguments: arguments)
        case "resend_reply", "resend_list_threads", "resend_get_thread", "resend_label_thread", "webhook",
            "reset_webhook":
            return ToolEnvelope.failure(
                tool: composite,
                kind: "not_available_builtin",
                message:
                    "Only `resend_send` and `health` are implemented in Grizzy's built-in Resend driver for now.",
                retryable: false
            )
        default:
            return ToolEnvelope.failure(
                tool: composite,
                kind: "unknown_tool",
                message: "Unknown osaurus.resend tool `\(tool)`."
            )
        }
    }

    private static func apiKey(_ arguments: [String: Any]) -> String? {
        if let k = OsaurusBuiltinToolArguments.string(from: arguments, keys: ["api_key", "key"]), !k.isEmpty {
            return k
        }
        return ProcessInfo.processInfo.environment["GRIZZY_RESEND_API_KEY"]
    }

    private static func ping(composite: String, arguments: [String: Any]) async -> String {
        guard let key = apiKey(arguments) else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "missing_secret",
                message: "Provide `api_key` or set `GRIZZY_RESEND_API_KEY` for Grizzy.",
                field: "api_key",
                retryable: false
            )
        }
        guard case .allowed(let url) = GrizzyOutboundHTTPURLPolicy.validateAgentHTTPURL(
            "https://api.resend.com/emails")
        else {
            return ToolEnvelope.failure(tool: composite, kind: "invalid_url", message: "Bad Resend URL.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let text = String(data: data, encoding: .utf8) ?? ""
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            return ToolEnvelope.success(
                tool: composite,
                result: ["status": code, "body": text]
            )
        } catch {
            return ToolEnvelope.fromError(error, tool: composite)
        }
    }

    private static func send(composite: String, arguments: [String: Any]) async -> String {
        guard let key = apiKey(arguments) else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "missing_secret",
                message: "Provide `api_key` or set `GRIZZY_RESEND_API_KEY` for Grizzy.",
                field: "api_key",
                retryable: false
            )
        }
        let from =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["from", "sender"]) ?? ""
        let to = OsaurusBuiltinToolArguments.string(from: arguments, keys: ["to", "recipient"]) ?? ""
        let subject = OsaurusBuiltinToolArguments.string(from: arguments, keys: ["subject", "title"]) ?? ""
        let html = OsaurusBuiltinToolArguments.string(from: arguments, keys: ["html", "body_html"])
        let textBody = OsaurusBuiltinToolArguments.string(from: arguments, keys: ["text", "body"])
        guard !from.isEmpty, !to.isEmpty, !subject.isEmpty else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Provide `from`, `to`, and `subject` (plus `html` or `text`).",
                field: "from"
            )
        }
        guard html != nil || textBody != nil else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Provide `html` and/or `text` body content.",
                field: "html"
            )
        }
        var payload: [String: Any] = ["from": from, "to": [to], "subject": subject]
        if let html { payload["html"] = html }
        if let textBody { payload["text"] = textBody }
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
            case .allowed(let url) = GrizzyOutboundHTTPURLPolicy.validateAgentHTTPURL(
                "https://api.resend.com/emails")
        else {
            return ToolEnvelope.failure(tool: composite, kind: "invalid_args", message: "Could not build request.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let text = String(data: data, encoding: .utf8) ?? ""
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            return ToolEnvelope.success(
                tool: composite,
                result: ["status": code, "body": text]
            )
        } catch {
            return ToolEnvelope.fromError(error, tool: composite)
        }
    }
}
