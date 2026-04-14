import Foundation
import GrizzyClawCore

/// Fetches model id lists from local and remote providers (parity with Python `settings_dialog` + `grizzyclaw/llm/*`).
public enum ModelListFetch: Sendable {
    /// Parses LM Studio native `GET /api/v1/models` body. Uses per-element iteration so a mixed or oddly-bridged
    /// `models` array does not cause a failed `as? [[String: Any]]` cast (which would yield **no** ids despite HTTP 200).
    static func parseLmStudioNativeModelsJSON(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var list: [Any]?
        if let m = root["models"] as? [Any] { list = m }
        else if let d = root["data"] as? [Any] { list = d }
        guard let raw = list else { return [] }
        var ids: [String] = []
        for item in raw {
            if let s = idFromLmStudioModelEntry(item) {
                ids.append(s)
            }
        }
        return normalizeLmStudioIds(ids)
    }

    private static func normalizeLmStudioIds(_ ids: [String]) -> [String] {
        let trimmed = ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return Array(Set(trimmed)).sorted()
    }

    /// For loopback hosts, `URLSession` / resolution can behave differently for `localhost` vs `127.0.0.1` vs `::1`.
    /// Remote LAN URLs use a single candidate. Order: preserve configured host first, then IPv4 literal, then the other loopback name.
    static func lmStudioNativeModelListBaseCandidates(_ base: String) -> [String] {
        let b = base.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let u = URL(string: b), let host = u.host?.lowercased() else {
            return [LocalHTTPSession.preferIPv4LoopbackString(b)]
        }
        let loopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        if !loopback {
            return [b]
        }
        var seen = Set<String>()
        var out: [String] = []
        func push(_ s: String) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !t.isEmpty, seen.insert(t).inserted else { return }
            out.append(t)
        }
        push(b)
        push(LocalHTTPSession.preferIPv4LoopbackString(b))
        if host == "127.0.0.1", var comp = URLComponents(url: u, resolvingAgainstBaseURL: false) {
            comp.host = "localhost"
            if let u2 = comp.url { push(u2.absoluteString) }
        }
        return out
    }

    /// Strips OpenAI-compat `/v1` suffix only — does **not** rewrite `localhost` → `127.0.0.1` (see ``lmStudioNativeModelListBaseCandidates``).
    private static func lmStudioNativeApiBaseFromOpenAICompatURL(_ raw: String) -> String {
        var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { return "http://localhost:1234" }
        if !base.hasPrefix("http://"), !base.hasPrefix("https://") {
            base = "http://\(base)"
        }
        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if base.hasSuffix("/v1") {
            base = String(base.dropLast(3)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        let resolved = base.isEmpty ? "http://localhost:1234" : base
        return resolved
    }

    private static func lmStudioFetchNativeModelIds(baseCandidates: [String], apiKey: String?) async -> [String] {
        for base in baseCandidates {
            let path = base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v1/models"
            guard let url = URL(string: path) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 15
            if let k = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty {
                req.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization")
            }
            let ids = await lmStudioGETModelsParsingIds(request: req)
            if !ids.isEmpty { return ids }
        }
        return []
    }

    /// Ephemeral `URLSession` first; on loopback some setups return HTTP 200 with an **empty** body from that pool while LAN works — retry once with `URLSession.shared`.
    private static func lmStudioGETModelsParsingIds(request: URLRequest) async -> [String] {
        do {
            let (data, resp) = try await LocalHTTPSession.modelProbe.data(for: request)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            var ids = parseLmStudioNativeModelsJSON(data)
            if ids.isEmpty, data.isEmpty {
                let (d2, r2) = try await URLSession.shared.data(for: request)
                if let h2 = r2 as? HTTPURLResponse, h2.statusCode == 200 {
                    ids = parseLmStudioNativeModelsJSON(d2)
                }
            }
            return ids
        } catch {
            if let (d2, r2) = try? await URLSession.shared.data(for: request),
               let h2 = r2 as? HTTPURLResponse, h2.statusCode == 200 {
                return parseLmStudioNativeModelsJSON(d2)
            }
            return []
        }
    }

    private static func idFromLmStudioModelEntry(_ item: Any) -> String? {
        if let s = item as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        guard let m = item as? [String: Any] else { return nil }
        if let t = m["type"] as? String {
            let lower = t.lowercased()
            if lower == "embedding" || lower == "embeddings" { return nil }
        }
        let candidates: [String?] = [
            m["key"] as? String,
            m["id"] as? String,
            m["model"] as? String,
            m["name"] as? String,
            m["model_key"] as? String,
            m["display_name"] as? String,
        ]
        for c in candidates {
            if let u = c?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
                return u
            }
        }
        return nil
    }

    public struct OllamaTags: Decodable, Sendable {
        struct M: Decodable, Sendable { let name: String }
        let models: [M]?
    }

    /// OpenAI-style `GET …/v1/models` → `{ "data": [ { "id" } ] }`.
    public struct OpenAIModelsEnvelope: Decodable, Sendable {
        struct D: Decodable, Sendable { let id: String? }
        let data: [D]?
    }

    public static func ollamaTagNames(baseURL: String) async -> [String] {
        var t = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { t = "http://localhost:11434" }
        if !t.hasPrefix("http") { t = "http://\(t)" }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: t + "/api/tags") else { return [] }
        do {
            let probe = LocalHTTPSession.preferIPv4Loopback(url)
            var req = URLRequest(url: probe)
            // Composer refresh probes many local providers in parallel; fail fast when Ollama is not running.
            req.timeoutInterval = 4
            let (data, _) = try await LocalHTTPSession.modelProbe.data(for: req)
            let tags = try JSONDecoder().decode(OllamaTags.self, from: data)
            return (tags.models ?? []).map(\.name).filter { !$0.isEmpty }.sorted()
        } catch {
            return []
        }
    }

    /// LM Studio **OpenAI-compat** URL (e.g. `http://localhost:1234/v1`) → native `GET {host}/api/v1/models` (`models` array). See `LMStudioProvider._native_api_base` in Python.
    public static func lmStudioOpenAINativeModelIds(lmstudioOpenAICompatURL: String, apiKey: String?) async -> [String] {
        let stripped = lmStudioNativeApiBaseFromOpenAICompatURL(lmstudioOpenAICompatURL)
        let candidates = lmStudioNativeModelListBaseCandidates(stripped)
        return await lmStudioFetchNativeModelIds(baseCandidates: candidates, apiKey: apiKey)
    }

    /// `base` is normalized LM Studio base without `/v1` suffix (see `ChatParameterResolver.normalizeLmStudioV1Base`).
    /// Parses native `{ "models": [...] }` or OpenAI-style `{ "data": [...] }` (parity with `LMStudioV1Provider.list_models`).
    public static func lmStudioV1ModelIds(base: String, apiKey: String? = nil) async -> [String] {
        let normalized = ChatParameterResolver.normalizeLmStudioV1Base(base)
        let candidates = lmStudioNativeModelListBaseCandidates(normalized)
        return await lmStudioFetchNativeModelIds(baseCandidates: candidates, apiKey: apiKey)
    }

    /// Curated ids from `AnthropicProvider.list_models()` (Python).
    public static func anthropicCuratedModelIds() -> [String] {
        [
            "claude-sonnet-4-5-20250929",
            "claude-opus-4-6",
            "claude-sonnet-4-20250514",
            "claude-haiku-4-5-20251001",
            "claude-opus-4-5-20251101",
            "claude-opus-4-20250514",
            "claude-3-5-sonnet-20241022",
            "claude-3-5-haiku-20241022",
            "claude-3-opus-20240229",
            "claude-3-sonnet-20240229",
            "claude-3-haiku-20240307",
        ]
    }

    /// OpenAI-compatible `GET {baseURL}/models` with Bearer — `baseURL` must include `/v1` (e.g. `https://api.openai.com/v1`).
    public static func openAIStyleModelIds(baseURL: String, apiKey: String) async -> [String] {
        var b = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty { return [] }
        if !b.hasPrefix("http://"), !b.hasPrefix("https://") {
            b = "https://\(b)"
        }
        b = b.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !b.hasSuffix("/v1") {
            b += "/v1"
        }
        guard let url = URL(string: b + "/models") else { return [] }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 60
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 { return [] }
            let parsed = try JSONDecoder().decode(OpenAIModelsEnvelope.self, from: data)
            let ids = (parsed.data ?? []).compactMap { $0.id?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return Array(Set(ids)).sorted()
        } catch {
            return []
        }
    }

    /// OpenCode Zen — `OpencodeZenProvider` / `https://opencode.ai/zen/v1/models`.
    public static func opencodeZenModelIds(apiKey: String) async -> [String] {
        await openAIStyleModelIds(baseURL: "https://opencode.ai/zen/v1", apiKey: apiKey)
    }

    /// OpenRouter — same shape as OpenAI.
    public static func openRouterModelIds(apiKey: String) async -> [String] {
        await openAIStyleModelIds(baseURL: OpenRouterBaseURL, apiKey: apiKey)
    }

    private static let OpenRouterBaseURL = "https://openrouter.ai/api/v1"
}
