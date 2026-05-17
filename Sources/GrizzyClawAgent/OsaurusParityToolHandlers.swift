import Foundation
import GrizzyClawCore

/// Handlers for Osaurus `ToolRegistry` tools surfaced as `grizzyclaw.*`.
public enum OsaurusParityToolHandlers {
    public static func handle(
        tool: String,
        arguments: [String: Any],
        workspaceId: String?
    ) -> String? {
        switch tool {
        case "todo": return todo(arguments: arguments, workspaceId: workspaceId)
        case "complete": return complete(arguments: arguments, workspaceId: workspaceId)
        case "clarify": return clarify(arguments: arguments)
        case "share_artifact": return shareArtifact(arguments: arguments)
        case "render_chart": return renderChart(arguments: arguments)
        case "methods_save": return methodsSave(arguments: arguments)
        case "methods_report": return methodsReport(arguments: arguments)
        case "memory_search_working": return memorySearchWorking(arguments: arguments)
        case "memory_search_conversations": return memorySearchConversations(arguments: arguments)
        case "memory_search_summaries": return memorySearchSummaries(arguments: arguments)
        case "memory_search_graph": return memorySearchGraph(arguments: arguments)
        case "spawn_subagent": return spawnSubagent(arguments: arguments)
        default: return nil
        }
    }

    // MARK: - Tier 1

