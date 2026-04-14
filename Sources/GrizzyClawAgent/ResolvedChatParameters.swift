import Foundation
import GrizzyClawCore

public enum ChatResolutionError: LocalizedError, Sendable {
    case unsupportedProvider(String)
    case missingAPIKey(provider: String)
    case invalidURL(String)
    case workspaceRequired
    /// Bundled MLX inference is only available on Apple silicon builds.
    case mlxRequiresAppleSilicon
    /// `llm_model` / `mlx_model` must name a Hugging Face repo id (e.g. `mlx-community/...`).
    case mlxModelIdRequired

    public var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let p):
            return "Provider \"\(p)\" is not supported by the macOS client yet. Supported: ollama, lmstudio, lmstudio_v1, mlx, openai, openrouter, opencode_zen, cursor, custom, anthropic."
        case .missingAPIKey(let provider):
            return "No API key configured for provider \"\(provider)\" in workspace config or ~/.grizzyclaw/config.yaml."
        case .invalidURL(let s):
            return "Invalid URL: \(s)"
        case .workspaceRequired:
            return "Select a workspace in the Workspaces tab before chatting."
        case .mlxRequiresAppleSilicon:
            return "Bundled MLX inference requires an Apple silicon Mac (arm64 build)."
        case .mlxModelIdRequired:
            return "Set llm_model (workspace) or mlx_model (~/.grizzyclaw/config.yaml) to a Hugging Face model id, e.g. mlx-community/Llama-3.2-3B-Instruct-4bit."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unsupportedProvider:
            return "Set llm_provider on the workspace (Workspaces → Edit) or default_llm_provider in ~/.grizzyclaw/config.yaml, then reload Config."
        case .missingAPIKey(let provider):
            return Self.apiKeyHint(for: provider)
        case .mlxRequiresAppleSilicon:
            return "Use an HTTP provider (Ollama, LM Studio, cloud) on Intel Macs, or run an arm64 build on Apple silicon."
        case .mlxModelIdRequired:
            return "Pick an MLX model from the Hugging Face mlx-community org or another compatible repo; the first run downloads weights into ~/.grizzyclaw/mlx_models/."
        case .invalidURL(let s):
            if s.contains("cursor_url") {
                return "Set cursor_url (and cursor_api_key) in ~/.grizzyclaw/config.yaml. Reload Config, then try again."
            }
            if s.contains("custom_provider_url") {
                return "Set custom_provider_url in the workspace config (Workspaces → Edit)."
            }
            return "Check URLs in workspace config and ~/.grizzyclaw/config.yaml."
        case .workspaceRequired:
            return "Open the Workspaces tab, select a row, then return to Chat."
        }
    }

    private static func apiKeyHint(for provider: String) -> String {
        let key: String
        switch provider {
        case "openai": key = "openai_api_key"
        case "openrouter": key = "openrouter_api_key"
        case "opencode_zen": key = "opencode_zen_api_key"
        case "cursor": key = "cursor_api_key"
        case "lmstudio": key = "lmstudio_api_key (optional for local)"
        case "anthropic": key = "anthropic_api_key"
        case "lmstudio_v1": key = "lmstudio_v1_api_key (optional for local)"
        default: key = "\(provider)_api_key"
        }
        return "Add \(key) under ~/.grizzyclaw/config.yaml (see Config tab for the path), reload Config, then retry."
    }
}

/// Enough information to POST to an OpenAI-compatible `/v1/chat/completions` (or vendor equivalent).
public struct ResolvedChatParameters: Sendable {
    public let providerId: String
    public let chatCompletionsURL: URL
    public let apiKey: String?
    public let model: String
    public let temperature: Double
    public let maxTokens: Int?
    public let frequencyPenalty: Double?
    public let systemPrompt: String

    public init(
        providerId: String,
        chatCompletionsURL: URL,
        apiKey: String?,
        model: String,
        temperature: Double,
        maxTokens: Int?,
        frequencyPenalty: Double?,
        systemPrompt: String
    ) {
        self.providerId = providerId
        self.chatCompletionsURL = chatCompletionsURL
        self.apiKey = apiKey
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.frequencyPenalty = frequencyPenalty
        self.systemPrompt = systemPrompt
    }
}

