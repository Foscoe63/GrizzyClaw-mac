import Foundation

/// Subset of Python `Settings` / `~/.grizzyclaw/config.yaml` used by the Swift app for display and future LLM routing.
/// Keys match YAML snake_case from `grizzyclaw.config.Settings`.
public struct UserConfigSnapshot: Sendable, Equatable {
    public var configPathDisplay: String
    public var fileMissing: Bool

    public var appName: String
    public var debug: Bool
    public var theme: String
    public var fontFamily: String
    public var fontSize: Int
    public var compactMode: Bool

    public var defaultLlmProvider: String
    public var defaultModel: String
    public var maxTokens: Int
    public var maxSessionMessages: Int
    public var maxContextLength: Int

    public var ollamaUrl: String
    public var ollamaModel: String
    public var lmstudioUrl: String
    /// Native LM Studio v1 REST base (no `/api` or `/v1` suffix); from `lmstudio_v1_url` in `config.yaml`.
    public var lmstudioV1Url: String
    public var lmstudioModel: String
    /// Hugging Face repo id for bundled MLX (e.g. `mlx-community/Llama-3.2-3B-Instruct-4bit`).
    public var mlxModel: String
    /// Revision / branch for MLX hub downloads (default `main`).
    public var mlxRevision: String
    /// Optional absolute path for Hugging Face hub cache root (MLX). Empty = default `~/.grizzyclaw/mlx_models` (`mlx_models_directory` in config.yaml).
    public var mlxModelsDirectory: String
    public var openaiModel: String
    public var anthropicModel: String
    public var mcpServersFile: String
    public var mcpPromptSchemasEnabled: Bool
    /// Optional path to `skill_marketplace.json`; empty = use `~/.grizzyclaw/skill_marketplace.json` or built-in defaults (Python `skill_marketplace_path`).
    public var skillMarketplacePath: String
    /// Global ClawHub defaults used when a workspace/agent does not override `enabled_skills`.
    public var enabledSkills: [String]

    /// Whether non-empty API key strings appear in YAML (never expose raw secrets in UI).
    public var hasOpenaiApiKey: Bool
    public var hasAnthropicApiKey: Bool
    public var hasOpenrouterApiKey: Bool

    /// When false, chat history is not written to `~/.grizzyclaw/sessions/` (Python `session_persistence`).
    public var sessionPersistence: Bool

    /// Hard timeout (seconds) for one scheduled task run; `0` disables (`scheduled_task_run_timeout_seconds` in config.yaml).
    public var scheduledTaskRunTimeoutSeconds: Int

    /// Optional gateway WebSocket auth for `sessions_send` (`gateway_auth_token` in `config.yaml`; Python `Settings.gateway_auth_token`).
    public var gatewayAuthToken: String?

    public static let empty = UserConfigSnapshot(
        configPathDisplay: "",
        fileMissing: false,
        appName: "GrizzyClaw",
        debug: false,
        theme: "Light",
        fontFamily: "System Default",
        fontSize: 13,
        compactMode: false,
        defaultLlmProvider: "ollama",
        defaultModel: "llama3.2",
        maxTokens: 2000,
        maxSessionMessages: 20,
        maxContextLength: 4000,
        ollamaUrl: "http://localhost:11434",
        ollamaModel: "llama3.2",
        lmstudioUrl: "http://localhost:1234/v1",
        lmstudioV1Url: "http://localhost:1234",
        lmstudioModel: "local-model",
        mlxModel: "mlx-community/Llama-3.2-3B-Instruct-4bit",
        mlxRevision: "main",
        mlxModelsDirectory: "",
        openaiModel: "gpt-4o",
        anthropicModel: "claude-sonnet-4-5-20250929",
        mcpServersFile: "~/.grizzyclaw/grizzyclaw.json",
        mcpPromptSchemasEnabled: true,
        skillMarketplacePath: "",
        enabledSkills: [],
        hasOpenaiApiKey: false,
        hasAnthropicApiKey: false,
        hasOpenrouterApiKey: false,
        sessionPersistence: true,
        scheduledTaskRunTimeoutSeconds: 300,
        gatewayAuthToken: nil
    )

