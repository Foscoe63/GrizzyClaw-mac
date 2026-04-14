import Combine
import GrizzyClawCore
import SwiftUI

/// Loads and mutates `workspaces.json` (Python `WorkspaceManager` format).
@MainActor
public final class WorkspaceStore: ObservableObject {
    @Published public private(set) var index: WorkspaceIndex?
    @Published public private(set) var loadError: String?
    @Published public private(set) var saveError: String?
    /// True while `reload()` is running (brief); used for ProgressView in tab UIs.
    @Published public private(set) var isReloading = false
    /// User templates from `~/.grizzyclaw/workspace_templates.json` (Python parity). Empty if missing or invalid.
    @Published public private(set) var userWorkspaceTemplates: [WorkspaceUserTemplate] = []

    public init() {}

    public func reload() {
        isReloading = true
        defer { isReloading = false }
        saveError = nil
        loadUserTemplates()
        let url = GrizzyClawPaths.workspacesJSON

        do {
            try GrizzyClawPaths.ensureUserDataDirectoryExists()
        } catch {
            loadError = error.localizedDescription
            index = nil
            GrizzyClawLog.error("workspaces: ensure data dir failed: \(error.localizedDescription)")
            return
        }

        func persistNormalized(_ file: WorkspacesFile) throws {
            let n = WorkspaceBootstrap.normalizePointers(file)
            if n.changed {
                try WorkspaceIndexLoader.save(n.file, to: url)
            }
        }

        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try WorkspaceBootstrap.writePythonDefaultWorkspacesFile(to: url)
            }

