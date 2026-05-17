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
            return ToolEnvelope.success(
                tool: "grizzyclaw.get_status",
                text: """
                GrizzyClaw native chat status:
                - Active workspace id: \(workspaceId ?? "(none)")
                - MCP servers file: \(config.mcpServersFile)
                """
            )
        case "create_scheduled_task":
            return createScheduledTask(arguments: arguments, scheduledTasksURL: scheduledTasksURL)
        case "list_scheduled_tasks":
            return listScheduledTasks(from: scheduledTasksURL)
        case "run_scheduled_task":
            let tid = (arguments["task_id"] as? String) ?? String(describing: arguments["task_id"] ?? "")
            return ToolEnvelope.failure(
                tool: "grizzyclaw.run_scheduled_task",
                kind: "unsupported",
                message: "Immediate runs are not supported in the iPad-native tool stubs yet (task_id=\(tid))."
            )
        case "search_transcripts":
            return searchTranscripts(arguments: arguments)
        case "list_installed_skills":
            return listInstalledSkills()
        case "capabilities_search":
            return capabilitiesSearch(arguments: arguments)
        case "capabilities_load":
            return capabilitiesLoad(arguments: arguments)
        default:
            if let osaurus = OsaurusParityToolHandlers.handle(
                tool: tool,
                arguments: arguments,
                workspaceId: workspaceId
            ) {
                return osaurus
            }
            return ToolEnvelope.failure(
                tool: "grizzyclaw.\(tool)",
                kind: "unknown_tool",
                message: "Unknown grizzyclaw tool `\(tool)`."
            )
        }
    }
}