/// Parameters for bundled on-device MLX generation (mlx-swift-lm + Hugging Face Hub downloads).
public struct MLXStreamParameters: Sendable {
    public var providerId: String
    /// Hugging Face model repo id (e.g. `mlx-community/Llama-3.2-3B-Instruct-4bit`).
    public var modelId: String
    public var revision: String
    public var temperature: Double
    public var maxOutputTokens: Int?
    public var systemPrompt: String
    /// Root directory for Hub downloads (typically `~/.grizzyclaw/mlx_models`).
    public var downloadBaseDirectory: URL

    public init(
        providerId: String,
        modelId: String,
        revision: String,
        temperature: Double,
        maxOutputTokens: Int?,
        systemPrompt: String,
        downloadBaseDirectory: URL
    ) {
        self.providerId = providerId
        self.modelId = modelId
        self.revision = revision
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.systemPrompt = systemPrompt
        self.downloadBaseDirectory = downloadBaseDirectory
    }
}

/// Resolved routing for the Chat tab: OpenAI-compatible, Anthropic Messages API, LM Studio native v1, or bundled MLX.
public enum ResolvedLLMStreamRequest: Sendable {
    case openAICompatible(ResolvedChatParameters)
    case anthropic(AnthropicStreamParameters)
    case lmStudioV1(LMStudioV1StreamParameters)
    case mlx(MLXStreamParameters)
}

public enum ChatParameterResolver {
    /// Merges global `config.yaml`, secrets, and the active workspace `config` object (Python `WorkspaceConfig`).
    public static func resolve(
        user: UserConfigSnapshot,
        routing: RoutingExtras,
        secrets: UserConfigSecrets,
        workspace: WorkspaceRecord?,
        guiLlmOverride: GuiChatPreferences.LLM? = nil,
        systemPromptSuffix: String? = nil
    ) throws -> ResolvedLLMStreamRequest {
        guard let ws = workspace else {
            throw ChatResolutionError.workspaceRequired
        }

        let cfg = ws.config

        var provider = cfg?.string(forKey: "llm_provider") ?? user.defaultLlmProvider
        if let gp = guiLlmOverride?.provider?.trimmingCharacters(in: .whitespacesAndNewlines), !gp.isEmpty {
            provider = gp
        }
        if provider == "opencode" {
            provider = "opencode_zen"
        }

        let guiModel: String? = {
            guard let m = guiLlmOverride?.model?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty else {
                return nil
            }
            return m
        }()

        func pickModel(_ workspaceModel: String?, _ fallback: String) -> String {
            if let g = guiModel { return g }
            if let w = workspaceModel?.trimmingCharacters(in: .whitespacesAndNewlines), !w.isEmpty { return w }
            return fallback
        }

        let temperature = cfg?.double(forKey: "temperature") ?? 0.7
        let maxTok = cfg?.int(forKey: "max_tokens") ?? user.maxTokens

        let baseSystemPrompt = cfg?.string(forKey: "system_prompt") ?? routing.systemPrompt
        let systemPrompt: String = {
            let suf = systemPromptSuffix?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !suf.isEmpty else { return baseSystemPrompt }
            let base = baseSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if base.isEmpty { return suf }
            return base + "\n\n" + suf
        }()

        let rep = routing.llmRepetitionPenalty
        let freq: Double? = {
            let fp = max(0.0, min(2.0, rep - 1.0))
            return abs(fp) < 0.0001 ? nil : fp
        }()
        let lmStudioV1Repeat: Double? = {
            let clamped = max(1.0, min(2.0, rep))
            return abs(clamped - 1.0) < 0.0001 ? nil : clamped
        }()

        func pickKey(_ wsKey: String, _ global: String?) -> String? {
            if let s = cfg?.string(forKey: wsKey), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return s
            }
            return global.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        }

