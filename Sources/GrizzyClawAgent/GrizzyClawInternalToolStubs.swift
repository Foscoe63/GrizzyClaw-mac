import Foundation
import GrizzyClawCore

/// Handles `mcp: grizzyclaw` tools in native Mac chat (Python agent has full implementations).
public enum GrizzyClawInternalToolStubs {
    public static func result(
        tool: String,
        arguments: [String: Any],
        workspaceId: String?,
        config: UserConfigSnapshot
    ) -> String {
        result(
            tool: tool,
            arguments: arguments,
            workspaceId: workspaceId,
            config: config,
            scheduledTasksURL: GrizzyClawPaths.scheduledTasksJSON
        )
    }

    static func result(
        tool: String,
        arguments: [String: Any],
        workspaceId: String?,
        config: UserConfigSnapshot,
        scheduledTasksURL: URL
    ) -> String {
        switch tool {
        case "get_status":
            return """
            **GrizzyClaw (Mac native chat)**
            - Chat uses this app’s streaming client to your configured LLM provider (not the Python daemon).
            - Active workspace id: \(workspaceId ?? "(none)")
            - MCP servers file: \(config.mcpServersFile)
            """
        case "create_scheduled_task":
            return createScheduledTask(arguments: arguments, scheduledTasksURL: scheduledTasksURL)
        case "list_scheduled_tasks":
            return listScheduledTasks(from: scheduledTasksURL)
        case "run_scheduled_task":
            let tid = (arguments["task_id"] as? String) ?? String(describing: arguments["task_id"] ?? "")
            return "To run task id \(tid) immediately, use **Scheduler → Run now** (Python agent) or the web/Python chat with the full agent."
        case "search_transcripts":
            return "Transcript search is not implemented in native Mac chat. Use Python/web chat for `search_transcripts`, or export this session and search locally."
        default:
            return "**❌ Unknown grizzyclaw tool `\(tool)`.**"
        }
    }
}

private extension GrizzyClawInternalToolStubs {
    static func createScheduledTask(arguments: [String: Any], scheduledTasksURL: URL) -> String {
        let name = stringArg("name", in: arguments)
        let cron = stringArg("cron", in: arguments)
        let message = stringArg("message", in: arguments)

        guard !name.isEmpty else {
            return "**❌ Missing required argument `name`.**"
        }
        guard !cron.isEmpty else {
            return "**❌ Missing required argument `cron`.**"
        }
        guard !message.isEmpty else {
            return "**❌ Missing required argument `message`.**"
        }

        do {
            let postAction = try mcpPostAction(from: arguments["mcp_post_action"])
            let record = try ScheduledTasksPersistence.createTask(
                name: name,
                cron: cron,
                message: message,
                mcpPostAction: postAction,
                to: scheduledTasksURL
            )
            return """
            ✅ Scheduled task created.
            - id: \(record.taskId)
            - name: \(record.name)
            - cron: \(record.cron)
            - storage: \(scheduledTasksURL.path)
            """
        } catch {
            return "**❌ Failed to create scheduled task:** \(error.localizedDescription)"
        }
    }

    static func listScheduledTasks(from url: URL) -> String {
        do {
            let tasks = try ScheduledTasksPersistence.load(from: url)
            guard !tasks.isEmpty else {
                return "No scheduled tasks found in \(url.path)."
            }
            let lines = tasks.map { task in
                "- `\(task.taskId)` — \(task.name) (`\(task.cron)`)"
            }
            return """
            Scheduled tasks in \(url.path):
            \(lines.joined(separator: "\n"))
            """
        } catch {
            return "**❌ Failed to load scheduled tasks:** \(error.localizedDescription)"
        }
    }

    static func stringArg(_ key: String, in arguments: [String: Any]) -> String {
        ((arguments[key] as? String) ?? String(describing: arguments[key] ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func mcpPostAction(from raw: Any?) throws -> MCPPostActionRecord? {
        guard let raw else { return nil }
        let json = try JSONValue.decode(fromJSONObject: raw)
        guard case .object(let dict) = json else {
            throw NSError(
                domain: "GrizzyClawInternalToolStubs",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "`mcp_post_action` must be a JSON object."]
            )
        }
        let root = JSONValue.object(dict)
        let mcp = root.string(forKey: "mcp")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tool = root.string(forKey: "tool")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !mcp.isEmpty, !tool.isEmpty else {
            throw NSError(
                domain: "GrizzyClawInternalToolStubs",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "`mcp_post_action` requires non-empty `mcp` and `tool` values."]
            )
        }

        let args: [String: JSONValue]?
        if case .object(let object)? = dict["arguments"] {
            args = object
        } else {
            args = nil
        }
        return MCPPostActionRecord(mcp: mcp, tool: tool, arguments: args)
    }
}
