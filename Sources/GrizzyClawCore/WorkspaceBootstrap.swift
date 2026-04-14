import Foundation

/// First-run and repair paths aligned with Python `WorkspaceManager._create_default_workspace` and
/// `WORKSPACE_TEMPLATES["default"]` in `grizzyclaw/workspaces/workspace.py`.
public enum WorkspaceBootstrap {
    /// Matches Python `WORKSPACE_TEMPLATES["default"].config` overrides (plus explicit LLM defaults for a stable JSON blob).
    public static func defaultTemplateConfig() -> JSONValue {
        .object([
            "llm_provider": .string("ollama"),
            "llm_model": .string("llama3.2"),
            "temperature": .double(0.7),
            "max_tokens": .int(131_072),
            "ollama_url": .string("http://localhost:11434"),
            "lmstudio_url": .string("http://localhost:1234/v1"),
            "system_prompt": .string(defaultSystemPrompt),
            "memory_enabled": .bool(true),
            "max_context_length": .int(4000),
            "max_session_messages": .int(20),
            "safety_content_filter": .bool(true),
            "safety_pii_redact_logs": .bool(true),
            "enable_inter_agent": .bool(true),
            "use_shared_memory": .bool(true),
            "swarm_role": .string("leader"),
            "swarm_auto_delegate": .bool(true),
            "swarm_consensus": .bool(true),
            "proactive_habits": .bool(true),
            "enable_folder_watchers": .bool(true),
            "webchat_enabled": .bool(true),
            "chat_mode": .string("chat"),
        ])
    }

    /// Python `WORKSPACE_TEMPLATES["default"]` → `WorkspaceRecord` with `id == "default"` and `is_default == true`.
    public static func makePythonDefaultWorkspaceRecord() -> WorkspaceRecord {
        WorkspaceRecord.makeNew(
            id: "default",
            name: "Default",
            description: "General-purpose assistant",
            icon: "🤖",
            color: "#007AFF",
            order: 0,
            config: defaultTemplateConfig(),
            isDefault: true
        )
    }

    public static func pythonDefaultWorkspacesFile() -> WorkspacesFile {
        WorkspacesFile(
            activeWorkspaceId: "default",
            baselineWorkspaceId: "default",
            workspaces: [makePythonDefaultWorkspaceRecord()]
        )
    }

    public static func writePythonDefaultWorkspacesFile(to url: URL) throws {
        try WorkspaceIndexLoader.save(pythonDefaultWorkspacesFile(), to: url)
    }

    /// Mirrors Python `_normalize_baseline_id` plus fixing invalid `active_workspace_id` like `_load_workspaces`.
    public static func normalizePointers(_ file: WorkspacesFile) -> (file: WorkspacesFile, changed: Bool) {
        var f = file
        var changed = false
        let ids = Set(f.workspaces.map(\.id))
        guard !ids.isEmpty else {
            return (f, changed)
        }

        if f.activeWorkspaceId == nil || (f.activeWorkspaceId.map { !ids.contains($0) } ?? true) {
            f.activeWorkspaceId = pickPrimaryWorkspaceId(f.workspaces)
            changed = true
        }

        let bid = f.baselineWorkspaceId
        if let b = bid, ids.contains(b) {
            return (f, changed)
        }
        if let w = f.workspaces.first(where: { $0.isDefault == true }), ids.contains(w.id) {
            f.baselineWorkspaceId = w.id
            changed = true
            return (f, changed)
        }
        if ids.contains("default") {
            f.baselineWorkspaceId = "default"
            changed = true
            return (f, changed)
        }
        if let aid = f.activeWorkspaceId, ids.contains(aid) {
            f.baselineWorkspaceId = aid
            changed = true
            return (f, changed)
        }
        f.baselineWorkspaceId = pickPrimaryWorkspaceId(f.workspaces)
        changed = true
        return (f, changed)
    }

    private static func pickPrimaryWorkspaceId(_ workspaces: [WorkspaceRecord]) -> String? {
        guard !workspaces.isEmpty else { return nil }
        let sorted = workspaces.sorted { a, b in
            let oa = a.order ?? 0
            let ob = b.order ?? 0
            if oa != ob { return oa < ob }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return sorted.first?.id
    }

    /// Same string as Python `WORKSPACE_TEMPLATES["default"].config.system_prompt`.
    private static let defaultSystemPrompt =
        "You are GrizzyClaw, a helpful AI assistant with memory. You can remember previous conversations and use that context to help the user.\n\n## SWARM LEADER\nBreak complex tasks into subtasks. Delegate by writing lines like:\n@research Research X.\n@coding Code Y.\n@personal Plan Z.\nUse workspace slugs: @research, @coding, @personal, @writing, @planning, or @code_assistant etc. Your delegations are executed automatically; specialist replies are then synthesized into one answer when consensus is on. Use shared memory to recall context."
}
