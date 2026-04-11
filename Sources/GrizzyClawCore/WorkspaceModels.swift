import Foundation

/// Root of `~/.grizzyclaw/workspaces.json` (Python `WorkspaceManager._save_workspaces`).
public struct WorkspacesFile: Codable, Sendable {
    public let activeWorkspaceId: String?
    public let baselineWorkspaceId: String?
    public let workspaces: [WorkspaceRecord]

    enum CodingKeys: String, CodingKey {
        case activeWorkspaceId = "active_workspace_id"
        case baselineWorkspaceId = "baseline_workspace_id"
        case workspaces
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

public enum WorkspaceIndexLoader {
    public static func load(from url: URL) throws -> WorkspaceIndex {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let file = try decoder.decode(WorkspacesFile.self, from: data)
        return WorkspaceIndex(
            workspaces: file.workspaces,
            activeWorkspaceId: file.activeWorkspaceId,
            baselineWorkspaceId: file.baselineWorkspaceId
        )
    }
}
