import Foundation
import GrizzyClawCore

/// Fetches model id lists from local and remote providers (parity with Python `settings_dialog` + `grizzyclaw/llm/*`).
public enum ModelListFetch: Sendable {
    public struct FetchResult: Sendable {
        public var ids: [String]
        public var diagnostic: String?

        public init(ids: [String], diagnostic: String? = nil) {
            self.ids = ids
            self.diagnostic = diagnostic
        }
    }

    /// Collapses mistaken `http://host:PORT:PORT` (duplicate numeric port) to `http://host:PORT`.
    /// Foundation rejects the double-port form, which previously led to concatenating `/api/v1/models`
    /// onto a non-URL string and surfacing "Invalid LM Studio model list URL: …:1234:1234/…".
    public static func collapseDuplicateLmStudioAuthorityPort(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let re = try? NSRegularExpression(
            pattern: #"^(?i)(https?://)([^/:?\[\]]+):(\d{1,5}):\3(?=/|$)"#,
            options: []
        ) else { return t }
        for _ in 0..<6 {
            let fullRange = NSRange(t.startIndex..., in: t)
            let next = re.stringByReplacingMatches(in: t, options: [], range: fullRange, withTemplate: "$1$2:$3")
            if next == t { break }
            t = next
        }
        return t
    }

    private struct LMStudioAttemptResult: Sendable {
        var ids: [String]
        var diagnostic: String?
    }

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
        let b = collapseDuplicateLmStudioAuthorityPort(
            base.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        )
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
        var base = collapseDuplicateLmStudioAuthorityPort(raw.trimmingCharacters(in: .whitespacesAndNewlines))
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
    ///
    /// Prefer ``lmStudioOpenAICompatModelFetch(lmstudioOpenAICompatURL:apiKey:)`` for provider `lmstudio` so model discovery stays on the OpenAI surface (`/v1/models`) and does not follow a different host than the configured compat URL.
    public static func lmStudioOpenAINativeModelIds(lmstudioOpenAICompatURL: String, apiKey: String?) async -> [String] {
        await lmStudioOpenAINativeModelFetch(lmstudioOpenAICompatURL: lmstudioOpenAICompatURL, apiKey: apiKey).ids
    }

    public static func lmStudioOpenAINativeModelFetch(lmstudioOpenAICompatURL: String, apiKey: String?) async -> FetchResult {
        let stripped = lmStudioNativeApiBaseFromOpenAICompatURL(lmstudioOpenAICompatURL)
        let candidates = lmStudioNativeModelListBaseCandidates(stripped)
        return await lmStudioFetchNativeModelResult(baseCandidates: candidates, apiKey: apiKey)
    }

