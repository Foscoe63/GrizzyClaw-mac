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

    /// Per-provider rows plus diagnostic text for probes that failed.
    ///
    /// `diagnosticsByProvider[k]` is set when a live probe for provider `k` produced an error
    /// (HTTP != 200, timeout, DNS failure, malformed JSON, etc.). The corresponding entry in
    /// `rowsByProvider[k]` still contains a fallback row (the user's stored default model) so
    /// the picker is never empty, but callers should surface the diagnostic so users know the
    /// fallback is *not* the real LM Studio / Ollama model list.
    public struct FetchOutcome: Sendable {
        public var rowsByProvider: [String: [Row]]
        public var diagnosticsByProvider: [String: String]

        public init(rowsByProvider: [String: [Row]] = [:], diagnosticsByProvider: [String: String] = [:]) {
            self.rowsByProvider = rowsByProvider
            self.diagnosticsByProvider = diagnosticsByProvider
        }
    }

    /// Fetches model lists for all built-in providers; empty fetch falls back to the default model id (Python `provider_models`).
    ///
    /// **Concurrency:** Probes run **in parallel** so a dead Ollama (`:11434`) does not delay LM Studio (`:1234`) in the chat toolbar.
    ///
    /// **Ollama:** Live `GET /api/tags` runs only when the effective default LLM provider is `ollama` (workspace `llm_provider` or global `default_llm_provider`). Otherwise the Ollama section shows the configured `ollama_model` only — avoids connection refused spam to `:11434` when you use LM Studio or other providers.
    ///
    /// **LM Studio (OpenAI-compat):** Always uses `GET …/v1/models` on ``lmstudio_url`` when building the picker (same as Settings refresh), even if native v1 is also enabled on the same host — users may load different models per API surface.
    ///
    /// **LM Studio v1:** Live `GET …/api/v1/models` runs when `lmstudio_v1_enabled` is set (workspace or global), or the effective default provider is `lmstudio_v1`. Otherwise the v1 row shows the stored `lmstudio_model` only — avoids probing a stale `lmstudio_v1_url` when v1 mode is off and you use another provider.
    public static func fetch(
        workspaceConfig cfg: JSONValue?,
        user: UserConfigSnapshot,
        routing: RoutingExtras,
        secrets: UserConfigSecrets
    ) async -> [String: [Row]] {
        await fetchWithDiagnostics(workspaceConfig: cfg, user: user, routing: routing, secrets: secrets).rowsByProvider
    }

    /// Same as ``fetch(workspaceConfig:user:routing:secrets:)`` but also returns per-provider
    /// diagnostics for probes that failed — so the workspace editor and chat composer can show
    /// the real error (e.g. "HTTP 401: Unauthorized", "connection refused") instead of silently
    /// substituting the stored default model and claiming "Loaded 1 model suggestion".
    public static func fetchWithDiagnostics(
        workspaceConfig cfg: JSONValue?,
        user: UserConfigSnapshot,
        routing: RoutingExtras,
        secrets: UserConfigSecrets
    ) async -> FetchOutcome {
        let anthropic = anthropicCuratedRows()

        async let ollama = ollamaRowsWithDiagnostic(cfg: cfg, user: user)
        async let lmstudio = lmstudioRowsWithDiagnostic(cfg: cfg, user: user, secrets: secrets)
        async let lmstudioV1 = lmstudioV1RowsWithDiagnostic(cfg: cfg, user: user, secrets: secrets)
        async let openai = openaiRows(cfg: cfg, user: user, secrets: secrets)
        async let openrouter = openrouterRows(cfg: cfg, routing: routing, secrets: secrets)
        async let opencodeZen = opencodeZenRows(cfg: cfg, routing: routing, secrets: secrets)
        async let cursor = cursorRows(cfg: cfg, routing: routing, secrets: secrets)
        async let mlx = mlxRows(cfg: cfg, user: user)
        async let custom = customRows(cfg: cfg, user: user, secrets: secrets)

        var rows: [String: [Row]] = [:]
        var diags: [String: String] = [:]

        let ollamaResult = await ollama
        rows["ollama"] = ollamaResult.rows
        if let d = ollamaResult.diagnostic { diags["ollama"] = d }

        let lmstudioResult = await lmstudio
        rows["lmstudio"] = lmstudioResult.rows
        if let d = lmstudioResult.diagnostic { diags["lmstudio"] = d }

        let lmstudioV1Result = await lmstudioV1
        rows["lmstudio_v1"] = lmstudioV1Result.rows
        if let d = lmstudioV1Result.diagnostic { diags["lmstudio_v1"] = d }

        rows["openai"] = await openai
        rows["anthropic"] = anthropic
        rows["openrouter"] = await openrouter
        rows["opencode_zen"] = await opencodeZen
        rows["cursor"] = await cursor
        rows["mlx"] = await mlx
        rows["custom"] = await custom
        return FetchOutcome(rowsByProvider: rows, diagnosticsByProvider: diags)
    }

    private struct ProbeResult: Sendable {
        var rows: [Row]
        var diagnostic: String?
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

    /// Native LM Studio v1 discovery hits `…/api/v1/models` on `lmstudio_v1_url`.
    private static func shouldProbeLmStudioV1LiveModelList(cfg: JSONValue?, user: UserConfigSnapshot) -> Bool {
        if cfg?.bool(forKey: "lmstudio_v1_enabled") == true { return true }
        if user.lmstudioV1Enabled { return true }
        return effectiveDefaultLlmProvider(cfg: cfg, user: user).lowercased() == "lmstudio_v1"
    }

    private static func resolvedLmStudioCompatURL(cfg: JSONValue?, user: UserConfigSnapshot) -> String {
        if let s = cfg?.string(forKey: "lmstudio_url"),
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
        return user.lmstudioUrl
    }

    private static func resolvedLmStudioV1BaseRaw(cfg: JSONValue?, user: UserConfigSnapshot) -> String {
        if let s = cfg?.string(forKey: "lmstudio_v1_url"),
           !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
        return user.lmstudioV1Url
    }

    private static func ollamaRowsWithDiagnostic(cfg: JSONValue?, user: UserConfigSnapshot) async -> ProbeResult {
        guard shouldProbeOllamaLiveModelList(cfg: cfg, user: user) else {
            return ProbeResult(rows: [user.ollamaModel].map { Row(modelId: $0, displayName: $0) }, diagnostic: nil)
        }
        let base = cfg?.string(forKey: "ollama_url") ?? user.ollamaUrl
        let ids = await ModelListFetch.ollamaTagNames(baseURL: base)
        if ids.isEmpty {
            let diag = "Ollama probe at \(base) returned no models (is `ollama serve` running?)."
            return ProbeResult(rows: [user.ollamaModel].map { Row(modelId: $0, displayName: $0) }, diagnostic: diag)
        }
        return ProbeResult(rows: ids.map { Row(modelId: $0, displayName: $0) }, diagnostic: nil)
    }

    private static func lmstudioRowsWithDiagnostic(cfg: JSONValue?, user: UserConfigSnapshot, secrets: UserConfigSecrets) async -> ProbeResult {
        let base = resolvedLmStudioCompatURL(cfg: cfg, user: user)
        let key = workspaceOrGlobalApiKey(cfg: cfg, secrets: secrets, workspaceKey: "lmstudio_api_key", global: secrets.lmstudioApiKey)
        let result = await ModelListFetch.lmStudioOpenAICompatModelFetch(lmstudioOpenAICompatURL: base, apiKey: key)
        if !result.ids.isEmpty {
            return ProbeResult(rows: result.ids.map { Row(modelId: $0, displayName: $0) }, diagnostic: nil)
        }
        let fallback = [Row(modelId: user.lmstudioModel, displayName: user.lmstudioModel)]
        let diag = result.diagnostic
            ?? "LM Studio OpenAI-compat probe at \(base) returned no models (is LM Studio running at this URL and a model loaded?)."
        return ProbeResult(rows: fallback, diagnostic: diag)
    }

    private static func lmstudioV1RowsWithDiagnostic(cfg: JSONValue?, user: UserConfigSnapshot, secrets: UserConfigSecrets) async -> ProbeResult {
        guard shouldProbeLmStudioV1LiveModelList(cfg: cfg, user: user) else {
            return ProbeResult(rows: [user.lmstudioModel].map { Row(modelId: $0, displayName: $0) }, diagnostic: nil)
        }
        let raw = resolvedLmStudioV1BaseRaw(cfg: cfg, user: user)
        let norm = ChatParameterResolver.normalizeLmStudioV1Base(raw)
        let key = workspaceOrGlobalApiKey(cfg: cfg, secrets: secrets, workspaceKey: "lmstudio_v1_api_key", global: secrets.lmstudioV1ApiKey)
        let result = await ModelListFetch.lmStudioV1ModelFetch(base: norm, apiKey: key)
        if !result.ids.isEmpty {
            return ProbeResult(rows: result.ids.map { Row(modelId: $0, displayName: $0) }, diagnostic: nil)
        }
        let fallback = [Row(modelId: user.lmstudioModel, displayName: user.lmstudioModel)]
        let diag = result.diagnostic ?? "LM Studio v1 probe at \(norm) returned no models (is LM Studio's local server running and loaded?)."
        return ProbeResult(rows: fallback, diagnostic: diag)
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
