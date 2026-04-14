import Foundation
import Yams

/// Extra routing fields from `config.yaml` used for LLM resolution (alongside `UserConfigSnapshot`).
public struct RoutingExtras: Sendable, Equatable {
    public var systemPrompt: String
    public var cursorUrl: String
    public var cursorModel: String
    public var openrouterModel: String
    public var opencodeZenModel: String
    /// Python `llm_repetition_penalty` (maps to `frequency_penalty` in OpenAI API as `max(0, min(2, rep - 1))`).
    public var llmRepetitionPenalty: Double

    public static let `default` = RoutingExtras(
        systemPrompt:
            "You are GrizzyClaw, a helpful AI assistant with memory. You can remember previous conversations and use that context to help the user.",
        cursorUrl: "",
        cursorModel: "gpt-4o",
        openrouterModel: "openai/gpt-4o",
        opencodeZenModel: "big-pickle",
        llmRepetitionPenalty: 1.15
    )

    init(
        systemPrompt: String,
        cursorUrl: String,
        cursorModel: String,
        openrouterModel: String,
        opencodeZenModel: String,
        llmRepetitionPenalty: Double
    ) {
        self.systemPrompt = systemPrompt
        self.cursorUrl = cursorUrl
        self.cursorModel = cursorModel
        self.openrouterModel = openrouterModel
        self.opencodeZenModel = opencodeZenModel
        self.llmRepetitionPenalty = llmRepetitionPenalty
    }

    init(parsing dict: [String: Any]) {
        func str(_ k: String, _ d: String) -> String {
            UserConfigSnapshot.coerceString(dict[k], default: d)
        }
        func dbl(_ k: String, _ d: Double) -> Double {
            UserConfigSnapshot.coerceDouble(dict[k], default: d)
        }

        self.init(
            systemPrompt: str(
                "system_prompt",
                RoutingExtras.default.systemPrompt
            ),
            cursorUrl: str("cursor_url", ""),
            cursorModel: str("cursor_model", "gpt-4o"),
            openrouterModel: str("openrouter_model", "openai/gpt-4o"),
            opencodeZenModel: str("opencode_zen_model", "big-pickle"),
            llmRepetitionPenalty: dbl("llm_repetition_penalty", 1.15)
        )
    }
}

extension UserConfigLoader {
    /// Reads routing-related keys from `config.yaml`.
    public static func loadRoutingExtras(at url: URL = GrizzyClawPaths.configYAML) throws -> RoutingExtras {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .default
        }
        guard let yamlText = String(data: try Data(contentsOf: url), encoding: .utf8) else {
            throw LoadError.notUTF8(url)
        }
        let parsed = try Yams.load(yaml: yamlText)
        let dict = (parsed as? [String: Any]) ?? [:]
        return RoutingExtras(parsing: dict)
    }
}