    private static func todo(arguments: [String: Any], workspaceId: String?) -> String {
        let md = stringArg("markdown", in: arguments)
        guard !md.isEmpty else {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.todo",
                kind: "invalid_args",
                message: "Missing required argument `markdown`.",
                field: "markdown"
            )
        }
        do {
            try GrizzyClawPaths.ensureOsaurusParityDirectoryExists()
            let url = todosURL(workspaceId: workspaceId)
            let payload: [String: Any] = ["markdown": md, "updated_at": ISO8601DateFormatter().string(from: Date())]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try data.write(to: url, options: .atomic)
            return ToolEnvelope.success(
                tool: "grizzyclaw.todo",
                result: [
                    "saved": true,
                    "storage_path": url.path,
                    "preview": String(md.replacingOccurrences(of: "\n", with: " ").prefix(200)),
                ]
            )
        } catch {
            return ToolEnvelope.fromError(error, tool: "grizzyclaw.todo")
        }
    }

    private static func complete(arguments: [String: Any], workspaceId: String?) -> String {
        let summary = stringArg("summary", in: arguments)
        guard !summary.isEmpty else {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.complete",
                kind: "invalid_args",
                message: "Missing required argument `summary`.",
                field: "summary"
            )
        }
        if let rejection = OsaurusCompleteSummaryValidator.validationMessage(for: summary) {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.complete",
                kind: "invalid_args",
                message: rejection,
                field: "summary",
                expected: "≥30 chars of meaningful prose; not a placeholder",
                retryable: false
            )
        }
        do {
            try GrizzyClawPaths.ensureOsaurusParityDirectoryExists()
            let todos = todosURL(workspaceId: workspaceId)
            if FileManager.default.fileExists(atPath: todos.path) {
                try? FileManager.default.removeItem(at: todos)
            }
            let doneURL = GrizzyClawPaths.osaurusParityDirectory.appendingPathComponent(
                "last_complete_\(workspaceStorageKey(workspaceId)).json",
                isDirectory: false
            )
            let payload: [String: Any] = ["summary": summary, "completed_at": ISO8601DateFormatter().string(from: Date())]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try data.write(to: doneURL, options: .atomic)
            return ToolEnvelope.success(
                tool: "grizzyclaw.complete",
                result: [
                    "cleared_todos": true,
                    "summary": summary,
                    "storage_path": doneURL.path,
                ]
            )
        } catch {
            return ToolEnvelope.fromError(error, tool: "grizzyclaw.complete")
        }
    }

    private static func clarify(arguments: [String: Any]) -> String {
        let q = stringArg("question", in: arguments)
        guard !q.isEmpty else {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.clarify",
                kind: "invalid_args",
                message: "Missing required argument `question`.",
                field: "question"
            )
        }
        if let raw = arguments["options"], !(raw is NSNull) {
            guard let arr = OsaurusArgumentCoercion.stringArray(raw) else {
                return ToolEnvelope.failure(
                    tool: "grizzyclaw.clarify",
                    kind: "invalid_args",
                    message:
                        "`options` must be an array of strings, got \(String(describing: type(of: raw))). "
                        + "Pass e.g. [\"Yes\", \"No\"].",
                    field: "options",
                    expected: "array of short string choices",
                    retryable: false
                )
            }
            let cleaned = OsaurusClarifyOptionsRules.normalizeOptions(arr)
            if cleaned.count > OsaurusClarifyOptionsRules.maxOptions {
                return ToolEnvelope.failure(
                    tool: "grizzyclaw.clarify",
                    kind: "invalid_args",
                    message:
                        "`options` is capped at \(OsaurusClarifyOptionsRules.maxOptions) entries (got \(cleaned.count)). "
                        + "Drop low-value choices or break the question into a follow-up.",
                    field: "options",
                    expected: "≤\(OsaurusClarifyOptionsRules.maxOptions) short string choices",
                    retryable: false
                )
            }
            for opt in cleaned where opt.count > OsaurusClarifyOptionsRules.maxOptionLength {
                return ToolEnvelope.failure(
                    tool: "grizzyclaw.clarify",
                    kind: "invalid_args",
                    message:
                        "Option `\(String(opt.prefix(40)))…` is \(opt.count) chars (>\(OsaurusClarifyOptionsRules.maxOptionLength)). "
                        + "Use short labels — put longer detail in `question`.",
                    field: "options",
                    expected: "each option ≤\(OsaurusClarifyOptionsRules.maxOptionLength) chars",
                    retryable: false
                )
            }
        }
        let options: [String] = {
            guard let raw = arguments["options"], !(raw is NSNull),
                let arr = OsaurusArgumentCoercion.stringArray(raw)
            else { return [] }
            return Array(OsaurusClarifyOptionsRules.normalizeOptions(arr).prefix(OsaurusClarifyOptionsRules.maxOptions))
        }()
        let allowMultiple = options.isEmpty ? false : (OsaurusArgumentCoercion.bool(arguments["allowMultiple"]) ?? false)
        var lines = ["Clarification needed:", q]
        if !options.isEmpty {
            lines.append("Options: " + options.joined(separator: " | "))
            if allowMultiple {
                lines.append("(User may select multiple.)")
            }
        }
        return ToolEnvelope.success(
            tool: "grizzyclaw.clarify",
            text: lines.joined(separator: "\n")
        )
    }

    // MARK: - Tier 4–5 stubs

    private static func shareArtifact(arguments: [String: Any]) -> String {
        let path = stringArg("path", in: arguments)
        let content = stringArg("content", in: arguments)
        let filename = stringArg("filename", in: arguments)
        let description = stringArg("description", in: arguments)
        if path.isEmpty && content.isEmpty && filename.isEmpty {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.share_artifact",
                kind: "invalid_args",
                message: "Provide at least one of `path`, `content`, or `filename`.",
                field: "path"
            )
        }
        return ToolEnvelope.success(
            tool: "grizzyclaw.share_artifact",
            result: [
                "echo": [
                    "path": path,
                    "filename": filename,
                    "description": description,
                    "content_preview": String(content.prefix(800)),
                ],
                "note":
                    "GrizzyClaw-Air does not yet render artifact cards in chat; content is returned for the transcript only.",
            ]
        )
    }

    private static func renderChart(arguments: [String: Any]) -> String {
        OsaurusRenderChartParity.execute(tool: "grizzyclaw.render_chart", arguments: arguments)
    }

    private static func spawnSubagent(arguments: [String: Any]) -> String {
        let prompt = stringArg("prompt", in: arguments)
        guard !prompt.isEmpty else {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.spawn_subagent",
                kind: "invalid_args",
                message: "Missing required argument `prompt`.",
                field: "prompt"
            )
        }
        return ToolEnvelope.failure(
            tool: "grizzyclaw.spawn_subagent",
            kind: "not_supported",
            message: "Swarm / sub-agent execution from chat is not implemented in GrizzyClaw-Air.",
            retryable: false
        )
    }

    // MARK: - Tier 2 methods

    private static func methodsSave(arguments: [String: Any]) -> String {
        let name = stringArg("name", in: arguments)
        let description = stringArg("description", in: arguments)
        let body = stringArg("body", in: arguments)
        let trigger = stringArg("trigger_text", in: arguments)
        guard !name.isEmpty && !description.isEmpty && !body.isEmpty else {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.methods_save",
                kind: "invalid_args",
                message: "Requires non-empty `name`, `description`, and `body`.",
                field: "name"
            )
        }
        do {
            try GrizzyClawPaths.ensureOsaurusParityDirectoryExists()
            let url = GrizzyClawPaths.osaurusParityDirectory.appendingPathComponent("methods.json", isDirectory: false)
            var methods = loadMethodsArray(from: url)
            let id = UUID().uuidString.lowercased()
            methods.append([
                "id": id,
                "name": name,
                "description": description,
                "trigger_text": trigger,
                "body": body,
                "outcomes": ["loaded": 0, "succeeded": 0, "failed": 0],
            ])
            let root: [String: Any] = ["methods": methods]
            let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
            try data.write(to: url, options: .atomic)
            return ToolEnvelope.success(
                tool: "grizzyclaw.methods_save",
                result: ["method_id": id, "storage_path": url.path]
            )
        } catch {
            return ToolEnvelope.fromError(error, tool: "grizzyclaw.methods_save")
        }
    }

    private static func methodsReport(arguments: [String: Any]) -> String {
        let methodId = stringArg("method_id", in: arguments)
        let outcome = stringArg("outcome", in: arguments).lowercased()
        guard !methodId.isEmpty else {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.methods_report",
                kind: "invalid_args",
                message: "Missing `method_id`.",
                field: "method_id"
            )
        }
        guard ["loaded", "succeeded", "failed"].contains(outcome) else {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.methods_report",
                kind: "invalid_args",
                message: "`outcome` must be loaded, succeeded, or failed.",
                field: "outcome"
            )
        }
        do {
            try GrizzyClawPaths.ensureOsaurusParityDirectoryExists()
            let url = GrizzyClawPaths.osaurusParityDirectory.appendingPathComponent("methods.json", isDirectory: false)
            var methods = loadMethodsArray(from: url)
            guard let idx = methods.firstIndex(where: { ($0["id"] as? String)?.lowercased() == methodId.lowercased() }) else {
                return ToolEnvelope.failure(
                    tool: "grizzyclaw.methods_report",
                    kind: "not_found",
                    message: "No method with id `\(methodId)`.",
                    field: "method_id"
                )
            }
            var row = methods[idx]
            var oc = (row["outcomes"] as? [String: Any]) ?? [:]
            let prev = (oc[outcome] as? Int) ?? 0
            oc[outcome] = prev + 1
            if let notes = arguments["notes"] as? String, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                row["last_notes"] = notes
            }
            row["outcomes"] = oc
            methods[idx] = row
            let root: [String: Any] = ["methods": methods]
            let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
            try data.write(to: url, options: .atomic)
            return ToolEnvelope.success(
                tool: "grizzyclaw.methods_report",
                result: ["method_id": methodId, "outcome": outcome, "outcomes": oc]
            )
        } catch {
            return ToolEnvelope.fromError(error, tool: "grizzyclaw.methods_report")
        }
    }

    private static func loadMethodsArray(from url: URL) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["methods"] as? [[String: Any]]
        else {
            return []
        }
        return arr
    }

    // MARK: - Tier 3 memory

    private static func memorySearchWorking(arguments: [String: Any]) -> String {
        let query = stringArg("query", in: arguments)
        guard !query.isEmpty else {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.memory_search_working",
                kind: "invalid_args",
                message: "Missing `query`.",
                field: "query"
            )
        }
        let topK = max(1, min(50, intArg("top_k", in: arguments) ?? 10))
        let url = GrizzyClawPaths.osaurusParityDirectory.appendingPathComponent("working_memory.json", isDirectory: false)
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [[String: Any]]
        else {
            return ToolEnvelope.success(
                tool: "grizzyclaw.memory_search_working",
                result: [
                    "query": query,
                    "top_k": topK,
                    "matches": [],
                    "note": "No working_memory.json yet. Create ~/.grizzyclaw/osaurus_parity/working_memory.json with {\"items\":[{\"content\":\"...\"}]} to populate.",
                ]
            )
        }
        let needle = query.lowercased()
        var matches: [[String: Any]] = []
        for item in items {
            guard matches.count < topK else { break }
            let c = (item["content"] as? String) ?? ""
            if c.lowercased().contains(needle) {
                matches.append([
                    "preview": String(c.replacingOccurrences(of: "\n", with: " ").prefix(240)),
                ])
            }
        }
        return ToolEnvelope.success(
            tool: "grizzyclaw.memory_search_working",
            result: ["query": query, "top_k": topK, "matches": matches]
        )
    }

    private static func memorySearchConversations(arguments: [String: Any]) -> String {
        transcriptSearch(arguments: arguments, toolName: "memory_search_conversations", roleFilter: nil)
    }

    private static func memorySearchSummaries(arguments: [String: Any]) -> String {
        transcriptSearch(arguments: arguments, toolName: "memory_search_summaries", roleFilter: "assistant")
    }

    private static func transcriptSearch(arguments: [String: Any], toolName: String, roleFilter: String?) -> String {
        let query = stringArg("query", in: arguments)
        guard !query.isEmpty else {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.\(toolName)",
                kind: "invalid_args",
                message: "Missing required argument `query`.",
                field: "query"
            )
        }
        let topK = max(1, min(50, intArg("top_k", in: arguments) ?? 10))
        do {
            try GrizzyClawPaths.ensureSessionsDirectoryExists()
            let root = GrizzyClawPaths.sessionsDirectory
            let fm = FileManager.default
            let urls =
                (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]))
                ?? []
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
                    if let roleFilter {
                        guard role.lowercased() == roleFilter.lowercased() else { continue }
                    }
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
                tool: "grizzyclaw.\(toolName)",
                result: [
                    "query": query,
                    "top_k": topK,
                    "matches": matches,
                    "sessions_dir": root.path,
                ]
            )
        } catch {
            return ToolEnvelope.fromError(error, tool: "grizzyclaw.\(toolName)")
        }
    }

    private static func memorySearchGraph(arguments: [String: Any]) -> String {
        let query = stringArg("query", in: arguments)
        guard !query.isEmpty else {
            return ToolEnvelope.failure(
                tool: "grizzyclaw.memory_search_graph",
                kind: "invalid_args",
                message: "Missing `query`.",
                field: "query"
            )
        }
        return ToolEnvelope.success(
            tool: "grizzyclaw.memory_search_graph",
            result: [
                "query": query,
                "nodes": [],
                "edges": [],
                "note": "Graph memory is not implemented; stub returns an empty graph.",
            ]
        )
    }

    // MARK: - Paths

    private static func workspaceStorageKey(_ workspaceId: String?) -> String {
        let s = (workspaceId ?? "default").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "default" }
        return s.replacingOccurrences(of: "/", with: "_")
    }

    private static func todosURL(workspaceId: String?) -> URL {
        GrizzyClawPaths.osaurusParityDirectory.appendingPathComponent(
            "todos_\(workspaceStorageKey(workspaceId)).json",
            isDirectory: false
        )
    }

    // MARK: - Arg helpers

    private static func stringArg(_ key: String, in arguments: [String: Any]) -> String {
        ((arguments[key] as? String) ?? String(describing: arguments[key] ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func intArg(_ key: String, in arguments: [String: Any]) -> Int? {
        if let i = arguments[key] as? Int { return i }
        if let d = arguments[key] as? Double { return Int(d) }
        if let s = arguments[key] as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
}