    /// Defaults with `fileMissing == true` (no `config.yaml` on disk yet).
    public static func missingFile(at url: URL) -> UserConfigSnapshot {
        let e = UserConfigSnapshot.empty
        return UserConfigSnapshot(
            configPathDisplay: url.path,
            fileMissing: true,
            appName: e.appName,
            debug: e.debug,
            theme: e.theme,
            fontFamily: e.fontFamily,
            fontSize: e.fontSize,
            compactMode: e.compactMode,
            defaultLlmProvider: e.defaultLlmProvider,
            defaultModel: e.defaultModel,
            maxTokens: e.maxTokens,
            maxSessionMessages: e.maxSessionMessages,
            maxContextLength: e.maxContextLength,
            ollamaUrl: e.ollamaUrl,
            ollamaModel: e.ollamaModel,
            lmstudioUrl: e.lmstudioUrl,
            lmstudioV1Url: e.lmstudioV1Url,
            lmstudioModel: e.lmstudioModel,
            mlxModel: e.mlxModel,
            mlxRevision: e.mlxRevision,
            mlxModelsDirectory: e.mlxModelsDirectory,
            openaiModel: e.openaiModel,
            anthropicModel: e.anthropicModel,
            mcpServersFile: e.mcpServersFile,
            mcpPromptSchemasEnabled: e.mcpPromptSchemasEnabled,
            skillMarketplacePath: e.skillMarketplacePath,
            enabledSkills: e.enabledSkills,
            hasOpenaiApiKey: false,
            hasAnthropicApiKey: false,
            hasOpenrouterApiKey: false,
            sessionPersistence: e.sessionPersistence,
            scheduledTaskRunTimeoutSeconds: e.scheduledTaskRunTimeoutSeconds,
            gatewayAuthToken: nil
        )
    }

    public init(
        configPathDisplay: String,
        fileMissing: Bool,
        appName: String,
        debug: Bool,
        theme: String,
        fontFamily: String,
        fontSize: Int,
        compactMode: Bool,
        defaultLlmProvider: String,
        defaultModel: String,
        maxTokens: Int,
        maxSessionMessages: Int,
        maxContextLength: Int,
        ollamaUrl: String,
        ollamaModel: String,
        lmstudioUrl: String,
        lmstudioV1Url: String,
        lmstudioModel: String,
        mlxModel: String,
        mlxRevision: String,
        mlxModelsDirectory: String,
        openaiModel: String,
        anthropicModel: String,
        mcpServersFile: String,
        mcpPromptSchemasEnabled: Bool,
        skillMarketplacePath: String,
        enabledSkills: [String],
        hasOpenaiApiKey: Bool,
        hasAnthropicApiKey: Bool,
        hasOpenrouterApiKey: Bool,
        sessionPersistence: Bool,
        scheduledTaskRunTimeoutSeconds: Int,
        gatewayAuthToken: String?
    ) {
        self.configPathDisplay = configPathDisplay
        self.fileMissing = fileMissing
        self.appName = appName
        self.debug = debug
        self.theme = theme
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.compactMode = compactMode
        self.defaultLlmProvider = defaultLlmProvider
        self.defaultModel = defaultModel
        self.maxTokens = maxTokens
        self.maxSessionMessages = maxSessionMessages
        self.maxContextLength = maxContextLength
        self.ollamaUrl = ollamaUrl
        self.ollamaModel = ollamaModel
        self.lmstudioUrl = lmstudioUrl
        self.lmstudioV1Url = lmstudioV1Url
        self.lmstudioModel = lmstudioModel
        self.mlxModel = mlxModel
        self.mlxRevision = mlxRevision
        self.mlxModelsDirectory = mlxModelsDirectory
        self.openaiModel = openaiModel
        self.anthropicModel = anthropicModel
        self.mcpServersFile = mcpServersFile
        self.mcpPromptSchemasEnabled = mcpPromptSchemasEnabled
        self.skillMarketplacePath = skillMarketplacePath
        self.enabledSkills = enabledSkills
        self.hasOpenaiApiKey = hasOpenaiApiKey
        self.hasAnthropicApiKey = hasAnthropicApiKey
        self.hasOpenrouterApiKey = hasOpenrouterApiKey
        self.sessionPersistence = sessionPersistence
        self.scheduledTaskRunTimeoutSeconds = scheduledTaskRunTimeoutSeconds
        self.gatewayAuthToken = gatewayAuthToken
    }

