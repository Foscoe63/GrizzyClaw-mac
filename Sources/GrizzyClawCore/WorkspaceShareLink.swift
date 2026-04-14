import Foundation

/// Python `WorkspaceManager.export_workspace_to_link` / `import_workspace_from_link`: URL-safe base64 JSON (workspace dict without `id` on export; new id on import).
public enum WorkspaceShareLink {
    public static func exportBase64URL(_ record: WorkspaceRecord) throws -> String {
        var o: [String: Any] = [:]
        o["name"] = record.name
        o["description"] = record.description ?? ""
        o["icon"] = record.icon ?? "🤖"
        o["color"] = record.color ?? "#007AFF"
        o["order"] = record.order ?? 0
        if let ap = record.avatarPath, !ap.isEmpty {
            o["avatar_path"] = ap
        }
        if let cfg = record.config {
            o["config"] = try cfg.jsonSerializationValue()
        } else {
            o["config"] = [String: Any]()
        }
        o["created_at"] = record.createdAt ?? isoNow()
        o["updated_at"] = record.updatedAt ?? isoNow()
        o["is_active"] = record.isActive ?? true
        o["is_default"] = record.isDefault ?? false
        o["session_count"] = record.sessionCount ?? 0
        o["message_count"] = record.messageCount ?? 0
        o["total_response_time_ms"] = record.totalResponseTimeMs ?? 0.0
        o["total_input_tokens"] = record.totalInputTokens ?? 0
        o["total_output_tokens"] = record.totalOutputTokens ?? 0
        o["feedback_up"] = record.feedbackUp ?? 0
        o["feedback_down"] = record.feedbackDown ?? 0

        let data = try JSONSerialization.data(withJSONObject: o, options: [])
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    /// Decodes a pasted link to a JSON object (Python `urlsafe_b64decode` + `json.loads`).
    public static func decodeImportPayload(_ link: String) throws -> [String: Any] {
        var s = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { throw WorkspaceMutationError.invalidShareLink }
        s = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = (4 - s.count % 4) % 4
        if pad > 0 {
            s += String(repeating: "=", count: pad)
        }
        guard let data = Data(base64Encoded: s) else {
            throw WorkspaceMutationError.invalidShareLink
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WorkspaceMutationError.invalidShareLink
        }
        guard obj["name"] is String else {
            throw WorkspaceMutationError.invalidShareLink
        }
        return obj
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