    /// Normalizes `lmstudio_url` to a base ending in `/v1` for `GET …/v1/models` (no trailing slash after `v1`).
    public static func normalizeLmStudioOpenAICompatBaseForModelsList(_ raw: String) -> String? {
        var b = collapseDuplicateLmStudioAuthorityPort(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if b.isEmpty { return nil }
        if !b.hasPrefix("http://"), !b.hasPrefix("https://") {
            b = "http://\(b)"
        }
        b = b.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !b.lowercased().hasSuffix("/v1") {
            b += "/v1"
        }
        return b
    }

    /// LM Studio **OpenAI-compatible** model list: `GET {lmstudio_url}/models` where the URL includes `/v1` (same host/path style as chat). Optional `Authorization: Bearer` when `apiKey` is non-empty.
    public static func lmStudioOpenAICompatModelFetch(
        lmstudioOpenAICompatURL: String,
        apiKey: String?,
        unauthorizedRetry: Bool = false
    ) async -> FetchResult {
        guard let base = normalizeLmStudioOpenAICompatBaseForModelsList(lmstudioOpenAICompatURL) else {
            return FetchResult(ids: [], diagnostic: "LM Studio OpenAI-compat URL is empty.")
        }
        guard let rawUrl = URL(string: base + "/models") else {
            return FetchResult(ids: [], diagnostic: "Invalid LM Studio OpenAI-compat models URL: \(base)/models")
        }
        let url = LocalHTTPSession.preferIPv4Loopback(rawUrl)
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedKey.isEmpty {
            req.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        }
        GrizzyClawLog.debug("LM Studio model refresh: GET \(url.absoluteString)")
        do {
            let (data, resp) = try await LocalHTTPSession.modelProbe.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 401, !trimmedKey.isEmpty, !unauthorizedRetry {
                GrizzyClawLog.debug("LM Studio OpenAI-compat /v1/models: retrying without Authorization (401 with non-empty API key)")
                return await lmStudioOpenAICompatModelFetch(
                    lmstudioOpenAICompatURL: lmstudioOpenAICompatURL,
                    apiKey: nil,
                    unauthorizedRetry: true
                )
            }
            guard let http = resp as? HTTPURLResponse else {
                return FetchResult(ids: [], diagnostic: "LM Studio returned a non-HTTP response at \(url.absoluteString).")
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                let snippet = body.prefix(500)
                return FetchResult(
                    ids: [],
                    diagnostic:
                        "LM Studio OpenAI-compat GET /v1/models returned HTTP \(http.statusCode) at \(url.absoluteString).\n\(snippet)"
                )
            }
            let parsed = try JSONDecoder().decode(OpenAIModelsEnvelope.self, from: data)
            let ids = (parsed.data ?? []).compactMap { $0.id?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if ids.isEmpty {
                return FetchResult(
                    ids: [],
                    diagnostic:
                        "LM Studio returned HTTP 200 at \(url.absoluteString) but no model ids in the OpenAI `data` array (wrong server or schema?)."
                )
            }
            GrizzyClawLog.debug("LM Studio model refresh: \(ids.count) model(s) from \(url.absoluteString)")
            return FetchResult(ids: Array(Set(ids)).sorted())
        } catch {
            let formatted = LLMErrorHints.formattedMessage(for: error)
            return FetchResult(
                ids: [],
                diagnostic: "LM Studio OpenAI-compat request failed at \(url.absoluteString).\n\n\(formatted)"
            )
        }
    }

    /// `base` is normalized LM Studio base without `/v1` suffix (see `ChatParameterResolver.normalizeLmStudioV1Base`).
    /// Parses native `{ "models": [...] }` or OpenAI-style `{ "data": [...] }` (parity with `LMStudioV1Provider.list_models`).
    public static func lmStudioV1ModelIds(base: String, apiKey: String? = nil) async -> [String] {
        await lmStudioV1ModelFetch(base: base, apiKey: apiKey).ids
    }

    public static func lmStudioV1ModelFetch(base: String, apiKey: String? = nil) async -> FetchResult {
        let normalized = ChatParameterResolver.normalizeLmStudioV1Base(base)
        let candidates = lmStudioNativeModelListBaseCandidates(normalized)
        return await lmStudioFetchNativeModelResult(baseCandidates: candidates, apiKey: apiKey)
    }

    /// True when the OpenAI-compat ``lmstudio_url`` and the native v1 base resolve to the same HTTP authority (scheme + canonical host + port).
    ///
    /// URL comparison helper (e.g. diagnostics or future UX); the chat model picker always probes OpenAI-compat ``GET …/v1/models`` for `lmstudio` regardless of v1 enablement.
    public static func lmStudioOpenAICompatURLSharesAuthorityWithV1Base(openAICompatURL: String, lmstudioV1BaseRaw: String) -> Bool {
        let compatRoot = lmStudioNativeApiBaseFromOpenAICompatURL(openAICompatURL)
        let v1Root = ChatParameterResolver.normalizeLmStudioV1Base(lmstudioV1BaseRaw)
        guard let a = lmStudioHttpAuthorityFingerprint(compatRoot),
              let b = lmStudioHttpAuthorityFingerprint(v1Root) else { return false }
        return a == b
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

private extension ModelListFetch {
    static func lmStudioHttpAuthorityFingerprint(_ root: String) -> String? {
        var t = collapseDuplicateLmStudioAuthorityPort(
            root.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if t.isEmpty { return nil }
        if !t.hasPrefix("http://"), !t.hasPrefix("https://") {
            t = "http://\(t)"
        }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let u = URL(string: t), let hostRaw = u.host, !hostRaw.isEmpty else { return nil }
        let scheme = (u.scheme ?? "http").lowercased()
        let host = lmStudioCanonicalHost(hostRaw)
        let port: Int = {
            if let p = u.port { return p }
            return scheme == "https" ? 443 : 80
        }()
        return "\(scheme)://\(host):\(port)"
    }

    static func lmStudioCanonicalHost(_ host: String) -> String {
        let h = host.lowercased()
        if h == "localhost" || h == "127.0.0.1" || h == "::1" { return "loopback" }
        return h
    }

    static func lmStudioFetchNativeModelResult(
        baseCandidates: [String],
        apiKey: String?,
        unauthorizedRetry: Bool = false
    ) async -> FetchResult {
        var lastDiagnostic: String?
        for base in baseCandidates {
            let path = base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v1/models"
            guard let url = URL(string: path) else {
                lastDiagnostic = "Invalid LM Studio model list URL: \(path)"
                continue
            }
            var req = URLRequest(url: url)
            req.timeoutInterval = 15
            if let k = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty {
                req.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization")
            }
            GrizzyClawLog.debug("LM Studio model refresh: GET \(url.absoluteString)")
            let result = await lmStudioGETModelsResult(request: req)
            if !result.ids.isEmpty {
                GrizzyClawLog.debug("LM Studio model refresh: \(result.ids.count) model(s) from \(url.absoluteString)")
                return FetchResult(ids: result.ids)
            }
            if let diagnostic = result.diagnostic, !diagnostic.isEmpty {
                lastDiagnostic = diagnostic
                GrizzyClawLog.debug("LM Studio model refresh failed: \(singleLine(diagnostic))")
            }
        }
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let diagLower = (lastDiagnostic ?? "").lowercased()
        if !unauthorizedRetry,
           !trimmedKey.isEmpty,
           diagLower.contains("401") || diagLower.contains("unauthorized")
        {
            GrizzyClawLog.debug("LM Studio model refresh: retrying without Authorization (401 with non-empty API key)")
            return await lmStudioFetchNativeModelResult(
                baseCandidates: baseCandidates,
                apiKey: nil,
                unauthorizedRetry: true
            )
        }
        return FetchResult(
            ids: [],
            diagnostic: lastDiagnostic ?? "LM Studio did not return any model ids from /api/v1/models."
        )
    }

    private static func lmStudioGETModelsResult(request: URLRequest) async -> LMStudioAttemptResult {
        do {
            let (data, resp) = try await LocalHTTPSession.modelProbe.data(for: request)
            let initial = lmStudioParseResult(data: data, response: resp, url: request.url)
            if !initial.ids.isEmpty {
                return initial
            }
            if data.isEmpty {
                let (d2, r2) = try await URLSession.shared.data(for: request)
                let retry = lmStudioParseResult(data: d2, response: r2, url: request.url)
                if !retry.ids.isEmpty || retry.diagnostic != nil {
                    return retry
                }
            }
            return initial
        } catch {
            if let (d2, r2) = try? await URLSession.shared.data(for: request) {
                let retry = lmStudioParseResult(data: d2, response: r2, url: request.url)
                if !retry.ids.isEmpty || retry.diagnostic != nil {
                    return retry
                }
            }
            let formatted = LLMErrorHints.formattedMessage(for: error)
            return LMStudioAttemptResult(
                ids: [],
                diagnostic: "LM Studio request failed at \(request.url?.absoluteString ?? "<unknown>").\n\n\(formatted)"
            )
        }
    }

    private static func lmStudioParseResult(data: Data, response: URLResponse, url: URL?) -> LMStudioAttemptResult {
        let urlString = url?.absoluteString ?? "<unknown>"
        guard let http = response as? HTTPURLResponse else {
            return LMStudioAttemptResult(
                ids: [],
                diagnostic: "LM Studio returned a non-HTTP response at \(urlString)."
            )
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let formatted = LLMErrorHints.formattedMessage(for: LLMStreamHTTPError.httpStatus(http.statusCode, body))
            return LMStudioAttemptResult(
                ids: [],
                diagnostic: "LM Studio responded at \(urlString).\n\n\(formatted)"
            )
        }
        let ids = parseLmStudioNativeModelsJSON(data)
        if !ids.isEmpty {
            return LMStudioAttemptResult(ids: ids, diagnostic: nil)
        }
        if data.isEmpty {
            return LMStudioAttemptResult(
                ids: [],
                diagnostic: "LM Studio responded with HTTP 200 at \(urlString), but the response body was empty."
            )
        }
        let bodyPreview = String(data: data.prefix(400), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var message = "LM Studio responded with HTTP 200 at \(urlString), but no model ids were found in the JSON body."
        if !bodyPreview.isEmpty {
            message += "\n\nResponse preview:\n\(bodyPreview)"
        }
        return LMStudioAttemptResult(ids: [], diagnostic: message)
    }

    static func singleLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