    /// Parse YAML-loaded dictionary (same keys as Python `Settings` / `yaml.safe_load`).
    public init(parsing dict: [String: Any], configPath: URL) {
        func str(_ k: String, _ d: String) -> String {
            Self.coerceString(dict[k], default: d)
        }
        func int(_ k: String, _ d: Int) -> Int {
            Self.coerceInt(dict[k], default: d)
        }
        func bool(_ k: String, _ d: Bool) -> Bool {
            Self.coerceBool(dict[k], default: d)
        }
        func hasSecret(_ k: String) -> Bool {
            guard let v = dict[k] else { return false }
            if v is NSNull { return false }
            let s = Self.coerceString(v, default: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !s.isEmpty
        }
        func optionalSecret(_ k: String) -> String? {
            guard let v = dict[k], !(v is NSNull) else { return nil }
            let s = Self.coerceString(v, default: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }

        var provider = str("default_llm_provider", "ollama")
        if provider == "opencode" {
            provider = "opencode_zen"
        }

        self.init(
            configPathDisplay: configPath.path,
            fileMissing: false,
            appName: str("app_name", "GrizzyClaw"),
            debug: bool("debug", false),
            theme: str("theme", "Light"),
            fontFamily: str("font_family", "System Default"),
            fontSize: int("font_size", 13),
            compactMode: bool("compact_mode", false),
            defaultLlmProvider: provider,
            defaultModel: str("default_model", "llama3.2"),
            maxTokens: int("max_tokens", 2000),
            maxSessionMessages: int("max_session_messages", 20),
            maxContextLength: int("max_context_length", 4000),
            ollamaUrl: str("ollama_url", "http://localhost:11434"),
            ollamaModel: str("ollama_model", "llama3.2"),
            lmstudioUrl: str("lmstudio_url", "http://localhost:1234/v1"),
            lmstudioV1Url: str("lmstudio_v1_url", "http://localhost:1234"),
            lmstudioModel: str("lmstudio_model", "local-model"),
            mlxModel: str("mlx_model", "mlx-community/Llama-3.2-3B-Instruct-4bit"),
            mlxRevision: str("mlx_revision", "main"),
            mlxModelsDirectory: str("mlx_models_directory", ""),
            openaiModel: str("openai_model", "gpt-4o"),
            anthropicModel: str("anthropic_model", "claude-sonnet-4-5-20250929"),
            mcpServersFile: str("mcp_servers_file", "~/.grizzyclaw/grizzyclaw.json"),
            mcpPromptSchemasEnabled: bool("mcp_prompt_schemas_enabled", true),
            skillMarketplacePath: str("skill_marketplace_path", ""),
            enabledSkills: Self.coerceStringArray(dict["enabled_skills"]),
            hasOpenaiApiKey: hasSecret("openai_api_key"),
            hasAnthropicApiKey: hasSecret("anthropic_api_key"),
            hasOpenrouterApiKey: hasSecret("openrouter_api_key"),
            sessionPersistence: bool("session_persistence", true),
            scheduledTaskRunTimeoutSeconds: int("scheduled_task_run_timeout_seconds", 300),
            gatewayAuthToken: optionalSecret("gateway_auth_token")
        )
    }

    internal static func coerceString(_ v: Any?, default d: String) -> String {
        guard let v else { return d }
        if v is NSNull { return d }
        if let s = v as? String { return s }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        }
        if let n = v as? Int { return String(n) }
        if let n = v as? Double { return String(n) }
        if let b = v as? Bool { return b ? "true" : "false" }
        return d
    }

    internal static func coerceInt(_ v: Any?, default d: Int) -> Int {
        guard let v else { return d }
        if let n = v as? NSNumber { return n.intValue }
        if let i = v as? Int { return i }
        if let dbl = v as? Double { return Int(dbl) }
        if let s = v as? String, let i = Int(s) { return i }
        return d
    }

    internal static func coerceBool(_ v: Any?, default d: Bool) -> Bool {
        guard let v else { return d }
        if let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue }
        if let b = v as? Bool { return b }
        if let i = v as? Int { return i != 0 }
        if let s = v as? String {
            let t = s.lowercased()
            if ["1", "true", "yes"].contains(t) { return true }
            if ["0", "false", "no"].contains(t) { return false }
        }
        return d
    }

    internal static func coerceDouble(_ v: Any?, default d: Double) -> Double {
        guard let v else { return d }
        if v is NSNull { return d }
        if let x = v as? NSNumber { return x.doubleValue }
        if let x = v as? Double { return x }
        if let x = v as? Int { return Double(x) }
        if let s = v as? String, let x = Double(s) { return x }
        return d
    }

    internal static func coerceStringArray(_ v: Any?) -> [String] {
        if let items = v as? [Any] {
            return items.compactMap {
                let s = Self.coerceString($0, default: "").trimmingCharacters(in: .whitespacesAndNewlines)
                return s.isEmpty ? nil : s
            }
        }
        let single = Self.coerceString(v, default: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return single.isEmpty ? [] : [single]
    }
}
