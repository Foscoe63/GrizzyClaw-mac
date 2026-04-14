import Foundation
import GrizzyClawCore

/// Per-provider model rows for the chat composer picker (Python `ModelListWorker` + `ModelSelectorPopup.rebuild`).
public enum ModelPickerModels: Sendable {
    public struct Row: Identifiable, Hashable, Sendable {
        public let modelId: String
        public let displayName: String
        public var id: String { modelId }

        public init(modelId: String, displayName: String) {
            self.modelId = modelId
            self.displayName = displayName
        }
    }

    /// Workspace YAML API key override, else value from keychain snapshot (Python `workspace_api_key_providers` parity).
    private static func workspaceOrGlobalApiKey(
        cfg: JSONValue?,
        secrets: UserConfigSecrets,
        workspaceKey: String,
        global: String?
    ) -> String? {
        if let s = cfg?.string(forKey: workspaceKey), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
        return global.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    /// Fetches model lists for all built-in providers; empty fetch falls back to the default model id (Python `provider_models`).
    ///
    /// **Concurrency:** Probes run **in parallel** so a dead Ollama (`:11434`) does not delay LM Studio (`:1234`) in the chat toolbar.
    ///
    /// **Ollama:** Live `GET /api/tags` runs only when the effective default LLM provider is `ollama` (workspace `llm_provider` or global `default_llm_provider`). Otherwise the Ollama section shows the configured `ollama_model` only — avoids connection refused spam to `:11434` when you use LM Studio or other providers.
    public static func fetch(
        workspaceConfig cfg: JSONValue?,
        user: UserConfigSnapshot,
        routing: RoutingExtras,
        secrets: UserConfigSecrets
    ) async -> [String: [Row]] {
        let anthropic = anthropicCuratedRows()

        async let ollama = ollamaRows(cfg: cfg, user: user)
        async let lmstudio = lmstudioRows(cfg: cfg, user: user, secrets: secrets)
        async let lmstudioV1 = lmstudioV1Rows(cfg: cfg, user: user, secrets: secrets)
        async let openai = openaiRows(cfg: cfg, user: user, secrets: secrets)
        async let openrouter = openrouterRows(cfg: cfg, routing: routing, secrets: secrets)
        async let opencodeZen = opencodeZenRows(cfg: cfg, routing: routing, secrets: secrets)
        async let cursor = cursorRows(cfg: cfg, routing: routing, secrets: secrets)
        async let mlx = mlxRows(cfg: cfg, user: user)
        async let custom = customRows(cfg: cfg, user: user, secrets: secrets)

        var out: [String: [Row]] = [:]
        out["ollama"] = await ollama
        out["lmstudio"] = await lmstudio
        out["lmstudio_v1"] = await lmstudioV1
        out["openai"] = await openai
        out["anthropic"] = anthropic
        out["openrouter"] = await openrouter
        out["opencode_zen"] = await opencodeZen
        out["cursor"] = await cursor
        out["mlx"] = await mlx
        out["custom"] = await custom
        return out
    }

    private static func anthropicCuratedRows() -> [Row] {
        ModelListFetch.anthropicCuratedModelIds().map { Row(modelId: $0, displayName: $0) }
    }

    /// Workspace `llm_provider` overrides global default (parity with ``ResolvedChatParameters``).
    private static func effectiveDefaultLlmProvider(cfg: JSONValue?, user: UserConfigSnapshot) -> String {
        let ws = cfg?.string(forKey: "llm_provider")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !ws.isEmpty { return ws }
        return user.defaultLlmProvider.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Live Ollama discovery hits `localhost:11434`; skip when the user is not on Ollama to avoid CFNetwork errors if Ollama is not installed.
    private static func shouldProbeOllamaLiveModelList(cfg: JSONValue?, user: UserConfigSnapshot) -> Bool {
        effectiveDefaultLlmProvider(cfg: cfg, user: user).lowercased() == "ollama"
    }

    private static func ollamaRows(cfg: JSONValue?, user: UserConfigSnapshot) async -> [Row] {
        guard shouldProbeOllamaLiveModelList(cfg: cfg, user: user) else {
            return [user.ollamaModel].map { Row(modelId: $0, displayName: $0) }
        }
        let base = cfg?.string(forKey: "ollama_url") ?? user.ollamaUrl
        var ids = await ModelListFetch.ollamaTagNames(baseURL: base)
        if ids.isEmpty { ids = [user.ollamaModel] }
        return ids.map { Row(modelId: $0, displayName: $0) }
    }

    private static func lmstudioRows(cfg: JSONValue?, user: UserConfigSnapshot, secrets: UserConfigSecrets) async -> [Row] {
        let base: String = {
            if let s = cfg?.string(forKey: "lmstudio_url"),
               !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
            return user.lmstudioUrl
        }()
        let key = workspaceOrGlobalApiKey(cfg: cfg, secrets: secrets, workspaceKey: "lmstudio_api_key", global: secrets.lmstudioApiKey)
        var ids = await ModelListFetch.lmStudioOpenAINativeModelIds(lmstudioOpenAICompatURL: base, apiKey: key)
        if ids.isEmpty { ids = [user.lmstudioModel] }
        return ids.map { Row(modelId: $0, displayName: $0) }
    }

    private static func lmstudioV1Rows(cfg: JSONValue?, user: UserConfigSnapshot, secrets: UserConfigSecrets) async -> [Row] {
        let raw: String = {
            if let s = cfg?.string(forKey: "lmstudio_v1_url"),
               !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
            return user.lmstudioV1Url
        }()
        let norm = ChatParameterResolver.normalizeLmStudioV1Base(raw)
        let key = workspaceOrGlobalApiKey(cfg: cfg, secrets: secrets, workspaceKey: "lmstudio_v1_api_key", global: secrets.lmstudioV1ApiKey)
        var ids = await ModelListFetch.lmStudioV1ModelIds(base: norm, apiKey: key)
        if ids.isEmpty { ids = [user.lmstudioModel] }
        return ids.map { Row(modelId: $0, displayName: $0) }
    }

    private static func openaiRows(cfg: JSONValue?, user: UserConfigSnapshot, secrets: UserConfigSecrets) async -> [Row] {
        if let key = workspaceOrGlobalApiKey(cfg: cfg, secrets: secrets, workspaceKey: "openai_api_key", global: secrets.openaiApiKey) {
            var ids = await ModelListFetch.openAIStyleModelIds(baseURL: "https://api.openai.com/v1", apiKey: key)
            if ids.isEmpty { ids = [user.openaiModel] }
            return ids.map { Row(modelId: $0, displayName: $0) }
        }
        return [user.openaiModel].map { Row(modelId: $0, displayName: $0) }
    }

    private static func openrouterRows(cfg: JSONValue?, routing: RoutingExtras, secrets: UserConfigSecrets) async -> [Row] {
        if let key = workspaceOrGlobalApiKey(cfg: cfg, secrets: secrets, workspaceKey: "openrouter_api_key", global: secrets.openrouterApiKey) {
            var ids = await ModelListFetch.openRouterModelIds(apiKey: key)
            if ids.isEmpty { ids = [routing.openrouterModel] }
            return ids.map { Row(modelId: $0, displayName: $0) }
        }
        return [routing.openrouterModel].map { Row(modelId: $0, displayName: $0) }
    }

    private static func opencodeZenRows(cfg: JSONValue?, routing: RoutingExtras, secrets: UserConfigSecrets) async -> [Row] {
        if let key = workspaceOrGlobalApiKey(cfg: cfg, secrets: secrets, workspaceKey: "opencode_zen_api_key", global: secrets.opencodeZenApiKey) {
            var ids = await ModelListFetch.opencodeZenModelIds(apiKey: key)
            if ids.isEmpty { ids = [routing.opencodeZenModel] }
            return ids.map { Row(modelId: $0, displayName: $0) }
        }
        return [routing.opencodeZenModel].map { Row(modelId: $0, displayName: $0) }
    }

    private static func cursorRows(cfg: JSONValue?, routing: RoutingExtras, secrets: UserConfigSecrets) async -> [Row] {
        let url = routing.cursorUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key = workspaceOrGlobalApiKey(cfg: cfg, secrets: secrets, workspaceKey: "cursor_api_key", global: secrets.cursorApiKey), !url.isEmpty {
            var ids = await ModelListFetch.openAIStyleModelIds(baseURL: url, apiKey: key)
            if ids.isEmpty { ids = [routing.cursorModel] }
            return ids.map { Row(modelId: $0, displayName: $0) }
        }
        return [routing.cursorModel].map { Row(modelId: $0, displayName: $0) }
    }

    private static func mlxRows(cfg: JSONValue?, user: UserConfigSnapshot) async -> [Row] {
        let wsDir = cfg?.string(forKey: "mlx_models_directory")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let userDir = user.mlxModelsDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let configured = !wsDir.isEmpty ? wsDir : userDir
        let root: URL?
        do {
            root = try GrizzyClawPaths.mlxDownloadRoot(userConfiguredPath: configured.isEmpty ? nil : configured)
        } catch {
            root = nil
        }
        var ids: [String] = []
        if let root {
            ids = CachedMLXHubRepoIds.listRepoIds(downloadRoot: root)
        }
        if ids.isEmpty { ids = [user.mlxModel] }
        return ids.map { Row(modelId: $0, displayName: $0) }
    }

    private static func customRows(cfg: JSONValue?, user: UserConfigSnapshot, secrets: UserConfigSecrets) async -> [Row] {
        if let raw = cfg?.string(forKey: "custom_provider_url"),
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let key = workspaceOrGlobalApiKey(cfg: cfg, secrets: secrets, workspaceKey: "custom_provider_api_key", global: secrets.customProviderApiKey)
            let k = key ?? ""
            var ids: [String] = []
            if !k.isEmpty {
                ids = await ModelListFetch.openAIStyleModelIds(baseURL: raw, apiKey: k)
            }
            if ids.isEmpty { ids = [user.defaultModel] }
            return ids.map { Row(modelId: $0, displayName: $0) }
        }
        return [user.defaultModel].map { Row(modelId: $0, displayName: $0) }
    }
}
