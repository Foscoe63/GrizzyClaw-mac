import Foundation

/// Osaurus-style tool envelope used for both internal tools and MCP results.
///
/// We keep this as a tiny encoding/decoding helper around JSON strings because
/// the chat loop needs to pass tool results back to the model as text.
public enum ToolEnvelope {
    // MARK: - Encode

    public static func success(tool: String? = nil, result: Any, warnings: [String]? = nil) -> String {
        var obj: [String: Any] = [
            "ok": true,
            "result": result,
        ]
        if let tool, !tool.isEmpty { obj["tool"] = tool }
        if let warnings, !warnings.isEmpty { obj["warnings"] = warnings }
        return safeJSONString(obj) ?? "{\"ok\":true,\"result\":null}"
    }

    /// Convenience for `result: { "text": "..." }`.
    public static func success(tool: String? = nil, text: String, warnings: [String]? = nil) -> String {
        success(tool: tool, result: ["text": text], warnings: warnings)
    }

    public static func failure(
        tool: String? = nil,
        kind: String,
        message: String,
        field: String? = nil,
        expected: String? = nil,
        retryable: Bool? = nil
    ) -> String {
        var obj: [String: Any] = [
            "ok": false,
            "kind": kind,
            "message": message,
        ]
        if let tool, !tool.isEmpty { obj["tool"] = tool }
        if let field, !field.isEmpty { obj["field"] = field }
        if let expected, !expected.isEmpty { obj["expected"] = expected }
        if let retryable { obj["retryable"] = retryable }
        return safeJSONString(obj) ?? "{\"ok\":false,\"kind\":\"execution_error\",\"message\":\"Tool failed\"}"
    }

    public static func fromError(_ error: Error, tool: String? = nil) -> String {
        // Keep it simple: treat unknown errors as execution_error.
        failure(
            tool: tool,
            kind: "execution_error",
            message: error.localizedDescription,
            retryable: true
        )
    }

    // MARK: - Decode helpers

    public static func isEnvelope(_ raw: String) -> Bool {
        guard let obj = decode(raw) else { return false }
        return obj["ok"] != nil
    }

    public static func isSuccess(_ raw: String) -> Bool {
        guard let obj = decode(raw) else { return false }
        return (obj["ok"] as? Bool) == true
    }

    public static func isFailure(_ raw: String) -> Bool {
        guard let obj = decode(raw) else { return false }
        return (obj["ok"] as? Bool) == false
    }

    /// If this is a success envelope and the payload is `{"text": ...}`, return it.
    public static func successText(_ raw: String) -> String? {
        guard let obj = decode(raw) else { return nil }
        guard (obj["ok"] as? Bool) == true else { return nil }
        guard let result = obj["result"] as? [String: Any] else { return nil }
        return result["text"] as? String
    }

    public static func failureMessage(_ raw: String) -> String? {
        guard let obj = decode(raw) else { return nil }
        guard (obj["ok"] as? Bool) == false else { return nil }
        return obj["message"] as? String
    }

    private static func decode(_ raw: String) -> [String: Any]? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("{"), let data = t.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return obj as? [String: Any]
    }

    private static func safeJSONString(_ obj: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(obj) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

