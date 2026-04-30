import AppKit
import GrizzyClawAgent
import GrizzyClawCore
import SwiftUI
import UniformTypeIdentifiers

/// Main tab row — matches Python `tabs_main` (everything except Tools/Skills on `tabs_aux`).
private enum WorkspaceEditorMainTab: String, CaseIterable, Identifiable, Hashable {
    case general
    case work
    case llm
    case prompt
    case apiKeys
    case swarm
    case metrics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .work: return "Work"
        case .llm: return "LLM"
        case .prompt: return "Prompt"
        case .apiKeys: return "API Keys"
        case .swarm: return "Swarm"
        case .metrics: return "Metrics"
        }
    }
}

/// Second tab row — Python `tabs_aux`: Tools + Skills only.
private enum WorkspaceEditorAuxTab: String, CaseIterable, Identifiable, Hashable {
    case tools
    case skills

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tools: return "Tools"
        case .skills: return "Skills"
        }
    }
}

/// Which pane is shown (both tab rows drive the same content stack, like `WorkspaceDialog`).
private enum WorkspaceEditorPane: Hashable {
    case main(WorkspaceEditorMainTab)
    case aux(WorkspaceEditorAuxTab)
}

/// Keeps last MCP tool discovery per workspace while the app runs so the Tools tab survives
/// view recreation (save/reload, split view updates, tab switches that drop `tabContent` branches).
@MainActor
private enum WorkspaceEditorMCPCache {
    static var discovery: [String: [String: [MCPToolDescriptor]]] = [:]
}

/// Full settings + tabs for one workspace (Python Workspaces dialog right pane).
struct WorkspaceFullEditorView: View {
    let workspace: WorkspaceRecord
    let defaultProvider: String
    let defaultModel: String
    let defaultOllamaUrl: String
    let onSave: () -> Void
    /// Called after Duplicate so the split view selects the new workspace id.
    var onNavigateToWorkspaceId: ((String) -> Void)?

    @ObservedObject var workspaceStore: WorkspaceStore
    @ObservedObject var configStore: ConfigStore
    @ObservedObject var chatSession: ChatSessionModel

    @State private var selectedPane: WorkspaceEditorPane = .main(.general)
    @State private var name: String
    @State private var description: String
    @State private var icon: String
    @State private var color: String
    @State private var avatarPath: String

    @State private var chatMode: String
    @State private var workFolderPath: String

    @State private var llmProvider: String
    @State private var llmModel: String
    @State private var ollamaUrl: String
    @State private var lmstudioUrl: String
    @State private var lmstudioV1Url: String
    @State private var temperatureText: String
    @State private var maxTokensText: String

    @State private var systemPrompt: String

    @State private var memoryEnabled: Bool
    @State private var memoryFile: String
    @State private var maxContextLength: String
    @State private var maxSessionMessages: String

    @State private var enableInterAgent: Bool
    @State private var interAgentChannel: String
    @State private var useSharedMemory: Bool
    @State private var swarmAutoDelegate: Bool
    @State private var swarmConsensus: Bool

    @State private var subagentsEnabled: Bool
    @State private var subagentsMaxDepth: Int
    @State private var subagentsMaxChildren: Int
    /// Display string for default sub-agent run timeout (`"No timeout"` or seconds — matches Python `QSpinBox` special value).
    @State private var subagentsRunTimeoutField: String

    @State private var proactiveHabits: Bool
    @State private var proactiveScreen: Bool
    @State private var proactiveAutonomy: Bool
    @State private var proactiveAutonomyIntervalMinutes: Int
    @State private var proactiveFileTriggers: Bool
    @State private var enableFolderWatchers: Bool

    @State private var safetyContentFilter: Bool
    @State private var autonomyLevel: String

    @State private var useAgentsSdk: Bool
    @State private var agentsSdkMaxTurns: Int

    @State private var apiKeyOpenAI: String
    @State private var apiKeyAnthropic: String
    @State private var apiKeyOpenRouter: String
    @State private var apiKeyCursor: String
    @State private var apiKeyOpenCodeZen: String
    @State private var apiKeyLMStudio: String
    @State private var apiKeyLMStudioV1: String

    @State private var saveError: String?
    @State private var saveSuccessVisible = false
    @State private var saveSuccessDismiss: Task<Void, Never>?

    // Tools (Python WorkspaceDialog → Tools tab)
    @State private var enforceToolAllowlist: Bool
    @State private var discoveredTools: [String: [MCPToolDescriptor]]
    @State private var toolSwitchOn: [String: Bool]
    @State private var expandedToolServers: Set<String> = []
    @State private var toolsRefreshing = false
    @State private var toolsDiscoveryMessage: String?

    // Skills marketplace rows
    @State private var marketplaceEntries: [SkillMarketplaceEntry] = []
    @State private var marketplaceLoadError: String?
    @State private var workspaceSkillsOverrideEnabled: Bool
    @State private var workspaceSkillIDs: [String]

    // LLM model suggestions for the workspace editor.
    @State private var availableModelsByProvider: [String: [ModelPickerModels.Row]] = [:]
    @State private var llmModelsLoading = false
    @State private var llmModelsMessage: String?
    @State private var llmModelsMessageIsError = false

    @State private var benchmarkBusy = false
    @State private var benchmarkResult = ""

    @State private var showingSaveTemplateSheet = false
    @State private var templateKeyDraft = ""