        func openAIParams(
            providerId: String,
            chatCompletionsURL: URL,
            apiKey: String?,
            model: String
        ) -> ResolvedLLMStreamRequest {
            .openAICompatible(
                ResolvedChatParameters(
                    providerId: providerId,
                    chatCompletionsURL: chatCompletionsURL,
                    apiKey: apiKey,
                    model: model,
                    temperature: temperature,
                    maxTokens: maxTok,
                    frequencyPenalty: freq,
                    systemPrompt: systemPrompt
                )
            )
        }

        switch provider {
        case "ollama":
            let base = cfg?.string(forKey: "ollama_url") ?? user.ollamaUrl
            let url = try openAICompatURL(hostBase: base)
            let model = pickModel(cfg?.string(forKey: "llm_model"), user.ollamaModel)
            return openAIParams(providerId: provider, chatCompletionsURL: url, apiKey: nil, model: model)

        case "lmstudio":
            let base: String = {
                if let s = cfg?.string(forKey: "lmstudio_url"),
                   !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
                return user.lmstudioUrl
            }()
            let url = try openAICompatURL(hostBase: base)
            let model = pickModel(cfg?.string(forKey: "llm_model"), user.lmstudioModel)
            let key = pickKey("lmstudio_api_key", secrets.lmstudioApiKey)
            return openAIParams(providerId: provider, chatCompletionsURL: url, apiKey: key, model: model)

        case "lmstudio_v1":
            let rawBase: String = {
                if let s = cfg?.string(forKey: "lmstudio_v1_url"),
                   !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return s
                }
                return user.lmstudioV1Url
            }()
            let base = Self.normalizeLmStudioV1Base(rawBase)
            guard let chatURL = URL(string: base + "/api/v1/chat") else {
                throw ChatResolutionError.invalidURL(rawBase)
            }
            guard let modelsURL = URL(string: base + "/api/v1/models") else {
                throw ChatResolutionError.invalidURL(rawBase)
            }
            let model = pickModel(cfg?.string(forKey: "llm_model"), user.lmstudioModel)
            let key = pickKey("lmstudio_v1_api_key", secrets.lmstudioV1ApiKey)
            return .lmStudioV1(
                LMStudioV1StreamParameters(
                    providerId: provider,
                    chatURL: chatURL,
                    modelsURL: modelsURL,
                    apiKey: key,
                    model: model,
                    temperature: temperature,
                    maxOutputTokens: maxTok,
                    repeatPenalty: lmStudioV1Repeat,
                    systemPrompt: systemPrompt
                )
            )

        case "mlx":
            guard HostArchitecture.isAppleSilicon else {
                throw ChatResolutionError.mlxRequiresAppleSilicon
            }
            let rawModel = pickModel(cfg?.string(forKey: "llm_model"), user.mlxModel)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawModel.isEmpty else {
                throw ChatResolutionError.mlxModelIdRequired
            }
            let revRaw = cfg?.string(forKey: "mlx_revision")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let revision = revRaw.isEmpty ? user.mlxRevision : revRaw
            let wsDir = cfg?.string(forKey: "mlx_models_directory")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let mergedDir = wsDir.isEmpty ? user.mlxModelsDirectory : wsDir
            let downloadBase: URL
            do {
                downloadBase = try GrizzyClawPaths.mlxDownloadRoot(
                    userConfiguredPath: mergedDir.isEmpty ? nil : mergedDir
                )
            } catch {
                throw ChatResolutionError.invalidURL("mlx_models: \(error.localizedDescription)")
            }
            return .mlx(
                MLXStreamParameters(
                    providerId: provider,
                    modelId: rawModel,
                    revision: revision,
                    temperature: temperature,
                    maxOutputTokens: maxTok,
                    systemPrompt: systemPrompt,
                    downloadBaseDirectory: downloadBase
                )
            )

        case "openai":
            let key = pickKey("openai_api_key", secrets.openaiApiKey)
            guard let key else { throw ChatResolutionError.missingAPIKey(provider: "openai") }
            let url = URL(string: "https://api.openai.com/v1/chat/completions")!
            let model = pickModel(cfg?.string(forKey: "llm_model"), user.openaiModel)
            return openAIParams(providerId: provider, chatCompletionsURL: url, apiKey: key, model: model)

