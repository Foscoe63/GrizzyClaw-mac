import AppKit
import GrizzyClawAgent
import GrizzyClawCore
import GrizzyClawMLX
import Security
import SwiftUI

/// Native `Preferences` window matching Python `SettingsDialog` (`settings_dialog.py`): title, 12 tabs in a 2×6 grid, Save / Close.
public struct PreferencesMainView: View {
    @StateObject private var doc = ConfigYamlDocument()
    @ObservedObject var configStore: ConfigStore
    @ObservedObject var workspaceStore: WorkspaceStore
    @ObservedObject var guiChatPrefs: GuiChatPrefsStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var selectedTab = 0
    @State private var saveButtonTitle = "Save"
    @State private var saveError: String?
    @State private var llmRefreshBusy = false
    @State private var llmFetchOllama: [String]?
    @State private var llmFetchLmStudio: [String]?
    @State private var llmFetchLmV1: [String]?
    @State private var llmFetchOpenAI: [String]?
    @State private var llmFetchAnthropic: [String]?
    @State private var llmFetchOpenRouter: [String]?
    @State private var llmFetchCursor: [String]?
    @State private var llmFetchZen: [String]?
    #if arch(arm64)
    @State private var llmFetchMLX: [String]?
    @State private var mlxDownloadRepoID = ""
    @State private var mlxPrefetchBusy = false
    #endif
    @State private var llmModelFetchAlert: String?
    @State private var telegramTesting = false
    @State private var telegramTestMessage: String?
    @State private var daemonStatusText = "Checking…"
    @State private var daemonGatewayHint = ""
    @State private var daemonBusy = false
    @State private var daemonTimer: Timer?

    private let tabTitles = [
        "General", "LLM Providers", "Telegram", "WhatsApp",
        "Appearance", "Daemon", "Prompts_Rules", "ClawHub",
        "MCP Servers", "Swarm Setup", "Security", "Integrations",
    ]

    public init(configStore: ConfigStore, workspaceStore: WorkspaceStore, guiChatPrefs: GuiChatPrefsStore) {
        self.configStore = configStore
        self.workspaceStore = workspaceStore
        self.guiChatPrefs = guiChatPrefs
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            tabButtonGrid
            Divider()
            Group {
                switch selectedTab {
                case 0: PreferencesGeneralForm(doc: doc)
                case 1: llmTab
                case 2: telegramTab
                case 3: whatsappTab
                case 4: appearanceTab
                case 5: daemonTab
                case 6: promptsTab
                case 7: clawHubTab
                case 8: mcpTab
                case 9: swarmTab
                case 10: securityTab
                case 11: integrationsTab
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footerBar
        }
        .background(PreferencesPanelChromeBackground())
        .preferredColorScheme(AppearanceTheme.resolvedColorScheme(for: doc.string("theme", default: "Light")))
        .tint(PreferencesTheme.accentPurple)
        .frame(minWidth: 700, minHeight: 550)
        .onAppear {
            doc.reload()
            refreshDaemonStatus()
            daemonTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                Task { @MainActor in
                    refreshDaemonStatus()
                }
            }
        }
        .onDisappear {
            daemonTimer?.invalidate()
            daemonTimer = nil
        }
        .alert("GrizzyClaw", isPresented: Binding(
            get: { telegramTestMessage != nil },
            set: { if !$0 { telegramTestMessage = nil } }
        )) {
            Button("OK", role: .cancel) { telegramTestMessage = nil }
        } message: {
            Text(telegramTestMessage ?? "")
        }
        .alert("Models", isPresented: Binding(
            get: { llmModelFetchAlert != nil },
            set: { if !$0 { llmModelFetchAlert = nil } }
        )) {
            Button("OK", role: .cancel) { llmModelFetchAlert = nil }
        } message: {
            Text(llmModelFetchAlert ?? "")
        }
    }