            var file = try WorkspaceIndexLoader.loadFile(from: url)
            if file.workspaces.isEmpty {
                file = WorkspaceBootstrap.pythonDefaultWorkspacesFile()
                try WorkspaceIndexLoader.save(file, to: url)
            }
            try persistNormalized(file)
            index = try WorkspaceIndexLoader.load(from: url)
            loadError = nil
        } catch {
            GrizzyClawLog.error("workspaces load failed, replacing with default: \(error.localizedDescription)")
            do {
                try WorkspaceBootstrap.writePythonDefaultWorkspacesFile(to: url)
                let recovered = try WorkspaceIndexLoader.loadFile(from: url)
                try persistNormalized(recovered)
                index = try WorkspaceIndexLoader.load(from: url)
                loadError = nil
            } catch {
                loadError = error.localizedDescription
                index = nil
                GrizzyClawLog.error("workspaces reload failed: \(error.localizedDescription)")
            }
        }
    }

    private func loadUserTemplates() {
        let url = GrizzyClawPaths.workspaceTemplatesJSON
        do {
            userWorkspaceTemplates = try WorkspaceTemplatesLoader.load(from: url)
        } catch {
            userWorkspaceTemplates = []
        }
    }

    /// Python `WorkspaceManager.record_feedback` — thumbs up/down tallies on the active workspace.
    public func recordFeedback(workspaceId: String, up: Bool) throws {
        let url = GrizzyClawPaths.workspacesJSON
        var file = try WorkspaceIndexLoader.loadFile(from: url)
        guard let i = file.workspaces.firstIndex(where: { $0.id == workspaceId }) else {
            throw WorkspaceMutationError.workspaceNotFound(workspaceId)
        }
        file.workspaces[i] = file.workspaces[i].recordingFeedback(up: up)
        try WorkspaceIndexLoader.save(file, to: url)
        saveError = nil
        reload()
    }

    /// Persists the active workspace id (Python `WorkspaceManager.set_active_workspace`).
    public func persistActiveWorkspace(id: String) {
        let url = GrizzyClawPaths.workspacesJSON
        do {
            try WorkspaceActivePersistence.setActiveWorkspaceId(id, fileURL: url)
            saveError = nil
            reload()
        } catch {
            saveError = error.localizedDescription
            GrizzyClawLog.error("persist active workspace failed: \(error.localizedDescription)")
        }
    }

    /// Python `WorkspaceManager.import_workspace_from_link` — appends a workspace and sets it active.
    @discardableResult
    public func importWorkspaceFromLink(_ link: String) throws -> String {
        let payload = try WorkspaceShareLink.decodeImportPayload(link)
        try GrizzyClawPaths.ensureUserDataDirectoryExists()
        let url = GrizzyClawPaths.workspacesJSON
        if !FileManager.default.fileExists(atPath: url.path) {
            try WorkspaceBootstrap.writePythonDefaultWorkspacesFile(to: url)
        }
        var file = try WorkspaceIndexLoader.loadFile(from: url)
        let newId = String(UUID().uuidString.prefix(8)).lowercased()
        let order = file.workspaces.count
        let ws = try WorkspaceRecord.fromImportPayload(payload, newId: newId, order: order)
        file.workspaces.append(ws)
        file.activeWorkspaceId = newId
        try WorkspaceIndexLoader.save(file, to: url)
        saveError = nil
        reload()
        return newId
    }

    /// Python `WorkspaceManager.add_user_template` — writes `~/.grizzyclaw/workspace_templates.json`.
    public func saveUserTemplate(key: String, fromWorkspaceId: String) throws {
        guard let ws = index?.workspaces.first(where: { $0.id == fromWorkspaceId }) else {
            throw WorkspaceMutationError.workspaceNotFound(fromWorkspaceId)
        }
        try WorkspaceTemplatesLoader.saveUserTemplate(
            key: key,
            workspace: ws,
            to: GrizzyClawPaths.workspaceTemplatesJSON
        )
        saveError = nil
        reload()
    }

    /// Built-in + user templates merged like Python `WorkspaceManager.get_all_templates` (user overrides the same key).
    public func mergedTemplateRowsForNewWorkspace() -> [WorkspaceTemplatePickerRow] {
        let builtins = BuiltInWorkspaceTemplates.orderedMetadata
        var userByKey: [String: WorkspaceUserTemplate] = [:]
        for u in userWorkspaceTemplates {
            userByKey[u.templateKey] = u
        }
        var rows: [WorkspaceTemplatePickerRow] = []
        for b in builtins {
            if let u = userByKey[b.key] {
                rows.append(
                    WorkspaceTemplatePickerRow(
                        templateKey: u.templateKey,
                        title: u.displayName,
                        subtitle: u.description,
                        icon: u.icon,
                        color: u.color
                    )
                )
            } else {
                rows.append(
                    WorkspaceTemplatePickerRow(
                        templateKey: b.key,
                        title: b.name,
                        subtitle: b.description,
                        icon: b.icon,
                        color: b.color
                    )
                )
            }
        }
        let builtinKeys = Set(builtins.map(\.key))
        for u in userWorkspaceTemplates where !builtinKeys.contains(u.templateKey) {
            rows.append(
                WorkspaceTemplatePickerRow(
                    templateKey: u.templateKey,
                    title: u.displayName,
                    subtitle: u.description,
                    icon: u.icon,
                    color: u.color
                )
            )
        }
        return rows
    }

    /// Config blob for a template key: user `workspace_templates.json` or bundled `swarm_workspace_templates.json`.
    public func configForNewWorkspace(templateKey: String) throws -> JSONValue {
        if let u = userWorkspaceTemplates.first(where: { $0.templateKey == templateKey }) {
            return u.config ?? .object([:])
        }
        return try SwarmWorkspaceTemplateCatalog.configJSON(forTemplateKey: templateKey)
    }

    /// Persists a new user template whose config is copied from the currently selected base template.
    public func saveUserTemplateFromPicker(
        key: String,
        displayName: String,
        description: String,
        icon: String,
        color: String,
        baseTemplateKey: String
    ) throws {
        let config = try configForNewWorkspace(templateKey: baseTemplateKey)
        try WorkspaceTemplatesLoader.saveUserTemplateEntry(
            key: key,
            displayName: displayName,
            description: description,
            icon: icon,
            color: color,
            config: config,
            to: GrizzyClawPaths.workspaceTemplatesJSON
        )
        saveError = nil
        reload()
    }

    /// Creates a workspace, sets it active, and saves `workspaces.json`. Returns the new id.
    /// `config` is optional merged workspace config (e.g. from `workspace_templates.json`).
    @discardableResult
    public func createWorkspace(
        name: String,
        description: String,
        icon: String,
        color: String,
        config: JSONValue? = nil
    ) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WorkspaceMutationError.emptyName }

        try GrizzyClawPaths.ensureUserDataDirectoryExists()
        let url = GrizzyClawPaths.workspacesJSON

        var file: WorkspacesFile
        if FileManager.default.fileExists(atPath: url.path) {
            file = try WorkspaceIndexLoader.loadFile(from: url)
        } else {
            file = WorkspacesFile(activeWorkspaceId: nil, baselineWorkspaceId: nil, workspaces: [])
        }
        if file.workspaces.isEmpty {
            try WorkspaceBootstrap.writePythonDefaultWorkspacesFile(to: url)
            file = try WorkspaceIndexLoader.loadFile(from: url)
        }

        let newId = String(UUID().uuidString.prefix(8)).lowercased()
        let ws = WorkspaceRecord.makeNew(
            id: newId,
            name: trimmed,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : description,
            icon: icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "🤖" : icon,
            color: color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "#007AFF" : color,
            order: file.workspaces.count,
            config: config
        )
        file.workspaces.append(ws)
        file.activeWorkspaceId = newId
        if file.baselineWorkspaceId == nil {
            file.baselineWorkspaceId = newId
        }
        try WorkspaceIndexLoader.save(file, to: url)
        saveError = nil
        reload()
        return newId
    }

    /// Clones a workspace with a new id and `"\(name) (copy)"`, copying `config` and metadata (B5).
    @discardableResult
    public func duplicateWorkspace(id: String) throws -> String {
        try GrizzyClawPaths.ensureUserDataDirectoryExists()
        let url = GrizzyClawPaths.workspacesJSON
        var file = try WorkspaceIndexLoader.loadFile(from: url)
        guard let src = file.workspaces.first(where: { $0.id == id }) else {
            throw WorkspaceMutationError.workspaceNotFound(id)
        }
        let newId = String(UUID().uuidString.prefix(8)).lowercased()
        let newName = Self.duplicateWorkspaceName(from: src.name)
        let ws = WorkspaceRecord.makeNew(
            id: newId,
            name: newName,
            description: src.description,
            icon: src.icon ?? "🤖",
            color: src.color ?? "#007AFF",
            order: file.workspaces.count,
            config: src.config
        )
        file.workspaces.append(ws)
        file.activeWorkspaceId = newId
        try WorkspaceIndexLoader.save(file, to: url)
        saveError = nil
        reload()
        return newId
    }

    private static func duplicateWorkspaceName(from name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "Workspace (copy)" }
        return "\(t) (copy)"
    }

    public func updateWorkspace(
        id: String,
        name: String,
        description: String?,
        icon: String,
        color: String,
        llmProvider: String,
        llmModel: String,
        ollamaUrl: String,
        temperature: Double?,
        maxTokens: Int?,
        systemPrompt: String?
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WorkspaceMutationError.emptyName }

        let url = GrizzyClawPaths.workspacesJSON
        var file = try WorkspaceIndexLoader.loadFile(from: url)
        guard let i = file.workspaces.firstIndex(where: { $0.id == id }) else {
            throw WorkspaceMutationError.workspaceNotFound(id)
        }
        let old = file.workspaces[i]
        let merged = Self.mergedConfig(
            old.config,
            llmProvider: llmProvider,
            llmModel: llmModel,
            ollamaUrl: ollamaUrl,
            temperature: temperature,
            maxTokens: maxTokens,
            systemPrompt: systemPrompt
        )
        file.workspaces[i] = old.updatingFields(
            name: trimmed,
            description: description,
            icon: icon,
            color: color,
            order: old.order ?? i,
            config: merged
        )
        try WorkspaceIndexLoader.save(file, to: url)
        saveError = nil
        reload()
    }

    /// Python `WorkspaceDialog` parity: merge arbitrary `config` keys and update row metadata (including avatar).
    /// Pass `configPatch` entries; use `Optional.some(nil)` is not possible — use `JSONValue.null` or omit key to leave; to remove a key, merge layer can use a dedicated API later.
    public func saveWorkspaceFullEditor(
        id: String,
        name: String,
        description: String?,
        icon: String,
        color: String,
        avatarPath: String?,
        configPatch: [String: JSONValue]
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WorkspaceMutationError.emptyName }

        let url = GrizzyClawPaths.workspacesJSON
        var file = try WorkspaceIndexLoader.loadFile(from: url)
        guard let i = file.workspaces.firstIndex(where: { $0.id == id }) else {
            throw WorkspaceMutationError.workspaceNotFound(id)
        }
        let old = file.workspaces[i]
        let mergedConfig = Self.mergeConfigObject(old.config, patch: configPatch)
        let resolvedAvatar: String?
        if avatarPath == nil {
            resolvedAvatar = old.avatarPath
        } else {
            let t = avatarPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            resolvedAvatar = t.isEmpty ? nil : t
        }
        file.workspaces[i] = old.updatingEditor(
            name: trimmed,
            description: description,
            icon: icon,
            color: color,
            order: old.order ?? i,
            avatarPath: resolvedAvatar,
            config: mergedConfig
        )
        try WorkspaceIndexLoader.save(file, to: url)
        saveError = nil
        reload()
    }

    private static func mergeConfigObject(_ existing: JSONValue?, patch: [String: JSONValue]) -> JSONValue {
        var dict: [String: JSONValue] = [:]
        if case .object(let o) = existing {
            dict = o
        }
        for (k, v) in patch {
            if case .null = v {
                dict.removeValue(forKey: k)
            } else {
                dict[k] = v
            }
        }
        return .object(dict)
    }

    /// Adds marketplace bundle skills to `enabled_skills` and saves immediately (Python `add_marketplace_skill_to_workspace`).
    public func addMarketplaceSkillToWorkspace(
        workspaceId: String,
        marketplaceId: String,
        skillMarketplacePathFromConfig: String
    ) throws {
        let marketplace = try SkillMarketplaceLoader.load(skillMarketplacePathFromConfig: skillMarketplacePathFromConfig)
        guard let entry = marketplace.first(where: { $0.id == marketplaceId }), !entry.enabledSkillsAdd.isEmpty else {
            return
        }
        let url = GrizzyClawPaths.workspacesJSON
        var file = try WorkspaceIndexLoader.loadFile(from: url)
        guard let i = file.workspaces.firstIndex(where: { $0.id == workspaceId }) else {
            throw WorkspaceMutationError.workspaceNotFound(workspaceId)
        }
        var dict = Self.configObjectDict(file.workspaces[i].config)
        var cur = Self.stringArray(fromConfig: dict, key: "enabled_skills")
        for s in entry.enabledSkillsAdd where !cur.contains(s) {
            cur.append(s)
        }
        dict["enabled_skills"] = .array(cur.map { .string($0) })
        file.workspaces[i] = file.workspaces[i].updatingEditor(
            name: file.workspaces[i].name,
            description: file.workspaces[i].description,
            icon: file.workspaces[i].icon ?? "🤖",
            color: file.workspaces[i].color ?? "#007AFF",
            order: file.workspaces[i].order ?? i,
            avatarPath: file.workspaces[i].avatarPath,
            config: .object(dict)
        )
        try WorkspaceIndexLoader.save(file, to: url)
        saveError = nil
        reload()
    }

    /// Removes marketplace bundle skills from `enabled_skills` and saves immediately (Python `remove_marketplace_skill_from_workspace`).
    public func removeMarketplaceSkillFromWorkspace(
        workspaceId: String,
        marketplaceId: String,
        skillMarketplacePathFromConfig: String
    ) throws {
        let marketplace = try SkillMarketplaceLoader.load(skillMarketplacePathFromConfig: skillMarketplacePathFromConfig)
        guard let entry = marketplace.first(where: { $0.id == marketplaceId }), !entry.enabledSkillsAdd.isEmpty else {
            return
        }
        let url = GrizzyClawPaths.workspacesJSON
        var file = try WorkspaceIndexLoader.loadFile(from: url)
        guard let i = file.workspaces.firstIndex(where: { $0.id == workspaceId }) else {
            throw WorkspaceMutationError.workspaceNotFound(workspaceId)
        }
        var dict = Self.configObjectDict(file.workspaces[i].config)
        let remove = Set(entry.enabledSkillsAdd)
        let cur = Self.stringArray(fromConfig: dict, key: "enabled_skills").filter { !remove.contains($0) }
        dict["enabled_skills"] = .array(cur.map { .string($0) })
        file.workspaces[i] = file.workspaces[i].updatingEditor(
            name: file.workspaces[i].name,
            description: file.workspaces[i].description,
            icon: file.workspaces[i].icon ?? "🤖",
            color: file.workspaces[i].color ?? "#007AFF",
            order: file.workspaces[i].order ?? i,
            avatarPath: file.workspaces[i].avatarPath,
            config: .object(dict)
        )
        try WorkspaceIndexLoader.save(file, to: url)
        saveError = nil
        reload()
    }

    private static func configObjectDict(_ config: JSONValue?) -> [String: JSONValue] {
        if case .object(let o) = config { return o }
        return [:]
    }

    private static func stringArray(fromConfig dict: [String: JSONValue], key: String) -> [String] {
        guard let v = dict[key], case .array(let a) = v else { return [] }
        return a.compactMap { if case .string(let s) = $0 { return s }; return nil }
    }

    /// Persists `baseline_workspace_id` (Python parity).
    public func persistBaselineWorkspace(id: String) {
        let url = GrizzyClawPaths.workspacesJSON
        do {
            try WorkspaceActivePersistence.setBaselineWorkspaceId(id, fileURL: url)
            saveError = nil
            reload()
        } catch {
            saveError = error.localizedDescription
            GrizzyClawLog.error("persist baseline workspace failed: \(error.localizedDescription)")
        }
    }

    /// Sets active workspace to the saved baseline, if any.
    public func returnToBaselineWorkspace() {
        guard let baseline = index?.baselineWorkspaceId else { return }
        persistActiveWorkspace(id: baseline)
    }

    /// Reorders workspaces by `order` field (sidebar drag-and-drop).
    public func moveWorkspace(from source: IndexSet, to destination: Int) throws {
        let url = GrizzyClawPaths.workspacesJSON
        var file = try WorkspaceIndexLoader.loadFile(from: url)
        var ordered = file.workspaces.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
        ordered.move(fromOffsets: source, toOffset: destination)
        var newOrderById: [String: Int] = [:]
        for (idx, ws) in ordered.enumerated() {
            newOrderById[ws.id] = idx
        }
        for j in file.workspaces.indices {
            let id = file.workspaces[j].id
            guard let o = newOrderById[id] else { continue }
            file.workspaces[j] = file.workspaces[j].reordering(to: o)
        }
        try WorkspaceIndexLoader.save(file, to: url)
        saveError = nil
        reload()
    }

    public func deleteWorkspace(id: String) throws {
        let url = GrizzyClawPaths.workspacesJSON
        var file = try WorkspaceIndexLoader.loadFile(from: url)
        guard file.workspaces.count > 1 else {
            throw WorkspaceMutationError.cannotDeleteLastWorkspace
        }
        guard file.workspaces.contains(where: { $0.id == id }) else {
            throw WorkspaceMutationError.workspaceNotFound(id)
        }
        file.workspaces.removeAll { $0.id == id }
        if file.activeWorkspaceId == id {
            file.activeWorkspaceId = file.workspaces.first?.id
        }
        if file.baselineWorkspaceId == id {
            file.baselineWorkspaceId = file.workspaces.first(where: { $0.isDefault == true })?.id
                ?? file.workspaces.first?.id
        }
        try WorkspaceIndexLoader.save(file, to: url)
        saveError = nil
        reload()
    }

    private static func mergedConfig(
        _ existing: JSONValue?,
        llmProvider: String,
        llmModel: String,
        ollamaUrl: String,
        temperature: Double?,
        maxTokens: Int?,
        systemPrompt: String?
    ) -> JSONValue {
        var dict: [String: JSONValue] = [:]
        if case .object(let o) = existing {
            dict = o
        }
        dict["llm_provider"] = .string(llmProvider)
        dict["llm_model"] = .string(llmModel)
        dict["ollama_url"] = .string(ollamaUrl)
        if let temperature {
            dict["temperature"] = .double(temperature)
        } else {
            dict.removeValue(forKey: "temperature")
        }
        if let maxTokens {
            dict["max_tokens"] = .int(maxTokens)
        } else {
            dict.removeValue(forKey: "max_tokens")
        }
        let sp = systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if sp.isEmpty {
            dict.removeValue(forKey: "system_prompt")
        } else {
            dict["system_prompt"] = .string(sp)
        }
        return .object(dict)
    }
}
