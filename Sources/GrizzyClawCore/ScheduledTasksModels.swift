import Foundation

/// Optional MCP post-action after a scheduled run (`scheduler_dialog.py` / `AgentCore._run_scheduled_task_action`).
public struct MCPPostActionRecord: Codable, Equatable, Sendable {
    public var mcp: String
    public var tool: String
    public var arguments: [String: JSONValue]?

    public init(mcp: String, tool: String, arguments: [String: JSONValue]? = nil) {
        self.mcp = mcp
        self.tool = tool
        self.arguments = arguments
    }
}

/// One row in `~/.grizzyclaw/scheduled_tasks.json` (`AgentCore._save_scheduled_tasks`).
public struct ScheduledTaskRecord: Codable, Equatable, Identifiable, Sendable {
    public var taskId: String
    public var userId: String
    public var name: String
    public var cron: String
    public var message: String
    public var mcpPostAction: MCPPostActionRecord?

    public var id: String { taskId }

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case legacyId = "id"
        case userId = "user_id"
        case name
        case cron
        case message
        case mcpPostAction = "mcp_post_action"
    }

    public init(
        taskId: String,
        userId: String,
        name: String,
        cron: String,
        message: String,
        mcpPostAction: MCPPostActionRecord? = nil
    ) {
        self.taskId = taskId
        self.userId = userId
        self.name = name
        self.cron = cron
        self.message = message
        self.mcpPostAction = mcpPostAction
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let tid = try c.decodeIfPresent(String.self, forKey: .taskId) {
            taskId = tid
        } else if let legacy = try c.decodeIfPresent(String.self, forKey: .legacyId) {
            taskId = legacy
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing task_id"))
        }
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? "gui_user"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Unnamed"
        cron = try c.decodeIfPresent(String.self, forKey: .cron) ?? ""
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        mcpPostAction = try c.decodeIfPresent(MCPPostActionRecord.self, forKey: .mcpPostAction)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(taskId, forKey: .taskId)
        try c.encode(userId, forKey: .userId)
        try c.encode(name, forKey: .name)
        try c.encode(cron, forKey: .cron)
        try c.encode(message, forKey: .message)
        if let mcpPostAction {
            try c.encode(mcpPostAction, forKey: .mcpPostAction)
        }
    }
}

private struct ScheduledTasksFile: Codable {
    var tasks: [ScheduledTaskRecord]
}

/// Load/save `scheduled_tasks.json` next to the Python app.
public enum ScheduledTasksPersistence {
    public static func load(from url: URL = GrizzyClawPaths.scheduledTasksJSON) throws -> [ScheduledTaskRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(ScheduledTasksFile.self, from: data)
        return file.tasks
    }

    public static func save(_ tasks: [ScheduledTaskRecord], to url: URL = GrizzyClawPaths.scheduledTasksJSON) throws {
        try GrizzyClawPaths.ensureUserDataDirectoryExists()
        let file = ScheduledTasksFile(tasks: tasks)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(file)
        try data.write(to: url, options: .atomic)
    }

    @discardableResult
    public static func createTask(
        name: String,
        cron: String,
        message: String,
        mcpPostAction: MCPPostActionRecord? = nil,
        userId: String = "gui_user",
        to url: URL = GrizzyClawPaths.scheduledTasksJSON
    ) throws -> ScheduledTaskRecord {
        var tasks = try load(from: url)
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        let record = ScheduledTaskRecord(
            taskId: "task_\(suffix)",
            userId: userId,
            name: name,
            cron: cron,
            message: message,
            mcpPostAction: mcpPostAction
        )
        tasks.append(record)
        try save(tasks, to: url)
        return record
    }
}
