import Foundation

/// Root of `~/.grizzyclaw/workspaces.json` (Python `WorkspaceManager._save_workspaces`).
public struct WorkspacesFile: Codable, Sendable {
    public var activeWorkspaceId: String?
    public var baselineWorkspaceId: String?
    public var workspaces: [WorkspaceRecord]

    enum CodingKeys: String, CodingKey {
        case activeWorkspaceId = "active_workspace_id"
        case baselineWorkspaceId = "baseline_workspace_id"
        case workspaces
    }

    public init(activeWorkspaceId: String?, baselineWorkspaceId: String?, workspaces: [WorkspaceRecord]) {
        self.activeWorkspaceId = activeWorkspaceId
        self.baselineWorkspaceId = baselineWorkspaceId
        self.workspaces = workspaces
    }
}

/// One workspace entry; mirrors Python `Workspace.to_dict` / `from_dict` fields we need for UI and tooling.
public struct WorkspaceRecord: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let icon: String?
    public let color: String?
    public let order: Int?
    public let avatarPath: String?
    public let config: JSONValue?
    public let createdAt: String?
    public let updatedAt: String?
    public let isActive: Bool?
    public let isDefault: Bool?
    public let sessionCount: Int?
    public let messageCount: Int?
    public let totalResponseTimeMs: Double?
    public let totalInputTokens: Int?
    public let totalOutputTokens: Int?
    public let feedbackUp: Int?
    public let feedbackDown: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, description, icon, color, order
        case avatarPath = "avatar_path"
        case config
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isActive = "is_active"
        case isDefault = "is_default"
        case sessionCount = "session_count"
        case messageCount = "message_count"
        case totalResponseTimeMs = "total_response_time_ms"
        case totalInputTokens = "total_input_tokens"
        case totalOutputTokens = "total_output_tokens"
        case feedbackUp = "feedback_up"
        case feedbackDown = "feedback_down"
    }
}

/// Sorted, read-only snapshot after loading `workspaces.json`.
public struct WorkspaceIndex: Sendable {
    public let workspaces: [WorkspaceRecord]
    public let activeWorkspaceId: String?
    public let baselineWorkspaceId: String?

    public init(workspaces: [WorkspaceRecord], activeWorkspaceId: String?, baselineWorkspaceId: String?) {
        self.workspaces = Self.sorted(workspaces)
        self.activeWorkspaceId = activeWorkspaceId
        self.baselineWorkspaceId = baselineWorkspaceId
    }