    init(
        workspace: WorkspaceRecord,
        workspaceStore: WorkspaceStore,
        configStore: ConfigStore,
        chatSession: ChatSessionModel,
        defaultProvider: String,
        defaultModel: String,
        defaultOllamaUrl: String,
        defaultLmstudioUrl: String,
        defaultLmstudioV1Url: String,
        onSave: @escaping () -> Void,
        onNavigateToWorkspaceId: ((String) -> Void)? = nil
    ) {
        self.workspace = workspace
        self.workspaceStore = workspaceStore
        self.configStore = configStore
        self.chatSession = chatSession
        self.defaultProvider = defaultProvider
        self.defaultModel = defaultModel
        self.defaultOllamaUrl = defaultOllamaUrl
        self.onSave = onSave
        self.onNavigateToWorkspaceId = onNavigateToWorkspaceId
        let cfg = workspace.config
        _name = State(initialValue: workspace.name)
        _description = State(initialValue: workspace.description ?? "")
        _icon = State(initialValue: workspace.icon ?? "🤖")
        _color = State(initialValue: workspace.color ?? "#007AFF")
        _avatarPath = State(initialValue: workspace.avatarPath ?? "")

        _chatMode = State(initialValue: cfg?.string(forKey: "chat_mode") ?? "chat")
        _workFolderPath = State(initialValue: cfg?.string(forKey: "work_folder_path") ?? "")

        _llmProvider = State(initialValue: cfg?.string(forKey: "llm_provider") ?? defaultProvider)
        _llmModel = State(initialValue: cfg?.string(forKey: "llm_model") ?? defaultModel)
        _ollamaUrl = State(initialValue: cfg?.string(forKey: "ollama_url") ?? defaultOllamaUrl)
        _lmstudioUrl = State(initialValue: cfg?.string(forKey: "lmstudio_url") ?? defaultLmstudioUrl)
        _lmstudioV1Url = State(initialValue: cfg?.string(forKey: "lmstudio_v1_url") ?? defaultLmstudioV1Url)
        if let t = cfg?.double(forKey: "temperature") {
            _temperatureText = State(initialValue: String(t))
        } else {
            _temperatureText = State(initialValue: "0.7")
        }
        if let m = cfg?.int(forKey: "max_tokens") {
            _maxTokensText = State(initialValue: String(m))
        } else {
            _maxTokensText = State(initialValue: "131072")
        }

        _systemPrompt = State(initialValue: cfg?.string(forKey: "system_prompt") ?? "")

        _memoryEnabled = State(initialValue: cfg?.bool(forKey: "memory_enabled") ?? true)
        _memoryFile = State(initialValue: cfg?.string(forKey: "memory_file") ?? "")
        _maxContextLength = State(initialValue: {
            if let v = cfg?.int(forKey: "max_context_length") { return String(v) }
            return "4000"
        }())
        _maxSessionMessages = State(initialValue: {
            if let v = cfg?.int(forKey: "max_session_messages") { return String(v) }
            return "20"
        }())

        _enableInterAgent = State(initialValue: cfg?.bool(forKey: "enable_inter_agent") ?? false)
        _interAgentChannel = State(initialValue: cfg?.string(forKey: "inter_agent_channel") ?? "")
        _useSharedMemory = State(initialValue: cfg?.bool(forKey: "use_shared_memory") ?? false)
        _swarmAutoDelegate = State(initialValue: cfg?.bool(forKey: "swarm_auto_delegate") ?? false)
        _swarmConsensus = State(initialValue: cfg?.bool(forKey: "swarm_consensus") ?? false)

        _subagentsEnabled = State(initialValue: cfg?.bool(forKey: "subagents_enabled") ?? false)
        _subagentsMaxDepth = State(initialValue: {
            let v = cfg?.int(forKey: "subagents_max_depth") ?? 2
            return max(1, min(5, v))
        }())
        _subagentsMaxChildren = State(initialValue: {
            let v = cfg?.int(forKey: "subagents_max_children") ?? 5
            return max(1, min(20, v))
        }())
        _subagentsRunTimeoutField = State(initialValue: {
            let sec = max(0, cfg?.int(forKey: "subagents_run_timeout_seconds") ?? 0)
            return sec == 0 ? "No timeout" : String(sec)
        }())

        _proactiveHabits = State(initialValue: cfg?.bool(forKey: "proactive_habits") ?? false)
        _proactiveScreen = State(initialValue: cfg?.bool(forKey: "proactive_screen") ?? false)
        _proactiveAutonomy = State(initialValue: cfg?.bool(forKey: "proactive_autonomy") ?? false)
        _proactiveAutonomyIntervalMinutes = State(initialValue: {
            let v = cfg?.int(forKey: "proactive_autonomy_interval_minutes") ?? 15
            return max(5, min(60, v))
        }())
        _proactiveFileTriggers = State(initialValue: cfg?.bool(forKey: "proactive_file_triggers") ?? false)
        _enableFolderWatchers = State(initialValue: cfg?.bool(forKey: "enable_folder_watchers") ?? true)

        _safetyContentFilter = State(initialValue: cfg?.bool(forKey: "safety_content_filter") ?? true)
        _autonomyLevel = State(initialValue: cfg?.string(forKey: "autonomy_level") ?? "")

        _useAgentsSdk = State(initialValue: cfg?.bool(forKey: "use_agents_sdk") ?? false)
        _agentsSdkMaxTurns = State(initialValue: {
            let v = cfg?.int(forKey: "agents_sdk_max_turns") ?? 25
            return max(5, min(100, v))
        }())

        _apiKeyOpenAI = State(initialValue: cfg?.string(forKey: "openai_api_key") ?? "")
        _apiKeyAnthropic = State(initialValue: cfg?.string(forKey: "anthropic_api_key") ?? "")
        _apiKeyOpenRouter = State(initialValue: cfg?.string(forKey: "openrouter_api_key") ?? "")
        _apiKeyCursor = State(initialValue: cfg?.string(forKey: "cursor_api_key") ?? "")
        _apiKeyOpenCodeZen = State(initialValue: cfg?.string(forKey: "opencode_zen_api_key") ?? "")
        _apiKeyLMStudio = State(initialValue: cfg?.string(forKey: "lmstudio_api_key") ?? "")
        _apiKeyLMStudioV1 = State(initialValue: cfg?.string(forKey: "lmstudio_v1_api_key") ?? "")
        _workspaceSkillsOverrideEnabled = State(initialValue: cfg?.stringArrayIfPresent(forKey: "enabled_skills") != nil)
        _workspaceSkillIDs = State(initialValue: cfg?.stringArray(forKey: "enabled_skills") ?? [])

        let capPairs = cfg?.mcpToolAllowlistPairs(forKey: "mcp_tool_allowlist")
        let cachedDisc = WorkspaceEditorMCPCache.discovery[workspace.id] ?? [:]
        let initialDisc: [String: [MCPToolDescriptor]] = {
            if !cachedDisc.isEmpty { return cachedDisc }
            if let pairs = capPairs, !pairs.isEmpty {
                return Self.discoveredToolsFromAllowlistPairs(pairs)
            }
            return [:]
        }()
        _discoveredTools = State(initialValue: initialDisc)
        _enforceToolAllowlist = State(initialValue: !(capPairs ?? []).isEmpty)
        _toolSwitchOn = State(initialValue: Self.toolSwitchMap(discovered: initialDisc, capPairs: capPairs))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleHeader
            workspaceTabBars
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            ScrollView {
                tabContent
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            if let err = saveError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
            actionFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingSaveTemplateSheet) {
            NavigationStack {
                Form {
                    TextField("Template key (letters, numbers, underscores)", text: $templateKeyDraft)
                        .textFieldStyle(.roundedBorder)
                    Text("Appears in + New alongside built-in templates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .formStyle(.grouped)
                .navigationTitle("Save as template")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingSaveTemplateSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            commitSaveTemplate()
                        }
                        .disabled(templateKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .frame(minWidth: 400, minHeight: 200)
        }
        .task(id: workspace.id) {
            do {
                marketplaceEntries = try SkillMarketplaceLoader.load(
                    skillMarketplacePathFromConfig: configStore.snapshot.skillMarketplacePath
                )
                marketplaceLoadError = nil
            } catch {
                marketplaceLoadError = error.localizedDescription
                marketplaceEntries = (try? SkillMarketplaceLoader.load(skillMarketplacePathFromConfig: "")) ?? []
            }
        }
        .onChange(of: workspace.id) {
            benchmarkResult = ""
        }
    }

    private var titleHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(icon) \(name)")
                    .font(.system(size: 24, weight: .bold))
                Spacer()
                if saveSuccessVisible {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: saveSuccessVisible)

            if workspace.id == workspaceStore.index?.baselineWorkspaceId {
                Text("🎯 Baseline workspace — Workspaces → Return to baseline (⌃⇧B) switches here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("Not the baseline — 🎯 Set as baseline uses this as your normal home after swarm/specialist setups.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private var actionFooter: some View {
        let baselineId = workspaceStore.index?.baselineWorkspaceId
        return HStack(spacing: 8) {
            Button("🔄 Switch to This Workspace") {
                workspaceStore.persistActiveWorkspace(id: workspace.id)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255))
            .help("Sets this workspace as active (same as Python).")

            Button("💾 Save Changes") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)

            Spacer(minLength: 8)

            Button("📋 Duplicate") {
                duplicateFromFooter()
            }
            .help("Duplicate this workspace.")

            if baselineId != workspace.id {
                Button("🎯 Set as baseline") {
                    workspaceStore.persistBaselineWorkspace(id: workspace.id)
                }
                .help("Use Workspaces → Return to baseline (⌃⇧B) to jump back here.")
            }

            Button("Save as template…") {
                templateKeyDraft = defaultTemplateKey(from: name)
                showingSaveTemplateSheet = true
            }
            .help("Save this setup to ~/.grizzyclaw/workspace_templates.json for + New.")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func defaultTemplateKey(from name: String) -> String {
        let lowered = name.lowercased()
        var out = ""
        for ch in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(ch) {
                out.unicodeScalars.append(ch)
            } else if !out.isEmpty, out.last != "_" {
                out.append("_")
            }
        }
        while out.last == "_" { out.removeLast() }
        let base = String(out.prefix(48))
        return base.isEmpty ? "my_template" : base
    }

    private func duplicateFromFooter() {
        saveError = nil
        do {
            let newId = try workspaceStore.duplicateWorkspace(id: workspace.id)
            onNavigateToWorkspaceId?(newId)
            onSave()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func commitSaveTemplate() {
        let key = templateKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        saveError = nil
        do {
            try workspaceStore.saveUserTemplate(key: key, fromWorkspaceId: workspace.id)
            showingSaveTemplateSheet = false
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func runWorkspaceBenchmark() {
        benchmarkResult = "Running…"
        benchmarkBusy = true
        let wid = workspace.id
        Task {
            let result = await chatSession.runUsageBenchmark(
                workspaceStore: workspaceStore,
                configStore: configStore,
                selectedWorkspaceId: wid,
                guiLlmOverride: nil as GuiChatPreferences.LLM?
            )
            await MainActor.run {
                benchmarkBusy = false
                switch result {
                case .succeeded(let elapsedMs, let approxTokens):
                    benchmarkResult = String(format: "Done: %.0f ms, ~%d tokens", elapsedMs, approxTokens)
                case .failed(let err):
                    benchmarkResult = "Error: \(String(err.prefix(120)))"
                }
                workspaceStore.reload()
            }
        }
    }

    /// Two-row tab bars (`tabs_main` + `tabs_aux`) sharing one content area — same layout as Python `WorkspaceDialog`.
    private var workspaceTabBars: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(WorkspaceEditorMainTab.allCases) { mt in
                        workspaceTabChip(
                            title: mt.title,
                            isSelected: isMainTabSelected(mt),
                            verticalPadding: 8
                        ) {
                            selectedPane = .main(mt)
                        }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(WorkspaceEditorAuxTab.allCases) { at in
                        workspaceTabChip(
                            title: at.title,
                            isSelected: isAuxTabSelected(at),
                            verticalPadding: 6
                        ) {
                            selectedPane = .aux(at)
                        }
                    }
                }
            }
        }
    }

    private func isMainTabSelected(_ t: WorkspaceEditorMainTab) -> Bool {
        if case .main(let m) = selectedPane { return m == t }
        return false
    }

    private func isAuxTabSelected(_ t: WorkspaceEditorAuxTab) -> Bool {
        if case .aux(let a) = selectedPane { return a == t }
        return false
    }

    private func workspaceTabChip(
        title: String,
        isSelected: Bool,
        verticalPadding: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, verticalPadding)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor)
                    } else {
                        Color.clear
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedPane {
        case .main(let t):
            switch t {
            case .general:
                generalForm
            case .work:
                workForm
            case .llm:
                llmForm
            case .prompt:
                promptForm
            case .apiKeys:
                apiKeysForm
            case .swarm:
                swarmForm
            case .metrics:
                metricsForm
            }
        case .aux(let t):
            switch t {
            case .tools:
                workspaceToolsSection
            case .skills:
                WorkspaceSkillEditorSection(
                    usesWorkspaceOverride: $workspaceSkillsOverrideEnabled,
                    workspaceSkillIDs: $workspaceSkillIDs,
                    inheritedSkillIDs: ClawHubSkillResolver.defaultSkillIDs(user: configStore.snapshot),
                    marketplaceEntries: marketplaceEntries,
                    marketplaceLoadError: marketplaceLoadError
                )
            }
        }
    }

    private var generalForm: some View {
        Form {
            Section {
                LabeledContent("Name:") {
                    TextField("", text: $name, prompt: Text("Workspace name"))
                }
                LabeledContent("Description:") {
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...8)
                }
                LabeledContent("Icon:") {
                    HStack(spacing: 12) {
                        TextField("", text: $icon, prompt: Text("🤖"))
                            .frame(width: 56)
                        Text("Color:")
                            .foregroundStyle(.secondary)
                        TextField("", text: $color, prompt: Text("#007AFF"))
                            .frame(minWidth: 100)
                    }
                }
                LabeledContent("Avatar:") {
                    HStack(spacing: 8) {
                        TextField(
                            "Path or URL to custom/VL-generated avatar image (optional)",
                            text: $avatarPath
                        )
                        Button("Browse…") { browseAvatarPath() }
                            .fixedSize()
                    }
                }
                LabeledContent("Share:") {
                    Button("Copy share link") { copyWorkspaceShareLink() }
                        .help(
                            "Export this workspace as a link to paste elsewhere (Import link to add it there)."
                        )
                }
            }
        }
        .formStyle(.grouped)
    }

    private var workForm: some View {
        Form {
            Section {
                Text(
                    "Work mode binds a folder on disk to this workspace. The model receives a project tree, "
                        + "git status when available, and fast-filesystem (Agents SDK) gets that path allowed automatically."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Picker("Mode:", selection: $chatMode) {
                    Text("Chat").tag("chat")
                    Text("Work").tag("work")
                }
                .help(
                    "Chat: normal assistant. Work: inject working-directory context (tree, git, manifest) and prefer that path for tools."
                )
                Text("Working directory:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("/path/to/your/project", text: $workFolderPath)
                    Button("Choose…") { browseWorkFolder() }
                        .fixedSize()
                    Button("Clear") { workFolderPath = "" }
                        .fixedSize()
                }
            }
        }
        .formStyle(.grouped)
    }

    private static let llmProviderOptions = [
        "ollama", "lmstudio", "lmstudio_v1", "mlx", "openai", "anthropic", "openrouter", "cursor", "opencode_zen",
    ]

    /// Includes current `llm_provider` if it is a custom id not in the default list (Python combo is editable).
    private var llmProviderPickerOptions: [String] {
        var o = Self.llmProviderOptions
        let cur = llmProvider.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cur.isEmpty, !o.contains(cur) {
            o.insert(cur, at: 0)
        }
        return o
    }

    private var availableModelsForSelectedProvider: [ModelPickerModels.Row] {
        let providerKey = llmProvider.trimmingCharacters(in: .whitespacesAndNewlines)
        var rows = availableModelsByProvider[providerKey] ?? []
        let trimmedCurrentModel = llmModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCurrentModel.isEmpty, !rows.contains(where: { $0.modelId == trimmedCurrentModel }) {
            rows.insert(.init(modelId: trimmedCurrentModel, displayName: trimmedCurrentModel), at: 0)
        }
        return rows
    }

    private var llmForm: some View {
        Form {
            Section {
                Picker("Provider:", selection: $llmProvider) {
                    ForEach(llmProviderPickerOptions, id: \.self) { p in
                        Text(p).tag(p)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("Select or type model name", text: $llmModel)
                    if !availableModelsForSelectedProvider.isEmpty {
                        Menu {
                            ForEach(availableModelsForSelectedProvider) { row in
                                Button(row.displayName) {
                                    llmModel = row.modelId
                                }
                            }
                        } label: {
                            Text("Suggestions")
                        }
                        .fixedSize()
                    }
                    Button {
                        refreshWorkspaceModelList()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh models from configured providers and update suggestions for this workspace.")
                    .disabled(llmModelsLoading)
                    if llmModelsLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Text(
                    availableModelsForSelectedProvider.isEmpty
                        ? "Type a model manually or refresh to load provider-backed suggestions."
                        : "Suggestions come from the selected provider when available; you can still type any model id manually."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if let llmModelsMessage {
                    Text(llmModelsMessage)
                        .font(.caption)
                        .foregroundStyle(llmModelsMessageIsError ? .red : .secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LabeledContent("Temperature:") {
                    TextField("", text: $temperatureText)
                        .frame(maxWidth: 80)
                }
                LabeledContent("Max Tokens:") {
                    TextField("", text: $maxTokensText)
                        .frame(maxWidth: 120)
                }
                Text(
                    "Model max context is shown in the Python app when the LLM router can query the provider."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Stepper(value: Binding(
                    get: { Int(maxSessionMessages.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 20 },
                    set: { maxSessionMessages = String($0) }
                ), in: 4...100) {
                    Text("Context Window (messages): \(maxSessionMessages)")
                }
                .help("Max conversation turns to keep. Older tool-heavy messages are prioritized.")
                Toggle("Use Agents SDK (OpenAI + LiteLLM)", isOn: $useAgentsSdk)
                    .help(
                        "Use OpenAI Agents SDK with LiteLLM for improved coding workflows. "
                            + "Requires: pip install 'openai-agents[litellm]'. Uses MCP tools natively."
                    )
                Stepper(value: $agentsSdkMaxTurns, in: 5...100) {
                    Text("Agents SDK Max Turns: \(agentsSdkMaxTurns)")
                }
                .help(
                    "Max agent turns when using Agents SDK (tool-call iterations). "
                        + "Increase for complex multi-file coding tasks."
                )
            }
            Section("Custom provider URLs (optional overrides)") {
                TextField("Ollama URL", text: $ollamaUrl)
                TextField("LM Studio URL (OpenAI-compat, e.g. http://localhost:1234/v1)", text: $lmstudioUrl)
                TextField("LM Studio V1 URL (native API base, e.g. http://192.168.1.x:1234)", text: $lmstudioV1Url)
            }
            Section("Memory") {
                Text(
                    "Memory settings apply to this workspace’s SQLite store under ~/.grizzyclaw/ (same as the Python app)."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Toggle("Enable memory for this workspace", isOn: $memoryEnabled)
                TextField("Custom memory database file (optional override)", text: $memoryFile, prompt: Text("Default: workspace_{id}.db"))
                LabeledContent("Max context length (tokens):") {
                    TextField("", text: $maxContextLength)
                        .frame(maxWidth: 120)
                }
                .help("Token budget for retrieved memory / context (see Python WorkspaceConfig).")
            }
        }
        .formStyle(.grouped)
        .task(id: workspace.id) {
            guard availableModelsByProvider.isEmpty else { return }
            refreshWorkspaceModelList()
        }
        .onChange(of: llmProvider) {
            llmModelsMessage = nil
            if availableModelsByProvider[llmProvider.trimmingCharacters(in: .whitespacesAndNewlines)] == nil {
                refreshWorkspaceModelList()
            }
        }
    }

    private var promptForm: some View {
        Form {
            Section {
                TextEditor(text: $systemPrompt)
                    .font(.body)
                    .frame(minHeight: 280)
            } header: {
                Text("System Prompt:")
            } footer: {
                Text("Enter the system prompt for this workspace…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var apiKeysForm: some View {
        Form {
            Section {
                Text(
                    "Optional per-workspace API key overrides. Leave empty to use the key from ~/.grizzyclaw/config.yaml (or Keychain)."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                apiKeyRow(label: "OpenAI Key:", text: $apiKeyOpenAI)
                apiKeyRow(label: "Anthropic Key:", text: $apiKeyAnthropic)
                apiKeyRow(label: "OpenRouter Key:", text: $apiKeyOpenRouter)
                apiKeyRow(label: "Cursor Key:", text: $apiKeyCursor)
                apiKeyRow(label: "OpenCode Zen API Key:", text: $apiKeyOpenCodeZen)
                apiKeyRow(label: "LM Studio Key:", text: $apiKeyLMStudio)
                apiKeyRow(label: "LM Studio v1 Key:", text: $apiKeyLMStudioV1)
            }
        }
        .formStyle(.grouped)
    }

    private func apiKeyRow(label: String, text: Binding<String>) -> some View {
        LabeledContent(label) {
            SecureField("Leave empty to use global setting", text: text)
        }
    }

    private var metricsWorkspaceSnapshot: WorkspaceRecord? {
        workspaceStore.index?.workspaces.first(where: { $0.id == workspace.id })
    }

    private var metricsForm: some View {
        Form {
            Section("📊 Performance Metrics") {
                metricsStatsContent(for: metricsWorkspaceSnapshot ?? workspace)
                HStack(spacing: 12) {
                    Button("🚀 Run Benchmark (5 prompts)") {
                        runWorkspaceBenchmark()
                    }
                    .disabled(benchmarkBusy)
                    if benchmarkBusy {
                        ProgressView().controlSize(.small)
                    }
                }
                if !benchmarkResult.isEmpty {
                    Text(benchmarkResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func metricsStatsContent(for w: WorkspaceRecord) -> some View {
        let msgs = w.messageCount ?? 0
        let avgMs = msgs > 0 ? (w.totalResponseTimeMs ?? 0) / Double(msgs) : 0.0
        let totalTok = (w.totalInputTokens ?? 0) + (w.totalOutputTokens ?? 0)
        let up = w.feedbackUp ?? 0
        let down = w.feedbackDown ?? 0
        let totalFb = up + down
        let quality: String = totalFb > 0
            ? String(format: "%.1f%%", Double(up) / Double(totalFb) * 100.0)
            : "N/A (no feedback yet)"
        LabeledContent("Avg Response Time:") {
            Text(String(format: "%.1f ms", avgMs))
        }
        LabeledContent("Total Tokens:") {
            Text("\(totalTok)")
        }
        LabeledContent("Quality Score:") {
            Text(quality)
        }
        LabeledContent("Messages:") {
            Text("\(msgs)")
        }
        LabeledContent("Sessions:") {
            Text("\(w.sessionCount ?? 0)")
        }
    }

    private var swarmForm: some View {
        Form {
            Section {
                Toggle("Allow this workspace to receive and send messages to other agents (@mentions)", isOn: $enableInterAgent)
                    .help(
                        "Enable agent-to-agent chat: type @workspace_name or @slug to delegate (e.g. @code_assistant analyze this)."
                    )
                TextField(
                    "Inter-agent channel:",
                    text: $interAgentChannel,
                    prompt: Text("Optional: e.g. swarm1 (only same-channel workspaces can message each other)")
                )
                Toggle("Use shared memory with other agents in the same channel", isOn: $useSharedMemory)
                    .help(
                        "When enabled, this workspace shares a memory DB with other workspaces on the same channel for swarm context."
                    )
                Toggle(
                    "Leader: auto-run @mentions from my response (break task → delegate to specialists)",
                    isOn: $swarmAutoDelegate
                )
                .help(
                    "When this workspace is the leader, any @research / @coding / @personal / @planning lines in its reply are executed and specialist replies are collected."
                )
                Toggle(
                    "Leader: synthesize specialist replies into one consensus answer",
                    isOn: $swarmConsensus
                )
                .help(
                    "After delegations, call the leader again to combine specialist responses into a single recommendation."
                )
            }

            Section("Sub-agents") {
                Toggle("Enable sub-agents (SPAWN_SUBAGENT)", isOn: $subagentsEnabled)
                    .help(
                        "Allow this agent to spawn background sub-agent runs for parallel or delegated tasks. Results are announced when complete."
                    )
                Stepper(value: $subagentsMaxDepth, in: 1...5) {
                    Text("Max spawn depth: \(subagentsMaxDepth)")
                }
                .help(
                    "Max spawn depth: 1 = only main can spawn; 2 = main and one level of children can spawn."
                )
                Stepper(value: $subagentsMaxChildren, in: 1...20) {
                    Text("Max children per parent: \(subagentsMaxChildren)")
                }
                .help("Max concurrent child runs per parent.")
                LabeledContent("Default run timeout:") {
                    HStack(spacing: 8) {
                        TextField("", text: $subagentsRunTimeoutField, prompt: Text("No timeout or seconds"))
                            .frame(minWidth: 160, alignment: .trailing)
                            .multilineTextAlignment(.trailing)
                        if Self.parseSubagentRunTimeoutSeconds(subagentsRunTimeoutField) > 0 {
                            Text("s")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .help("Default run timeout for spawned sub-agents (0 = no timeout).")
            }

            Section("Proactivity") {
                Toggle(
                    "Habit learning: analyze memory and auto-schedule actions (e.g. prep env Mon–Fri)",
                    isOn: $proactiveHabits
                )
                .help("Daily job analyzes memory patterns and suggests habit-based reminders.")
                Toggle(
                    "Screen awareness: periodic screenshot + VL analysis for desktop context",
                    isOn: $proactiveScreen
                )
                .help("Every 30 min, capture screen and ask the model what the user is doing; store summary in memory.")
                Toggle(
                    "Continuous Autonomy: background loop for predictive prep and tasks",
                    isOn: $proactiveAutonomy
                )
                .help("Agent creates a background loop checking workspace state periodically even without prompts.")
                Stepper(value: $proactiveAutonomyIntervalMinutes, in: 5...60) {
                    Text("Autonomy interval: \(proactiveAutonomyIntervalMinutes) min")
                }
                .help("How often the autonomy loop runs (5–60 minutes).")
                Toggle("Triggers on file changes and Git events", isOn: $proactiveFileTriggers)
                    .help(
                        "Watch ~/.grizzyclaw/file_watcher.json for watch_dirs; triggers.json can use event file_change or git_event."
                    )
                Toggle(
                    "Folder Watchers (per-folder AI runs, globs, convergence)",
                    isOn: $enableFolderWatchers
                )
                .help(
                    "Each watcher has its own folder, instructions, debounce, and optional glob filters. "
                        + "Storage: ~/.grizzyclaw/watchers/. Use Open Folder Watchers… to edit."
                )
                Button("Open Folder Watchers…") {
                    _ = try? GrizzyClawPaths.ensureWatchersDirectoryExists()
                    NSWorkspace.shared.open(GrizzyClawPaths.watchersDirectory)
                }
            }

            Section {
                Text(
                    "Tip: In chat, use @workspace_slug or @Workspace Name to delegate (e.g. @coding analyze this code). "
                        + "Leader can output @research / @coding / @personal / @planning to auto-delegate."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Safety") {
                Text(
                    "Guardrails for this workspace. Content filtering applies before messages are shown; autonomy overrides the global default when set."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Toggle("Enable safety content filter", isOn: $safetyContentFilter)
                    .help("When enabled, harmful or policy-violating model output is blocked or rewritten (Python AgentCore).")
                LabeledContent("Autonomy level override:") {
                    TextField("read_only, supervised, or full — empty uses global", text: $autonomyLevel)
                }
                .help("Leave empty to inherit `autonomy_level` from ~/.grizzyclaw/config.yaml.")
            }
        }
        .formStyle(.grouped)
    }

    private var workspaceToolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workspace tool allowlist (hard cap)")
                .font(.headline)
            Text(
                "When enabled, this workspace can only call the tools you select here. "
                    + "The chat Tools dropdown can still filter further, but cannot enable anything outside this list. "
                    + "Discovery reads `mcp_servers_file` (JSON) and talks to each server natively over stdio / HTTP — no Python helper required."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text("MCP file: \(configStore.snapshot.mcpServersFile)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)

            Toggle("Enforce allowlist for this workspace", isOn: $enforceToolAllowlist)

            HStack {
                Button("Enable all") {
                    var next = toolSwitchOn
                    for (srv, pairs) in discoveredTools {
                        for p in pairs {
                            next[Self.toolKey(server: srv, tool: p.name)] = true
                        }
                    }
                    toolSwitchOn = next
                }
                .disabled(discoveredTools.isEmpty)
                Button("Disable all") {
                    var next = toolSwitchOn
                    for (srv, pairs) in discoveredTools {
                        for p in pairs {
                            next[Self.toolKey(server: srv, tool: p.name)] = false
                        }
                    }
                    toolSwitchOn = next
                }
                .disabled(discoveredTools.isEmpty)
                Spacer()
                Button {
                    refreshMcpTools()
                } label: {
                    if toolsRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Refresh")
                    }
                }
                .disabled(toolsRefreshing)
            }

            if let toolsDiscoveryMessage {
                Text(toolsDiscoveryMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if discoveredTools.isEmpty {
                Text("Click Refresh to discover tools from your MCP servers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let sortedServers = discoveredTools.keys.sorted()
                ForEach(sortedServers, id: \.self) { srv in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedToolServers.contains(srv) },
                            set: { on in
                                if on { expandedToolServers.insert(srv) } else { expandedToolServers.remove(srv) }
                            }
                        ),
                        content: {
                            let pairs = discoveredTools[srv] ?? []
                            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                                let key = Self.toolKey(server: srv, tool: pair.name)
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pair.name)
                                            .font(.body)
                                        if !pair.description.isEmpty {
                                            Text(pair.description)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(3)
                                        }
                                    }
                                    Spacer()
                                    Toggle(
                                        "",
                                        isOn: toolToggleBinding(key: key)
                                    )
                                    .labelsHidden()
                                }
                                .padding(.vertical, 4)
                            }
                        },
                        label: {
                            HStack {
                                Text(srv)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(discoveredTools[srv]?.count ?? 0)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    )
                }
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .onAppear {
            guard discoveredTools.isEmpty else { return }
            // In-session cache (survives tab switches); lost on quit.
            if let cached = WorkspaceEditorMCPCache.discovery[workspace.id], !cached.isEmpty {
                discoveredTools = cached
                let cap = workspaceStore.index?.workspaces.first(where: { $0.id == workspace.id })?
                    .config?
                    .mcpToolAllowlistPairs(forKey: "mcp_tool_allowlist")
                rebuildToolSwitches(cap: cap)
                return
            }
            // After relaunch: rebuild tool rows from saved allowlist so toggles aren’t blank.
            let cap = workspaceStore.index?.workspaces.first(where: { $0.id == workspace.id })?
                .config?
                .mcpToolAllowlistPairs(forKey: "mcp_tool_allowlist")
            if let pairs = cap, !pairs.isEmpty {
                discoveredTools = Self.discoveredToolsFromAllowlistPairs(pairs)
                rebuildToolSwitches(cap: pairs)
                refreshMcpTools()
                return
            }
            refreshMcpTools()
        }
    }

    private func toolToggleBinding(key: String) -> Binding<Bool> {
        Binding(
            get: {
                toolSwitchOn[key] ?? true
            },
            set: { newVal in
                toolSwitchOn[key] = newVal
            }
        )
    }

    private static func toolKey(server: String, tool: String) -> String {
        "\(server)\u{1D}\(tool)"
    }

    /// Builds a minimal discovery map from persisted `mcp_tool_allowlist` (descriptions empty until Refresh).
    private static func discoveredToolsFromAllowlistPairs(_ pairs: [(String, String)]) -> [String: [MCPToolDescriptor]] {
        var dict: [String: [MCPToolDescriptor]] = [:]
        for (srv, tool) in pairs {
            guard !srv.isEmpty, !tool.isEmpty else { continue }
            dict[srv, default: []].append(MCPToolDescriptor(name: tool, description: ""))
        }
        for srv in dict.keys {
            dict[srv]?.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return dict
    }

    private func refreshMcpTools() {
        toolsRefreshing = true
        toolsDiscoveryMessage = nil
        let mcpPath = configStore.snapshot.mcpServersFile
        let wid = workspace.id
        Task {
            do {
                let result = try await MCPToolsDiscovery.discover(mcpServersFile: mcpPath)
                await MainActor.run {
                    toolsRefreshing = false
                    discoveredTools = result.servers
                    WorkspaceEditorMCPCache.discovery[wid] = result.servers
                    toolsDiscoveryMessage = result.errorMessage
                    let cap = workspaceStore.index?.workspaces.first(where: { $0.id == wid })?
                        .config?
                        .mcpToolAllowlistPairs(forKey: "mcp_tool_allowlist")
                    rebuildToolSwitches(cap: cap)
                }
            } catch {
                await MainActor.run {
                    toolsRefreshing = false
                    toolsDiscoveryMessage = error.localizedDescription
                }
            }
        }
    }

    private func rebuildToolSwitches(cap: [(String, String)]?) {
        toolSwitchOn = Self.toolSwitchMap(discovered: discoveredTools, capPairs: cap)
    }

    private static func toolSwitchMap(
        discovered: [String: [MCPToolDescriptor]],
        capPairs: [(String, String)]?
    ) -> [String: Bool] {
        let capSet: Set<String>? = capPairs.map { pairs in
            Set(pairs.map { Self.toolKey(server: $0.0, tool: $0.1) })
        }
        var next: [String: Bool] = [:]
        for (srv, pairs) in discovered {
            for p in pairs {
                let key = Self.toolKey(server: srv, tool: p.name)
                if let s = capSet {
                    next[key] = s.contains(key)
                } else {
                    next[key] = true
                }
            }
        }
        return next
    }

    private func browseAvatarPath() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                avatarPath = url.path
            }
        }
    }

    private func browseWorkFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                workFolderPath = url.path
            }
        }
    }

    private func copyWorkspaceShareLink() {
        saveError = nil
        let rec = workspaceStore.index?.workspaces.first(where: { $0.id == workspace.id }) ?? workspace
        do {
            let link = try WorkspaceShareLink.exportBase64URL(rec)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(link, forType: .string)
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func refreshWorkspaceModelList() {
        guard !llmModelsLoading else { return }
        llmModelsLoading = true
        llmModelsMessage = nil
        // Start from the persisted workspace config, then overlay live UI state so unsaved
        // edits to LM Studio URL / API keys / provider / ollama URL are used when probing
        // provider model lists (fixes: empty dropdown in workspace editor when the URL/key
        // was typed but not yet saved — parity with the global Settings dialog which reads
        // its live ConfigYamlDocument).
        let storedCfg = workspaceStore.index?.workspaces.first(where: { $0.id == workspace.id })?.config ?? workspace.config
        var overlay: [String: JSONValue] = {
            if case .object(let dict) = storedCfg { return dict }
            return [:]
        }()

        let trimmedProvider = llmProvider.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedProvider.isEmpty {
            overlay["llm_provider"] = .string(trimmedProvider)
        }

        let trimmedOllama = ollamaUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOllama.isEmpty {
            overlay["ollama_url"] = .string(trimmedOllama)
        }

        let trimmedLmUrl = lmstudioUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLmUrl.isEmpty {
            overlay["lmstudio_url"] = .string(trimmedLmUrl)
        }
        let trimmedLmV1Url = lmstudioV1Url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLmV1Url.isEmpty {
            overlay["lmstudio_v1_url"] = .string(trimmedLmV1Url)
        }

        func applyKey(_ key: String, value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                overlay.removeValue(forKey: key)
            } else {
                overlay[key] = .string(trimmed)
            }
        }
        applyKey("openai_api_key", value: apiKeyOpenAI)
        applyKey("anthropic_api_key", value: apiKeyAnthropic)
        applyKey("openrouter_api_key", value: apiKeyOpenRouter)
        applyKey("cursor_api_key", value: apiKeyCursor)
        applyKey("opencode_zen_api_key", value: apiKeyOpenCodeZen)
        applyKey("lmstudio_api_key", value: apiKeyLMStudio)
        applyKey("lmstudio_v1_api_key", value: apiKeyLMStudioV1)

        let cfg: JSONValue = .object(overlay)
        let user = configStore.snapshot
        let routing = configStore.routingExtras
        Task {
            let secrets = UserConfigLoader.loadSecretsWithKeychainLenient()
            let outcome = await ModelPickerModels.fetchWithDiagnostics(
                workspaceConfig: cfg,
                user: user,
                routing: routing,
                secrets: secrets
            )
            await MainActor.run {
                availableModelsByProvider = outcome.rowsByProvider
                llmModelsLoading = false
                let providerKey = llmProvider.trimmingCharacters(in: .whitespacesAndNewlines)
                let rows = outcome.rowsByProvider[providerKey] ?? []
                let count = rows.count
                // Surface the real probe error when we only have the fallback row (the stored
                // default model id) — otherwise users see "Loaded 1 model suggestion" and
                // assume the LM Studio server is reachable when it is not.
                if let diag = outcome.diagnosticsByProvider[providerKey] {
                    llmModelsMessage = diag
                    llmModelsMessageIsError = true
                } else if count > 0 {
                    llmModelsMessage = "Loaded \(count) model suggestion\(count == 1 ? "" : "s") for \(providerKey)."
                    llmModelsMessageIsError = false
                } else {
                    llmModelsMessage = "No provider-backed suggestions were returned for \(providerKey); manual model entry still works."
                    llmModelsMessageIsError = false
                }
            }
        }
    }

    /// Matches Python `QSpinBox` / `subagents_run_timeout_seconds`: `0` = no timeout; clamped to `0...86400`.
    private static func parseSubagentRunTimeoutSeconds(_ raw: String) -> Int {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return 0 }
        let lower = t.lowercased()
        if lower == "no timeout" || lower == "none" { return 0 }
        var digits = t
        if lower.hasSuffix("s"), t.count > 1 {
            digits = String(t.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let n = Int(digits) {
            return max(0, min(86400, n))
        }
        return 0
    }

    private func save() {
        saveError = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            saveError = "Name is required."
            return
        }
        let tempParsed = Double(temperatureText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "."))
        let maxParsed = Int(maxTokensText.trimmingCharacters(in: .whitespacesAndNewlines))
        let maxCtx = Int(maxContextLength.trimmingCharacters(in: .whitespacesAndNewlines))
        let maxSess = Int(maxSessionMessages.trimmingCharacters(in: .whitespacesAndNewlines))

        var patch: [String: JSONValue] = [:]
        patch["chat_mode"] = .string(chatMode)
        let wf = workFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        patch["work_folder_path"] = wf.isEmpty ? .null : .string(wf)
        patch["llm_provider"] = .string(llmProvider)
        patch["llm_model"] = .string(llmModel)
        patch["ollama_url"] = .string(ollamaUrl)
        patch["lmstudio_url"] = .string(lmstudioUrl)
        patch["lmstudio_v1_url"] = .string(lmstudioV1Url)
        if let t = tempParsed {
            patch["temperature"] = .double(t)
        }
        if let m = maxParsed {
            patch["max_tokens"] = .int(m)
        }
        let sp = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        patch["system_prompt"] = .string(sp)

        patch["use_agents_sdk"] = .bool(useAgentsSdk)
        patch["agents_sdk_max_turns"] = .int(agentsSdkMaxTurns)

        func putOptionalApiKey(_ key: String, _ value: String) {
            let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
            patch[key] = t.isEmpty ? .null : .string(t)
        }
        putOptionalApiKey("openai_api_key", apiKeyOpenAI)
        putOptionalApiKey("anthropic_api_key", apiKeyAnthropic)
        putOptionalApiKey("openrouter_api_key", apiKeyOpenRouter)
        putOptionalApiKey("cursor_api_key", apiKeyCursor)
        putOptionalApiKey("opencode_zen_api_key", apiKeyOpenCodeZen)
        putOptionalApiKey("lmstudio_api_key", apiKeyLMStudio)
        putOptionalApiKey("lmstudio_v1_api_key", apiKeyLMStudioV1)

        patch["memory_enabled"] = .bool(memoryEnabled)
        let mf = memoryFile.trimmingCharacters(in: .whitespacesAndNewlines)
        patch["memory_file"] = mf.isEmpty ? .null : .string(mf)
        if let v = maxCtx { patch["max_context_length"] = .int(v) }
        if let v = maxSess { patch["max_session_messages"] = .int(v) }

        patch["enable_inter_agent"] = .bool(enableInterAgent)
        let iac = interAgentChannel.trimmingCharacters(in: .whitespacesAndNewlines)
        patch["inter_agent_channel"] = iac.isEmpty ? .null : .string(iac)
        patch["use_shared_memory"] = .bool(useSharedMemory)
        patch["swarm_auto_delegate"] = .bool(swarmAutoDelegate)
        patch["swarm_consensus"] = .bool(swarmConsensus)

        patch["subagents_enabled"] = .bool(subagentsEnabled)
        patch["subagents_max_depth"] = .int(subagentsMaxDepth)
        patch["subagents_max_children"] = .int(subagentsMaxChildren)
        patch["subagents_run_timeout_seconds"] = .int(Self.parseSubagentRunTimeoutSeconds(subagentsRunTimeoutField))

        patch["proactive_habits"] = .bool(proactiveHabits)
        patch["proactive_screen"] = .bool(proactiveScreen)
        patch["proactive_autonomy"] = .bool(proactiveAutonomy)
        patch["proactive_autonomy_interval_minutes"] = .int(proactiveAutonomyIntervalMinutes)
        patch["proactive_file_triggers"] = .bool(proactiveFileTriggers)
        patch["enable_folder_watchers"] = .bool(enableFolderWatchers)

        patch["safety_content_filter"] = .bool(safetyContentFilter)
        let al = autonomyLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        if al.isEmpty {
            patch["autonomy_level"] = .null
        } else {
            patch["autonomy_level"] = .string(al)
        }

        if enforceToolAllowlist {
            if discoveredTools.isEmpty {
                let existing = workspaceStore.index?.workspaces.first(where: { $0.id == workspace.id })?
                    .config?
                    .mcpToolAllowlistPairs(forKey: "mcp_tool_allowlist") ?? []
                patch["mcp_tool_allowlist"] = .array(
                    existing.map { .array([.string($0.0), .string($0.1)]) }
                )
            } else {
                var rows: [JSONValue] = []
                for (srv, pairs) in discoveredTools {
                    for p in pairs {
                        let key = Self.toolKey(server: srv, tool: p.name)
                        if toolSwitchOn[key] == true {
                            rows.append(.array([.string(srv), .string(p.name)]))
                        }
                    }
                }
                patch["mcp_tool_allowlist"] = .array(rows)
            }
        } else {
            patch["mcp_tool_allowlist"] = .null
        }

        if workspaceSkillsOverrideEnabled {
            patch["enabled_skills"] = .array(workspaceSkillIDs.map { .string($0) })
        } else {
            patch["enabled_skills"] = .null
        }

        do {
            try workspaceStore.saveWorkspaceFullEditor(
                id: workspace.id,
                name: trimmed,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : description,
                icon: icon,
                color: color,
                avatarPath: avatarPath,
                configPatch: patch
            )
            flashSaveSuccess()
            onSave()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func flashSaveSuccess() {
        saveError = nil
        saveSuccessDismiss?.cancel()
        saveSuccessVisible = true
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        saveSuccessDismiss = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            saveSuccessVisible = false
            saveSuccessDismiss = nil
        }
    }
}
