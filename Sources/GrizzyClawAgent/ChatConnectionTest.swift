import Foundation
import GrizzyClawCore

/// Lightweight reachability checks (no chat POST, no tokens).
public enum ChatConnectionTest {
    public struct PingResult: Sendable {
        public var ok: Bool
        public var message: String

        public init(ok: Bool, message: String) {
            self.ok = ok
            self.message = message
        }
    }

    public static func ping(resolved: ResolvedLLMStreamRequest) async -> PingResult {
        switch resolved {
        case .openAICompatible(let p):
            return await pingServerRoot(chatCompletionsURL: p.chatCompletionsURL)
        case .anthropic:
            return await pingURL(
                url: URL(string: "https://api.anthropic.com")!,
                label: "Anthropic API host"
            )
        case .lmStudioV1(let p):
            return await pingLMStudioV1(modelsURL: p.modelsURL, apiKey: p.apiKey)
        case .mlx(let p):
            return pingMLX(parameters: p)
        }
    }

    private static func pingMLX(parameters: MLXStreamParameters) -> PingResult {
        guard HostArchitecture.isAppleSilicon else {
            return PingResult(ok: false, message: "MLX requires Apple silicon (arm64).")
        }
        if parameters.modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return PingResult(ok: false, message: "MLX: set llm_model to a Hugging Face model id.")
        }
        return PingResult(
            ok: true,
            message:
                "MLX: Apple silicon OK — model \(parameters.modelId)@\(parameters.revision). First chat may download weights to \(parameters.downloadBaseDirectory.path)."
        )
    }

    /// `chatURL` is e.g. `http://localhost:11434/v1/chat/completions` — strips `/v1/chat/completions` and GETs the service root.
    public static func pingServerRoot(chatCompletionsURL: URL) async -> PingResult {
        let root = apiRoot(from: chatCompletionsURL)
        return await pingURL(url: root, label: "API root")
    }

    static func apiRoot(from chatCompletions: URL) -> URL {
        chatCompletions
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func pingLMStudioV1(modelsURL: URL, apiKey: String?) async -> PingResult {
        var req = URLRequest(url: LocalHTTPSession.preferIPv4Loopback(modelsURL))
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        if let k = apiKey, !k.isEmpty {
            req.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, response) = try await LocalHTTPSession.modelProbe.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if code == 200 {
                return PingResult(ok: true, message: "LM Studio v1 reachable (HTTP \(code)) at \(modelsURL.absoluteString)")
            }
            if (200..<500).contains(code) {
                return PingResult(ok: true, message: "LM Studio v1 responded (HTTP \(code)) at \(modelsURL.absoluteString)")
            }
            return PingResult(ok: false, message: "HTTP \(code) at \(modelsURL.absoluteString)")
        } catch {
            return PingResult(ok: false, message: error.localizedDescription)
        }
    }

    private static func pingURL(url: URL, label: String) async -> PingResult {
        var req = URLRequest(url: LocalHTTPSession.preferIPv4Loopback(url))
        req.httpMethod = "GET"
        req.timeoutInterval = 10
        do {
            let (_, response) = try await LocalHTTPSession.modelProbe.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            if (200..<500).contains(code) {
                return PingResult(ok: true, message: "\(label) reachable (HTTP \(code)) at \(url.absoluteString)")
            }
            return PingResult(ok: false, message: "HTTP \(code) at \(url.absoluteString)")
        } catch {
            return PingResult(ok: false, message: error.localizedDescription)
        }
    }
}