    private static func sorted(_ items: [WorkspaceRecord]) -> [WorkspaceRecord] {
        items.sorted { a, b in
            let oa = a.order ?? 0
            let ob = b.order ?? 0
            if oa != ob { return oa < ob }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

extension WorkspaceRecord {
    /// New workspace row matching Python `WorkspaceManager.create_workspace` defaults.
    public static func makeNew(
        id: String,
        name: String,
        description: String?,
        icon: String,
        color: String,
        order: Int,
        config: JSONValue? = nil,
        isDefault: Bool = false
    ) -> WorkspaceRecord {
        let now = workspaceISO8601Now()
        return WorkspaceRecord(
            id: id,
            name: name,
            description: description,
            icon: icon,
            color: color,
            order: order,
            avatarPath: nil,
            config: config ?? .object([:]),
            createdAt: now,
            updatedAt: now,
            isActive: true,
            isDefault: isDefault,
            sessionCount: 0,
            messageCount: 0,
            totalResponseTimeMs: 0,
            totalInputTokens: 0,
            totalOutputTokens: 0,
            feedbackUp: 0,
            feedbackDown: 0
        )
    }

    /// Copy with edited fields (full row from workspace editor).
    /// Same row with a new `order` (for drag-reorder in the UI).
    public func reordering(to newOrder: Int) -> WorkspaceRecord {
        updatingFields(
            name: name,
            description: description,
            icon: icon ?? "🤖",
            color: color ?? "#007AFF",
            order: newOrder,
            config: config
        )
    }

    public func updatingFields(
        name: String,
        description: String?,
        icon: String,
        color: String,
        order: Int,
        config: JSONValue?
    ) -> WorkspaceRecord {
        let now = workspaceISO8601Now()
        return WorkspaceRecord(
            id: id,
            name: name,
            description: description,
            icon: icon,
            color: color,
            order: order,
            avatarPath: avatarPath,
            config: config ?? self.config,
            createdAt: createdAt,
            updatedAt: now,
            isActive: isActive,
            isDefault: isDefault,
            sessionCount: sessionCount,
            messageCount: messageCount,
            totalResponseTimeMs: totalResponseTimeMs,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            feedbackUp: feedbackUp,
            feedbackDown: feedbackDown
        )
    }

    /// Full row update for the workspace editor (Python `WorkspaceDialog` parity), including avatar path.
    public func updatingEditor(
        name: String,
        description: String?,
        icon: String,
        color: String,
        order: Int,
        avatarPath: String?,
        config: JSONValue?
    ) -> WorkspaceRecord {
        let now = workspaceISO8601Now()
        return WorkspaceRecord(
            id: id,
            name: name,
            description: description,
            icon: icon,
            color: color,
            order: order,
            avatarPath: avatarPath,
            config: config ?? self.config,
            createdAt: createdAt,
            updatedAt: now,
            isActive: isActive,
            isDefault: isDefault,
            sessionCount: sessionCount,
            messageCount: messageCount,
            totalResponseTimeMs: totalResponseTimeMs,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            feedbackUp: feedbackUp,
            feedbackDown: feedbackDown
        )
    }
}

extension WorkspaceRecord {
    /// Python `WorkspaceManager.record_feedback` — increments `feedback_up` or `feedback_down` and updates `updated_at`.
    public func recordingFeedback(up: Bool) -> WorkspaceRecord {
        let nu = (feedbackUp ?? 0) + (up ? 1 : 0)
        let nd = (feedbackDown ?? 0) + (up ? 0 : 1)
        return WorkspaceRecord(
            id: id,
            name: name,
            description: description,
            icon: icon,
            color: color,
            order: order,
            avatarPath: avatarPath,
            config: config,
            createdAt: createdAt,
            updatedAt: workspaceISO8601Now(),
            isActive: isActive,
            isDefault: isDefault,
            sessionCount: sessionCount,
            messageCount: messageCount,
            totalResponseTimeMs: totalResponseTimeMs,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            feedbackUp: nu,
            feedbackDown: nd
        )
    }

    /// Python `WorkspaceManager.get_workspace_slug` — lowercased name, spaces and hyphens → underscores.
    public var mentionSlug: String {
        name.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }

    /// Python `Workspace.config.enable_inter_agent` — required for discoverable @mentions.
    public var interAgentEnabled: Bool {
        config?.bool(forKey: "enable_inter_agent") ?? false
    }

    /// Work-mode project folder (`work_folder_path` in workspace config).
    public var workFolderPath: String {
        let raw = config?.string(forKey: "work_folder_path") ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Builds a row from Python `import_workspace_from_link` payload (new id and order assigned by caller).
    public static func fromImportPayload(_ raw: [String: Any], newId: String, order: Int) throws -> WorkspaceRecord {
        var m = raw
        m.removeValue(forKey: "id")
        m["id"] = newId
        m["order"] = order
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: m, options: [])
        } catch {
            throw WorkspaceMutationError.invalidShareLink
        }
        do {
            return try JSONDecoder().decode(WorkspaceRecord.self, from: data)
        } catch {
            let name = (raw["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { throw WorkspaceMutationError.invalidShareLink }
            let desc = raw["description"] as? String
            let icon = raw["icon"] as? String ?? "🤖"
            let color = raw["color"] as? String ?? "#007AFF"
            let avatarPath = raw["avatar_path"] as? String
            let config: JSONValue?
            if let c = raw["config"] {
                config = try? JSONValue.decode(fromJSONObject: c)
            } else {
                config = .object([:])
            }
            return WorkspaceRecord(
                id: newId,
                name: name,
                description: desc,
                icon: icon,
                color: color,
                order: order,
                avatarPath: avatarPath,
                config: config ?? .object([:]),
                createdAt: raw["created_at"] as? String,
                updatedAt: raw["updated_at"] as? String,
                isActive: raw["is_active"] as? Bool ?? true,
                isDefault: raw["is_default"] as? Bool ?? false,
                sessionCount: raw["session_count"] as? Int,
                messageCount: raw["message_count"] as? Int,
                totalResponseTimeMs: Self.doubleish(raw["total_response_time_ms"]),
                totalInputTokens: raw["total_input_tokens"] as? Int,
                totalOutputTokens: raw["total_output_tokens"] as? Int,
                feedbackUp: raw["feedback_up"] as? Int,
                feedbackDown: raw["feedback_down"] as? Int
            )
        }
    }

    private static func doubleish(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        return nil
    }
}

private func workspaceISO8601Now() -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: Date())
}

public enum WorkspaceIndexLoader {
    public static func load(from url: URL) throws -> WorkspaceIndex {
        let file = try loadFile(from: url)
        return WorkspaceIndex(
            workspaces: file.workspaces,
            activeWorkspaceId: file.activeWorkspaceId,
            baselineWorkspaceId: file.baselineWorkspaceId
        )
    }

    public static func loadFile(from url: URL) throws -> WorkspacesFile {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(WorkspacesFile.self, from: data)
    }

    public static func save(_ file: WorkspacesFile, to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(file)
        try data.write(to: url, options: .atomic)
    }
}