    private var headerBar: some View {
        HStack {
            Text("Preferences")
                .font(.system(size: 18, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }

    private var tabButtonGrid: some View {
        let cols = Array(repeating: GridItem(.flexible(minimum: 80), spacing: 6), count: 6)
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(Array(tabTitles.enumerated()), id: \.offset) { idx, title in
                Button {
                    selectedTab = idx
                } label: {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selectedTab == idx ? PreferencesTheme.tabSelectedFill : Color.clear)
                        )
                        .foregroundStyle(selectedTab == idx ? Color.white : Color.primary.opacity(0.92))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }

    private var footerBar: some View {
        HStack {
            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let err = doc.lastLoadError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button("Close") {
                saveToDisk()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button(saveButtonTitle) {
                saveToDisk(showSavedFeedback: true)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func saveToDisk(showSavedFeedback: Bool = false) {
        saveError = nil
        do {
            try doc.save()
            configStore.reload()
            if showSavedFeedback {
                saveButtonTitle = "Saved!"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    saveButtonTitle = "Save"
                }
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: - Tab 1 LLM

    private var llmTab: some View {
        ScrollView {
            Form {
                Section("Ollama (Local)") {
                    TextField("URL:", text: doc.bindingString("ollama_url", default: "http://localhost:11434"))
                    Text("Default: http://localhost:11434").font(.caption).foregroundStyle(.secondary)
                    LLMModelField(
                        doc: doc,
                        modelKey: "ollama_model",
                        defaultModel: "llama3.2",
                        seeds: [
                            "gpt-oss:20b", "llama3.2", "llama3.2:1b", "llama3.2:3b",
                            "llama3.1", "llama3.1:70b", "llama3.1:405b",
                            "mistral", "mixtral", "codellama",
                            "phi3", "qwen2.5", "gemma2",
                        ],
                        fetched: $llmFetchOllama,
                        isRefreshing: $llmRefreshBusy
                    ) {
                        let r = await ModelListFetch.ollamaTagNames(baseURL: doc.string("ollama_url", default: "http://localhost:11434"))
                        if r.isEmpty {
                            await MainActor.run { llmModelFetchAlert = "No models found for this provider." }
                        }
                        return r
                    }
                    Toggle("Show in Workspace API Keys", isOn: Binding(
                        get: { doc.isWorkspaceProviderEnabled(id: "ollama") },
                        set: { doc.setWorkspaceProviderEnabled(id: "ollama", enabled: $0) }
                    ))
                    .help("If checked, workspaces can override the API key for this provider (Ollama usually does not need one).")
                }

                Section("LM Studio (OpenAI-compatible)") {
                    Text("Provider id: lmstudio — OpenAI-compatible HTTP API at /v1/chat/completions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("URL:", text: doc.bindingString("lmstudio_url", default: "http://localhost:1234/v1"))
                    Text("Default: http://localhost:1234/v1").font(.caption).foregroundStyle(.secondary)
                    LLMModelField(
                        doc: doc,
                        modelKey: "lmstudio_model",
                        defaultModel: "local-model",
                        seeds: ["local-model", "llama-3.2-1b", "llama-3.2-3b", "mistral-7b", "phi-3-mini"],
                        fetched: $llmFetchLmStudio,
                        isRefreshing: $llmRefreshBusy
                    ) {
                        let result = await ModelListFetch.lmStudioOpenAINativeModelFetch(
                            lmstudioOpenAICompatURL: doc.string("lmstudio_url", default: "http://localhost:1234/v1"),
                            apiKey: doc.optionalString("lmstudio_api_key")
                        )
                        if result.ids.isEmpty {
                            await MainActor.run {
                                llmModelFetchAlert = result.diagnostic ?? "No models found for this provider."
                            }
                        }
                        return result.ids
                    }
                    SecureField("API Key:", text: doc.bindingOptionalStringNull("lmstudio_api_key"))
                        .textContentType(.password)
                    Text("Optional — for remote LM Studio or proxy auth").font(.caption).foregroundStyle(.secondary)
                    Text("Click Save at the bottom for chat to use this URL and model.")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                    Toggle("Show in Workspace API Keys", isOn: Binding(
                        get: { doc.isWorkspaceProviderEnabled(id: "lmstudio") },
                        set: { doc.setWorkspaceProviderEnabled(id: "lmstudio", enabled: $0) }
                    ))
                    .help("If checked, workspaces can override the API key for this provider (LM Studio usually does not need one).")
                }

                Section("LM Studio v1 (native API)") {
                    Text("Provider id: lmstudio_v1 — native REST (POST /api/v1/chat), stateful chat, MCP via LM Studio integrations. Distinct from OpenAI-compatible lmstudio above.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Enable LM Studio v1 API", isOn: doc.bindingBool("lmstudio_v1_enabled", default: false))
                        .help("When enabled, \"lmstudio_v1\" appears in Default Provider.")
                    TextField("Base URL:", text: doc.bindingString("lmstudio_v1_url", default: "http://localhost:1234"))
                    LLMModelField(
                        doc: doc,
                        modelKey: "lmstudio_v1_model",
                        defaultModel: "",
                        seeds: ["", "openai/gpt-oss-20b", "ibm/granite-4-micro", "qwen/qwen3-vl-4b"],
                        fetched: $llmFetchLmV1,
                        isRefreshing: $llmRefreshBusy
                    ) {
                        let result = await ModelListFetch.lmStudioV1ModelFetch(
                            base: doc.string("lmstudio_v1_url", default: "http://localhost:1234"),
                            apiKey: doc.optionalString("lmstudio_v1_api_key")
                        )
                        if result.ids.isEmpty {
                            await MainActor.run {
                                llmModelFetchAlert = result.diagnostic ?? "No models found for this provider."
                            }
                        }
                        return result.ids
                    }
                    SecureField("API Key:", text: doc.bindingOptionalStringNull("lmstudio_v1_api_key"))
                        .textContentType(.password)
                    Text("Optional — for remote LM Studio v1 or proxy auth").font(.caption).foregroundStyle(.secondary)
                    Toggle("Show in Workspace API Keys", isOn: Binding(
                        get: { doc.isWorkspaceProviderEnabled(id: "lmstudio_v1") },
                        set: { doc.setWorkspaceProviderEnabled(id: "lmstudio_v1", enabled: $0) }
                    ))
                    .help("If checked, workspaces get a field to override the API key for LM Studio v1.")
                    TextField("MCP plugins:", text: doc.bindingOptionalStringNull("lmstudio_v1_mcp_plugins"))
                    Text("e.g. ddg-search, filesystem (comma-separated server labels from LM Studio mcp.json)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("OpenAI") {
                    SecureField("API Key:", text: doc.bindingOptionalStringNull("openai_api_key"))
                        .textContentType(.password)
                    Text("From platform.openai.com").font(.caption).foregroundStyle(.secondary)
                    LLMModelField(
                        doc: doc,
                        modelKey: "openai_model",
                        defaultModel: "gpt-4o",
                        seeds: ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4", "gpt-3.5-turbo"],
                        fetched: $llmFetchOpenAI,
                        isRefreshing: $llmRefreshBusy
                    ) {
                        let key = doc.optionalString("openai_api_key")
                        if key.isEmpty {
                            await MainActor.run { llmModelFetchAlert = "Please enter your OpenAI API key first." }
                            return []
                        }
                        let r = await ModelListFetch.openAIStyleModelIds(baseURL: "https://api.openai.com/v1", apiKey: key)
                        if r.isEmpty {
                            await MainActor.run { llmModelFetchAlert = "No models found for this provider." }
                        }
                        return r
                    }
                    Toggle("Show in Workspace API Keys", isOn: Binding(
                        get: { doc.isWorkspaceProviderEnabled(id: "openai") },
                        set: { doc.setWorkspaceProviderEnabled(id: "openai", enabled: $0) }
                    ))
                    .help("If checked, workspaces get a field to override the API key for this provider.")
                }

                Section("Anthropic") {
                    SecureField("API Key:", text: doc.bindingOptionalStringNull("anthropic_api_key"))
                        .textContentType(.password)
                    Text("From console.anthropic.com").font(.caption).foregroundStyle(.secondary)
                    LLMModelField(
                        doc: doc,
                        modelKey: "anthropic_model",
                        defaultModel: "claude-sonnet-4-5-20250929",
                        seeds: [
                            "claude-sonnet-4-5-20250929", "claude-opus-4-6",
                            "claude-sonnet-4-20250514", "claude-haiku-4-5-20251001",
                            "claude-opus-4-5-20251101", "claude-opus-4-20250514",
                        ],
                        fetched: $llmFetchAnthropic,
                        isRefreshing: $llmRefreshBusy
                    ) {
                        let r = ModelListFetch.anthropicCuratedModelIds()
                        if r.isEmpty {
                            await MainActor.run { llmModelFetchAlert = "No models found for this provider." }
                        }
                        return r
                    }
                    Toggle("Show in Workspace API Keys", isOn: Binding(
                        get: { doc.isWorkspaceProviderEnabled(id: "anthropic") },
                        set: { doc.setWorkspaceProviderEnabled(id: "anthropic", enabled: $0) }
                    ))
                    .help("If checked, workspaces get a field to override the API key for this provider.")
                }

                Section("OpenRouter") {
                    SecureField("API Key:", text: doc.bindingOptionalStringNull("openrouter_api_key"))
                        .textContentType(.password)
                    Text("From openrouter.ai").font(.caption).foregroundStyle(.secondary)
                    LLMModelField(
                        doc: doc,
                        modelKey: "openrouter_model",
                        defaultModel: "openai/gpt-4o",
                        seeds: [
                            "openai/gpt-4o", "openai/gpt-4o-mini",
                            "anthropic/claude-3.5-sonnet", "anthropic/claude-3-opus",
                            "google/gemini-pro-1.5", "meta-llama/llama-3.1-70b-instruct",
                        ],
                        fetched: $llmFetchOpenRouter,
                        isRefreshing: $llmRefreshBusy
                    ) {
                        let key = doc.optionalString("openrouter_api_key")
                        if key.isEmpty {
                            await MainActor.run { llmModelFetchAlert = "Please enter your OpenRouter API key first." }
                            return []
                        }
                        let r = await ModelListFetch.openRouterModelIds(apiKey: key)
                        if r.isEmpty {
                            await MainActor.run { llmModelFetchAlert = "No models found for this provider." }
                        }
                        return r
                    }
                    Toggle("Show in Workspace API Keys", isOn: Binding(
                        get: { doc.isWorkspaceProviderEnabled(id: "openrouter") },
                        set: { doc.setWorkspaceProviderEnabled(id: "openrouter", enabled: $0) }
                    ))
                    .help("If checked, workspaces get a field to override the API key for this provider.")
                }

                Section("Cursor") {
                    SecureField("API Key:", text: doc.bindingOptionalStringNull("cursor_api_key"))
                        .textContentType(.password)
                    TextField("URL:", text: doc.bindingString("cursor_url", default: ""))
                    LLMModelField(
                        doc: doc,
                        modelKey: "cursor_model",
                        defaultModel: "gpt-4o",
                        seeds: ["gpt-4o", "gpt-4o-mini", "cursor-default", "claude-3.5-sonnet"],
                        fetched: $llmFetchCursor,
                        isRefreshing: $llmRefreshBusy
                    ) {
                        let key = doc.optionalString("cursor_api_key")
                        let base = doc.string("cursor_url", default: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if key.isEmpty {
                            await MainActor.run { llmModelFetchAlert = "Enter API key and base URL first." }
                            return []
                        }
                        if base.isEmpty {
                            await MainActor.run { llmModelFetchAlert = "Enter an OpenAI-compatible base URL (e.g. https://api.openai.com/v1)." }
                            return []
                        }
                        let r = await ModelListFetch.openAIStyleModelIds(baseURL: base, apiKey: key)
                        if r.isEmpty {
                            await MainActor.run { llmModelFetchAlert = "No models found for this provider." }
                        }
                        return r
                    }
                    Text("api.cursor.com/v1 does not provide chat (returns 404). Use an OpenAI-compatible base URL, e.g. https://api.openai.com/v1 with an OpenAI key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Show in Workspace API Keys", isOn: Binding(
                        get: { doc.isWorkspaceProviderEnabled(id: "cursor") },
                        set: { doc.setWorkspaceProviderEnabled(id: "cursor", enabled: $0) }
                    ))
                    .help("If checked, workspaces get a field to override the API key for this provider.")
                }

                Section("OpenCode Zen (hosted)") {
                    Text("API base: https://opencode.ai/zen/v1 — models: /models")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("API Key:", text: doc.bindingOptionalStringNull("opencode_zen_api_key"))
                        .textContentType(.password)
                    Text("Zen API key (from OpenCode /connect or opencode.ai)").font(.caption).foregroundStyle(.secondary)
                    LLMModelField(
                        doc: doc,
                        modelKey: "opencode_zen_model",
                        defaultModel: "big-pickle",
                        seeds: ["big-pickle", "claude-sonnet-4-5", "gpt-5.3-codex", "minimax-m2.5-free", "glm-5"],
                        fetched: $llmFetchZen,
                        isRefreshing: $llmRefreshBusy
                    ) {
                        let key = doc.optionalString("opencode_zen_api_key")
                        if key.isEmpty {
                            await MainActor.run { llmModelFetchAlert = "Enter your OpenCode Zen API key first." }
                            return []
                        }
                        let r = await ModelListFetch.opencodeZenModelIds(apiKey: key)
                        if r.isEmpty {
                            await MainActor.run { llmModelFetchAlert = "No models found for this provider." }
                        }
                        return r
                    }
                    Text("Uses POST …/chat/completions (OpenAI-compatible). Best for models documented on that route (e.g. big-pickle, glm-5, minimax). Some Zen models use /responses or /messages only — those may not work here yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("Zen docs", destination: URL(string: "https://opencode.ai/docs/zen/")!)
                    Toggle("Show in Workspace API Keys", isOn: Binding(
                        get: { doc.isWorkspaceProviderEnabled(id: "opencode_zen") },
                        set: { doc.setWorkspaceProviderEnabled(id: "opencode_zen", enabled: $0) }
                    ))
                    .help("If checked, workspaces can override the Zen API key.")
                }

                #if arch(arm64)
                Section("MLX (on-device, Apple silicon)") {
                    Text("Provider id: mlx — Hugging Face Hub downloads via mlx-swift-lm; weights live under the directory below (typically models/… per HubApi, or hub/… for Python-style cache).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline) {
                        TextField("Models directory (empty = default)", text: doc.bindingString("mlx_models_directory", default: ""))
                        Button("Choose…") { pickMLXModelsDirectory() }
                    }
                    Text("Default: \(GrizzyClawPaths.mlxModelsDirectory.path)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Revision / branch:", text: doc.bindingString("mlx_revision", default: "main"))
                    LLMModelField(
                        doc: doc,
                        modelKey: "mlx_model",
                        defaultModel: "mlx-community/Llama-3.2-3B-Instruct-4bit",
                        seeds: [
                            "mlx-community/Llama-3.2-3B-Instruct-4bit",
                            "mlx-community/Qwen3-4B-4bit",
                        ],
                        fetched: $llmFetchMLX,
                        isRefreshing: $llmRefreshBusy
                    ) {
                        let path = doc.optionalString("mlx_models_directory")
                        let root: URL
                        do {
                            root = try GrizzyClawPaths.mlxDownloadRoot(userConfiguredPath: path.isEmpty ? nil : path)
                        } catch {
                            await MainActor.run { llmModelFetchAlert = error.localizedDescription }
                            return []
                        }
                        let ids = MLXHubInstalledModels.listRepoIds(downloadRoot: root)
                        if ids.isEmpty {
                            await MainActor.run {
                                llmModelFetchAlert = "No cached models under models/ or hub/ yet. Use Download or send a chat to fetch weights."
                            }
                        }
                        return ids
                    }
                    HStack(alignment: .firstTextBaseline) {
                        TextField("Hugging Face repo id to download", text: $mlxDownloadRepoID)
                            .textFieldStyle(.roundedBorder)
                        Button(mlxPrefetchBusy ? "Downloading…" : "Download") {
                            Task { await runMLXPrefetchFromPreferences() }
                        }
                        .disabled(mlxPrefetchBusy)
                    }
                    .help("Downloads / verifies weights for the given repo id using the revision above.")
                    Toggle("Show in Workspace API Keys", isOn: Binding(
                        get: { doc.isWorkspaceProviderEnabled(id: "mlx") },
                        set: { doc.setWorkspaceProviderEnabled(id: "mlx", enabled: $0) }
                    ))
                    .help("Usually unchecked — MLX has no API key; enables workspace-specific overrides if you add them later.")
                }
                #endif

                Section("Custom Provider") {
                    TextField("Name:", text: doc.bindingString("custom_provider_name", default: "custom"))
                    Text("This name will appear in the workspace LLM provider list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("URL:", text: doc.bindingOptionalStringNull("custom_provider_url"))
                    Text("Base URL for the API endpoint").font(.caption).foregroundStyle(.secondary)
                    SecureField("API Key:", text: doc.bindingOptionalStringNull("custom_provider_api_key"))
                        .textContentType(.password)
                    TextField("Model", text: doc.bindingString("custom_provider_model", default: ""))
                    Toggle("Show in Workspace API Keys", isOn: Binding(
                        get: { doc.isCustomWorkspaceProviderEnabled() },
                        set: { doc.setCustomWorkspaceProviderEnabled($0) }
                    ))
                    .help("If checked, workspaces get a field to override the API key for this provider.")
                }
            }
            .formStyle(.grouped)
            .padding()
        }
    }

    #if arch(arm64)
    private func pickMLXModelsDirectory() {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        p.prompt = "Choose Folder"
        if p.runModal() == .OK, let url = p.url {
            doc.set("mlx_models_directory", value: url.path)
        }
    }

    private func runMLXPrefetchFromPreferences() async {
        let repo = mlxDownloadRepoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repo.isEmpty else {
            await MainActor.run {
                llmModelFetchAlert = "Enter a Hugging Face repo id (e.g. mlx-community/…)."
            }
            return
        }
        await MainActor.run { mlxPrefetchBusy = true }
        defer {
            Task { @MainActor in mlxPrefetchBusy = false }
        }
        do {
            let path = await MainActor.run { doc.optionalString("mlx_models_directory") }
            let rev = await MainActor.run { doc.string("mlx_revision", default: "main") }
            let root = try GrizzyClawPaths.mlxDownloadRoot(userConfiguredPath: path.isEmpty ? nil : path)
            try await MLXModelPrefetch.prefetch(downloadBase: root, modelId: repo, revision: rev) { _ in }
            let ids = MLXHubInstalledModels.listRepoIds(downloadRoot: root)
            await MainActor.run {
                llmFetchMLX = ids
                doc.set("mlx_model", value: repo)
            }
        } catch {
            await MainActor.run { llmModelFetchAlert = error.localizedDescription }
        }
    }
    #endif

    // MARK: - Tab 2 Telegram

    private var telegramTab: some View {
        ScrollView {
            Form {
                SecureField("Bot Token:", text: doc.bindingOptionalStringNull("telegram_bot_token"))
                Text("Get from @BotFather on Telegram").font(.caption).foregroundStyle(.secondary)
                TextField("Webhook URL:", text: doc.bindingOptionalStringNull("telegram_webhook_url"))
                Text("Leave empty for polling mode").font(.caption).foregroundStyle(.secondary)
                TextField("Proxy (optional):", text: doc.bindingOptionalStringNull("telegram_proxy"))
                Text("Config: \(GrizzyClawPaths.configYAML.path)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button("Test Connection") {
                    testTelegram()
                }
                .disabled(telegramTesting)
            }
            .formStyle(.grouped)
            .padding()
        }
    }

    private func testTelegram() {
        let raw = doc.string("telegram_bot_token", default: "")
        guard let token = PreferencesTelegramSanitizer.sanitizeToken(raw), !token.isEmpty else {
            telegramTestMessage = "Please enter a bot token"
            return
        }
        telegramTesting = true
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/getMe") else {
            telegramTesting = false
            telegramTestMessage = "Invalid token URL"
            return
        }
        Task {
            do {
                let (data, resp) = try await URLSession.shared.data(from: url)
                await MainActor.run {
                    telegramTesting = false
                    if let http = resp as? HTTPURLResponse, http.statusCode == 200,
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let ok = obj["ok"] as? Bool, ok,
                       let res = obj["result"] as? [String: Any],
                       let user = res["username"] as? String {
                        telegramTestMessage = "Connected successfully as @\(user)"
                    } else {
                        let s = String(data: data, encoding: .utf8) ?? ""
                        telegramTestMessage = "Could not connect: \(s.prefix(300))"
                    }
                }
            } catch {
                await MainActor.run {
                    telegramTesting = false
                    telegramTestMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Tab 3 WhatsApp

    private var whatsappTab: some View {
        ScrollView {
            Form {
                TextField("Session Path:", text: doc.bindingString("whatsapp_session_path", default: "~/.grizzyclaw/whatsapp_session"))
                Text("Directory to store WhatsApp session data (~ expands to home)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Test Connection") {
                    telegramTestMessage = "WhatsApp session path configured"
                }
            }
            .formStyle(.grouped)
            .padding()
        }
    }

    // MARK: - Tab 4 Appearance

    private var appearanceTab: some View {
        ScrollView {
            Form {
                Section("Theme") {
                    Picker("Color Theme:", selection: doc.bindingString("theme", default: "Light")) {
                        Text("Light").tag("Light")
                        Text("Dark").tag("Dark")
                        Text("Auto (System)").tag("Auto (System)")
                        Text("High Contrast Light").tag("High Contrast Light")
                        Text("High Contrast Dark").tag("High Contrast Dark")
                        Text("Nord").tag("Nord")
                        Text("Solarized Light").tag("Solarized Light")
                        Text("Solarized Dark").tag("Solarized Dark")
                        Text("Dracula").tag("Dracula")
                        Text("Monokai").tag("Monokai")
                    }
                }
                Section("Typography") {
                    Picker("Font Family:", selection: doc.bindingString("font_family", default: "System Default")) {
                        Text("System Default").tag("System Default")
                        Text("SF Pro").tag("SF Pro")
                        Text("Helvetica").tag("Helvetica")
                        Text("Arial").tag("Arial")
                        Text("Inter").tag("Inter")
                    }
                    Stepper(value: doc.bindingInt("font_size", default: 13), in: 10...20) {
                        Text("Base Font Size: \(doc.int("font_size", default: 13))")
                    }
                }
                Section("UI Density") {
                    Toggle("Enable Compact Mode", isOn: doc.bindingBool("compact_mode", default: false))
                }
            }
            .formStyle(.grouped)
            .padding()
        }
    }

    // MARK: - Tab 5 Daemon

    private var daemonTab: some View {
        ScrollView {
            Form {
                Section("Background Daemon") {
                    LabeledContent("Status:", value: daemonStatusText)
                    if !daemonGatewayHint.isEmpty {
                        LabeledContent("Gateway:", value: daemonGatewayHint)
                    }
                    HStack {
                        Button("Start Daemon") {
                            startDaemonCLI()
                        }
                        .disabled(
                            daemonBusy || FileManager.default.fileExists(atPath: GrizzyClawPaths.daemonSocket.path)
                        )
                        Button("Stop Daemon") {
                            stopDaemonCLI()
                        }
                        .disabled(
                            daemonBusy || !FileManager.default.fileExists(atPath: GrizzyClawPaths.daemonSocket.path)
                        )
                        if daemonBusy {
                            ProgressView().controlSize(.small)
                        }
                    }
                    Button("Open daemon log in Finder…") {
                        GrizzyClawShell.revealInFinder(GrizzyClawPaths.daemonStderrLog)
                    }
                    .disabled(!FileManager.default.fileExists(atPath: GrizzyClawPaths.daemonStderrLog.path))
                    Text(
                        "Uses `grizzyclaw` on your PATH (same as the Python install). "
                            + "The daemon runs Gateway (WebSocket), webhooks, and IPC. "
                            + "WebChat: http://127.0.0.1:18788/chat. "
                            + "If start fails, check the log file or run `grizzyclaw daemon run` in a terminal."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding()
        }
    }

    private func refreshDaemonStatus() {
        let sock = GrizzyClawPaths.daemonSocket.path
        let socketPresent = FileManager.default.fileExists(atPath: sock)
        if !socketPresent {
            daemonStatusText = "Stopped (no socket)"
            daemonGatewayHint = ""
            return
        }
        daemonStatusText = "Socket present"
        Task {
            let r = await GatewaySessionsClient.fetchSessions()
            await MainActor.run {
                switch r {
                case .success(let rows):
                    daemonStatusText = "Running"
                    daemonGatewayHint = "Gateway OK · \(rows.count) session(s) listed"
                case .failure(let err):
                    daemonGatewayHint = err.message
                    daemonStatusText = "Socket present (daemon starting or gateway error)"
                }
            }
        }
    }

    private func startDaemonCLI() {
        daemonBusy = true
        daemonGatewayHint = ""
        do {
            try GrizzyClawDaemonProcess.launchGrizzyClawDaemon(arguments: ["daemon", "run"])
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                daemonBusy = false
                refreshDaemonStatus()
            }
        } catch {
            daemonBusy = false
            telegramTestMessage =
                "Could not start daemon: \(error.localizedDescription)\nEnsure `grizzyclaw` is on PATH."
        }
    }

    private func stopDaemonCLI() {
        daemonBusy = true
        do {
            try GrizzyClawDaemonProcess.launchGrizzyClawDaemon(arguments: ["daemon", "stop"])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                daemonBusy = false
                refreshDaemonStatus()
            }
        } catch {
            daemonBusy = false
            telegramTestMessage = "Could not stop daemon: \(error.localizedDescription)"
        }
    }

    // MARK: - Tab 6 Prompts

    private var promptsTab: some View {
        ScrollView {
            Form {
                TextEditor(text: doc.bindingString("system_prompt", default: ""))
                    .frame(minHeight: 200)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                Text("System Prompt").font(.caption).foregroundStyle(.secondary)
                TextField("Rules File:", text: doc.bindingOptionalStringNull("rules_file"))
                Picker("Agent Tone:", selection: doc.bindingString("agent_tone", default: "")) {
                    Text("(none)").tag("")
                    Text("formal").tag("formal")
                    Text("casual").tag("casual")
                    Text("minimal").tag("minimal")
                }
                Toggle("Enable daily morning brief (summary from memory)", isOn: doc.bindingBool("morning_brief_enabled", default: false))
                TextField("Morning Brief Time:", text: doc.bindingString("morning_brief_time", default: "07:00"))
                Button("Preview") {
                    telegramTestMessage = "System prompt loaded successfully."
                }
            }
            .formStyle(.grouped)
            .padding()
        }
    }

    // MARK: - Tab 7 ClawHub

    private var clawHubTab: some View {
        ClawHubPreferencesView(doc: doc)
    }

    // MARK: - Tab 8 MCP

    private var mcpTab: some View {
        MCPServersPreferencesView(doc: doc, guiChatPrefs: guiChatPrefs)
    }

    // MARK: - Tab 9 Swarm

    private var swarmTab: some View {
        SwarmSetupPreferencesView(workspaceStore: workspaceStore)
    }

    // MARK: - Tab 10 Security

    private var securityTab: some View {
        ScrollView {
            Form {
                Text("⚠️  Changes require restart")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                Section("Security") {
                    SecureField("Secret Key:", text: doc.bindingString("secret_key", default: ""))
                    SecureField("JWT Secret:", text: doc.bindingString("jwt_secret", default: ""))
                    Stepper(value: doc.bindingInt("rate_limit_requests", default: 60), in: 10...1000) {
                        Text("Rate Limit: \(doc.int("rate_limit_requests", default: 60))")
                    }
                    Toggle("Allow shell commands", isOn: doc.bindingBool("exec_commands_enabled", default: false))
                    Toggle("Skip approval for safe commands (ls, df, pwd, whoami, date, etc.)", isOn: doc.bindingBool("exec_safe_commands_skip_approval", default: true))
                    Toggle("Run approved commands in sandbox (restricted PATH)", isOn: doc.bindingBool("exec_sandbox_enabled", default: false))
                    Toggle("Check LLM provider before sending", isOn: doc.bindingBool("pre_send_health_check", default: false))
                }
                Button("Generate New Keys") {
                    doc.set("secret_key", value: Self.randomToken())
                    doc.set("jwt_secret", value: Self.randomToken())
                }
            }
            .formStyle(.grouped)
            .padding()
        }
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    // MARK: - Tab 11 Integrations

    private var integrationsTab: some View {
        ScrollView {
            Form {
                Section("Gateway & Message Queue") {
                    SecureField("Gateway Auth Token:", text: doc.bindingOptionalStringNull("gateway_auth_token"))
                    Stepper(value: doc.bindingInt("gateway_rate_limit_requests", default: 60), in: 10...1000) {
                        Text("Rate limit (req/window): \(doc.int("gateway_rate_limit_requests", default: 60))")
                    }
                    Stepper(value: doc.bindingInt("gateway_rate_limit_window", default: 60), in: 10...3600) {
                        Text("Rate window (seconds): \(doc.int("gateway_rate_limit_window", default: 60))")
                    }
                    Toggle("Enable message queue (serialize per session)", isOn: doc.bindingBool("queue_enabled", default: false))
                    Stepper(value: doc.bindingInt("queue_max_per_session", default: 50), in: 1...1000) {
                        Text("Queue max per session: \(doc.int("queue_max_per_session", default: 50))")
                    }
                }
                Section("Media & Transcription") {
                    Picker("Transcription Provider:", selection: doc.bindingString("transcription_provider", default: "openai")) {
                        Text("openai").tag("openai")
                        Text("local").tag("local")
                    }
                    TextField("Microphone / input device name (optional)", text: doc.bindingOptionalStringNull("input_device_name"))
                    Stepper(value: doc.bindingInt("media_retention_days", default: 7), in: 1...365) {
                        Text("Media Retention (days): \(doc.int("media_retention_days", default: 7))")
                    }
                    Stepper(value: doc.bindingInt("media_max_size_mb", default: 0), in: 0...10_000) {
                        Text("Media max size (MB, 0=unlimited): \(doc.int("media_max_size_mb", default: 0))")
                    }
                }
                Section("Voice (TTS)") {
                    SecureField("ElevenLabs API Key:", text: doc.bindingOptionalStringNull("elevenlabs_api_key"))
                    TextField("Voice ID:", text: doc.bindingString("elevenlabs_voice_id", default: "21m00Tcm4TlvDq8ikWAM"))
                    Picker("TTS Provider:", selection: doc.bindingString("tts_provider", default: "auto")) {
                        Text("auto").tag("auto")
                        Text("elevenlabs").tag("elevenlabs")
                        Text("pyttsx3").tag("pyttsx3")
                        Text("say").tag("say")
                    }
                }
                Section("Gmail Pub/Sub") {
                    TextField("Credentials JSON:", text: doc.bindingOptionalStringNull("gmail_credentials_json"))
                    TextField("Pub/Sub Topic:", text: doc.bindingOptionalStringNull("gmail_pubsub_topic"))
                    TextField("Audience URL:", text: doc.bindingOptionalStringNull("gmail_pubsub_audience"))
                }
                Section("Automation Triggers") {
                    Text(
                        "Rules live in ~/.grizzyclaw/triggers.json. The Python agent daemon loads them; "
                            + "events include message, webhook, schedule, file_change, and git_event."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Button("Manage Triggers…") {
                        openWindow(id: "triggers")
                    }
                    Button("Reveal triggers.json in Finder…") {
                        GrizzyClawShell.revealInFinder(GrizzyClawPaths.triggersJSON)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
    }
}

private enum PreferencesTelegramSanitizer {
    static func sanitizeToken(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        if trimmed.isEmpty { return nil }
        let pattern = #"\d+:[A-Za-z0-9_-]{20,}"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return trimmed }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        if let m = re.firstMatch(in: trimmed, range: range), let r = Range(m.range, in: trimmed) {
            return String(trimmed[r])
        }
        return trimmed
    }
}