private extension GrizzyClawInternalToolStubs {
    static func createScheduledTask(arguments: [String: Any], scheduledTasksURL: URL) -> String {
        let name = stringArg("name", in: arguments)
        let cron = stringArg("cron", in: arguments)
        let message = stringArg("message", in: arguments)

        guard !name.isEmpty else {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.create_scheduled_task",
                kind: "invalid_args",
                message: "Missing required argument `name`.",
                field: "name"
            )
        }
        guard !cron.isEmpty else {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.create_scheduled_task",
                kind: "invalid_args",
                message: "Missing required argument `cron`.",
                field: "cron"
            )
        }
        guard !message.isEmpty else {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.create_scheduled_task",
                kind: "invalid_args",
                message: "Missing required argument `message`.",
                field: "message"
            )
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
            return ToolEnvelope.success(
                tool: "grizzyclaw.create_scheduled_task",
                result: [
                    "task_id": record.taskId,
                    "name": record.name,
                    "cron": record.cron,
                    "storage_path": scheduledTasksURL.path,
                ]
            )
        } catch {
            return ToolEnvelope.fromError(error, tool: "grizzyclaw.create_scheduled_task")
        }
    }

    static func listScheduledTasks(from url: URL) -> String {
        do {
            let tasks = try ScheduledTasksPersistence.load(from: url)
            guard !tasks.isEmpty else {
                return ToolEnvelope.success(
                    tool: "grizzyclaw.list_scheduled_tasks",
                    result: [
                        "tasks": [],
                        "storage_path": url.path,
                    ]
                )
            }
            let rows: [[String: Any]] = tasks.map { t in
                [
                    "task_id": t.taskId,
                    "name": t.name,
                    "cron": t.cron,
                    "message": t.message,
                ]
            }
            return ToolEnvelope.success(
                tool: "grizzyclaw.list_scheduled_tasks",
                result: [
                    "tasks": rows,
                    "storage_path": url.path,
                ]
            )
        } catch {
            return ToolEnvelope.fromError(error, tool: "grizzyclaw.list_scheduled_tasks")
        }
    }

    static func searchTranscripts(arguments: [String: Any]) -> String {
        let query = stringArg("query", in: arguments)
        guard !query.isEmpty else {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.search_transcripts",
                kind: "invalid_args",
                message: "Missing required argument `query`.",
                field: "query"
            )
        }

        let topKRaw = intArg("top_k", in: arguments)
        let topK = max(1, min(50, topKRaw ?? 10))

        do {
            try GrizzyClawPaths.ensureSessionsDirectoryExists()
            let root = GrizzyClawPaths.sessionsDirectory
            let fm = FileManager.default
            let urls = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])) ?? []
            let lowerNeedle = query.lowercased()

            var matches: [[String: Any]] = []
            for u in urls where u.pathExtension.lowercased() == "json" {
                guard matches.count < topK else { break }
                guard let data = try? Data(contentsOf: u) else { continue }
                guard let obj = try? JSONSerialization.jsonObject(with: data) else { continue }
                guard let arr = obj as? [[String: Any]] else { continue }

                for (idx, row) in arr.enumerated() {
                    guard matches.count < topK else { break }
                    let role = (row["role"] as? String) ?? "user"
                    let content = (row["content"] as? String) ?? ""
                    if content.lowercased().contains(lowerNeedle) {
                        let preview = content
                            .replacingOccurrences(of: "\n", with: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        matches.append([
                            "file": u.lastPathComponent,
                            "role": role,
                            "turn_index": idx,
                            "preview": String(preview.prefix(240)),
                        ])
                    }
                }
            }

            return ToolEnvelope.success(
                tool: "grizzyclaw.search_transcripts",
                result: [
                    "query": query,
                    "top_k": topK,
                    "matches": matches,
                    "sessions_dir": GrizzyClawPaths.sessionsDirectory.path,
                ]
            )
        } catch {
            return ToolEnvelope.fromError(error, tool: "grizzyclaw.search_transcripts")
        }
    }

    static func listInstalledSkills() -> String {
        do {
            let skills = try InstalledSkillStore.listInstalledSkills()
            let rows: [[String: Any]] = skills.map { s in
                [
                    "id": s.id,
                    "title": s.title,
                    "description": s.description,
                ]
            }
            return ToolEnvelope.success(
                tool: "grizzyclaw.list_installed_skills",
                result: [
                    "skills": rows,
                    "count": rows.count,
                ]
            )
        } catch {
            return ToolEnvelope.fromError(error, tool: "grizzyclaw.list_installed_skills")
        }
    }

    static func capabilitiesSearch(arguments: [String: Any]) -> String {
        let queries = stringArrayArg("queries", in: arguments)
        guard !queries.isEmpty else {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.capabilities_search",
                kind: "invalid_args",
                message: "Missing required argument `queries` (array of strings).",
                field: "queries"
            )
        }

        do {
            let skills = try InstalledSkillStore.listInstalledSkills()
            let needles = queries
                .flatMap { $0.components(separatedBy: .whitespacesAndNewlines) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }

            func scoreText(_ hay: String) -> Int {
                let h = hay.lowercased()
                return needles.reduce(0) { $0 + (h.contains($1) ? 1 : 0) }
            }

            let osaurusIDs = Set(BuiltinOsaurusSkills.all.map { $0.skillID.lowercased() })
            let cliCatalogIDs = Set(CLIAnythingBundledCatalog.loadEntries().map { $0.catalogID.lowercased() })

            var rows: [[String: Any]] = []

            for s in skills where scoreText("\(s.id)\n\(s.title)\n\(s.description)") > 0 {
                if osaurusIDs.contains(s.id.lowercased()) || cliCatalogIDs.contains(s.id.lowercased()) { continue }
                rows.append([
                    "id": "skill/\(s.id)",
                    "kind": "skill",
                    "score": scoreText("\(s.id)\n\(s.title)\n\(s.description)"),
                    "title": s.title,
                    "description": s.description,
                ])
            }

            for def in BuiltinOsaurusSkills.all {
                let sc = scoreText("\(def.skillID)\n\(def.name)\n\(def.description)")
                guard sc > 0 else { continue }
                rows.append([
                    "id": "skill/\(def.skillID)",
                    "kind": "osaurus_skill",
                    "score": sc,
                    "title": "\(def.icon) \(def.name)",
                    "description": def.description,
                ])
            }

            for entry in CLIAnythingBundledCatalog.loadEntries() {
                let sc = scoreText("\(entry.catalogID)\n\(entry.folder)\n\(entry.title)")
                guard sc > 0 else { continue }
                rows.append([
                    "id": "skill/\(entry.catalogID)",
                    "kind": "cli_anything_skill",
                    "score": sc,
                    "title": entry.title,
                    "description": "Bundled CLI-Anything harness skill (`\(entry.folder)`).",
                ])
            }

            rows.sort { a, b in
                let sa = a["score"] as? Int ?? 0
                let sb = b["score"] as? Int ?? 0
                if sa != sb { return sa > sb }
                let ida = (a["id"] as? String) ?? ""
                let idb = (b["id"] as? String) ?? ""
                return ida < idb
            }

            let out = Array(rows.prefix(40))

            return ToolEnvelope.success(
                tool: "grizzyclaw.capabilities_search",
                result: [
                    "queries": queries,
                    "results": out,
                ]
            )
        } catch {
            return ToolEnvelope.fromError(error, tool: "grizzyclaw.capabilities_search")
        }
    }

    static func capabilitiesLoad(arguments: [String: Any]) -> String {
        let ids = stringArrayArg("ids", in: arguments)
        guard !ids.isEmpty else {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.capabilities_load",
                kind: "invalid_args",
                message: "Missing required argument `ids` (array of strings).",
                field: "ids"
            )
        }

        // Note: actual "loading" is handled by the caller via enabled_skills / prompt augmentation.
        // This tool simply validates IDs and returns guidance.
        let loadedSkills: [String] = ids.map { raw in
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.lowercased().hasPrefix("skill/") {
                return String(t.dropFirst("skill/".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return t
        }.filter { !$0.isEmpty }

        if loadedSkills.isEmpty {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.capabilities_load",
                kind: "unsupported",
                message: "Provide one or more skill ids (optionally prefixed with `skill/`)."
            )
        }

        return ToolEnvelope.success(
            tool: "grizzyclaw.capabilities_load",
            result: [
                "loaded_skill_ids": loadedSkills,
                "note": "To apply these, add them to workspace.enabled_skills (Workspaces → Skills tab). For CLI-Anything packs, use “Bundled CLI-Anything…” import if the skill is not installed yet.",
            ]
        )
    }

    static func stringArg(_ key: String, in arguments: [String: Any]) -> String {
        ((arguments[key] as? String) ?? String(describing: arguments[key] ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func intArg(_ key: String, in arguments: [String: Any]) -> Int? {
        if let i = arguments[key] as? Int { return i }
        if let d = arguments[key] as? Double { return Int(d) }
        if let s = arguments[key] as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    static func stringArrayArg(_ key: String, in arguments: [String: Any]) -> [String] {
        if let arr = arguments[key] as? [String] {
            return arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let arr = arguments[key] as? [Any] {
            return arr.compactMap { $0 as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if let s = arguments[key] as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? [] : [t]
        }
        return []
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