        case "openrouter":
            let key = pickKey("openrouter_api_key", secrets.openrouterApiKey)
            guard let key else { throw ChatResolutionError.missingAPIKey(provider: "openrouter") }
            let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
            let model = pickModel(cfg?.string(forKey: "llm_model"), routing.openrouterModel)
            return openAIParams(providerId: provider, chatCompletionsURL: url, apiKey: key, model: model)

        case "opencode_zen":
            let key = pickKey("opencode_zen_api_key", secrets.opencodeZenApiKey)
            guard let key else { throw ChatResolutionError.missingAPIKey(provider: "opencode_zen") }
            let url = URL(string: "https://opencode.ai/zen/v1/chat/completions")!
            let model = pickModel(cfg?.string(forKey: "llm_model"), routing.opencodeZenModel)
            return openAIParams(providerId: provider, chatCompletionsURL: url, apiKey: key, model: model)

        case "cursor":
            let key = pickKey("cursor_api_key", secrets.cursorApiKey)
            guard let key else { throw ChatResolutionError.missingAPIKey(provider: "cursor") }
            let raw = routing.cursorUrl
            guard !raw.isEmpty else {
                throw ChatResolutionError.invalidURL("cursor_url is empty in ~/.grizzyclaw/config.yaml")
            }
            let full = try openAICompatURL(hostBase: raw)
            let model = pickModel(cfg?.string(forKey: "llm_model"), routing.cursorModel)
            return openAIParams(providerId: provider, chatCompletionsURL: full, apiKey: key, model: model)

        case "custom":
            guard let raw = cfg?.string(forKey: "custom_provider_url"), !raw.isEmpty else {
                throw ChatResolutionError.invalidURL("custom_provider_url")
            }
            let full = try openAICompatURL(hostBase: raw)
            let key = pickKey("custom_provider_api_key", secrets.customProviderApiKey)
            let model = pickModel(cfg?.string(forKey: "llm_model"), user.defaultModel)
            return openAIParams(providerId: provider, chatCompletionsURL: full, apiKey: key, model: model)

        case "anthropic":
            let key = pickKey("anthropic_api_key", secrets.anthropicApiKey)
            guard let key else { throw ChatResolutionError.missingAPIKey(provider: "anthropic") }
            guard let messagesURL = URL(string: "https://api.anthropic.com/v1/messages") else {
                throw ChatResolutionError.invalidURL("https://api.anthropic.com/v1/messages")
            }
            let model = pickModel(cfg?.string(forKey: "llm_model"), user.anthropicModel)
            let maxA = max(1, maxTok)
            return .anthropic(
                AnthropicStreamParameters(
                    providerId: provider,
                    messagesURL: messagesURL,
                    apiKey: key,
                    model: model,
                    temperature: temperature,
                    maxTokens: maxA,
                    systemPrompt: systemPrompt
                )
            )

        default:
            throw ChatResolutionError.unsupportedProvider(provider)
        }
    }

    /// Aligns with `_normalize_v1_base_url` in `grizzyclaw/llm/lmstudio_v1.py`.
    public static func normalizeLmStudioV1Base(_ raw: String) -> String {
        var url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty {
            return "http://localhost:1234"
        }
        if !url.hasPrefix("http://"), !url.hasPrefix("https://") {
            url = "http://\(url)"
        }
        url = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if url.contains("/v1"), !url.hasSuffix("/v1") {
            if let r = url.range(of: "/v1") {
                url = String(url[..<r.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
        } else if url.hasSuffix("/v1") {
            url = String(url.dropLast(3)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        if url.hasSuffix("/api") {
            url = String(url.dropLast(4)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return url.isEmpty ? "http://localhost:1234" : url
    }

    /// `hostBase` is e.g. `http://localhost:11434` or `http://localhost:1234/v1`.
    static func openAICompatURL(hostBase: String) throws -> URL {
        var t = hostBase.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !t.hasSuffix("/v1") {
            t += "/v1"
        }
        guard let url = URL(string: t + "/chat/completions") else {
            throw ChatResolutionError.invalidURL(hostBase)
        }
        return url
    }
}
