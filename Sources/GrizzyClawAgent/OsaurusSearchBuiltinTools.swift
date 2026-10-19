import Foundation
import GrizzyClawCore

enum OsaurusSearchBuiltinTools {
    static func result(tool: String, arguments: [String: Any]) async -> String {
        let composite = "osaurus.search.\(tool)"
        switch tool {
        case "search", "search_news":
            return await search(composite: composite, arguments: arguments, news: tool == "search_news")
        case "search_images":
            return await searchImages(composite: composite, arguments: arguments)
        case "search_and_extract":
            return await searchAndExtract(composite: composite, arguments: arguments)
        default:
            return ToolEnvelope.failure(
                tool: composite,
                kind: "unknown_tool",
                message: "Unknown osaurus.search tool `\(tool)`."
            )
        }
    }

    /// Shared DuckDuckGo Instant Answer JSON fetch (same backend as `search`).
    private static func duckDuckGoInstantAnswerObject(query q: String, news: Bool) async throws -> [String: Any] {
        var pieces: [URLQueryItem] = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "no_redirect", value: "1"),
        ]
        if news {
            pieces.append(URLQueryItem(name: "t", value: "news"))
        }
        var comp = URLComponents(string: "https://api.duckduckgo.com/")!
        comp.queryItems = pieces
        guard let url = comp.url else {
            throw NSError(domain: "OsaurusSearchBuiltinTools", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bad search URL."])
        }
        guard case .allowed(let safe) = GrizzyOutboundHTTPURLPolicy.validateAgentHTTPURL(url.absoluteString)
        else {
            throw NSError(domain: "OsaurusSearchBuiltinTools", code: 2, userInfo: [NSLocalizedDescriptionKey: "URL policy rejected search URL."])
        }
        let res = try await OsaurusBuiltinHTTPClient.perform(
            url: safe,
            method: "GET",
            headers: ["User-Agent": "GrizzyClawAgent/1.0 (bundled search)"],
            body: nil,
            maxBodyBytes: GrizzyOutboundHTTPURLPolicy.defaultMaxBodyBytes
        )
        guard let obj = try? JSONSerialization.jsonObject(with: res.body) as? [String: Any] else {
            throw NSError(
                domain: "OsaurusSearchBuiltinTools", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected DuckDuckGo response shape."]
            )
        }
        return obj
    }

    private static func search(
        composite: String,
        arguments: [String: Any],
        news: Bool
    ) async -> String {
        let q =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["query", "q", "text"])
            ?? ""
        guard !q.isEmpty else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Pass `query` (search text).",
                field: "query"
            )
        }
        do {
            let obj = try await duckDuckGoInstantAnswerObject(query: q, news: news)
            var results: [[String: Any]] = []
            if let abstract = obj["Abstract"] as? String, !abstract.isEmpty,
                let u = obj["AbstractURL"] as? String, !u.isEmpty
            {
                results.append([
                    "title": obj["Heading"] as? String ?? q,
                    "url": u,
                    "snippet": abstract,
                    "source_domain": (URL(string: u)?.host ?? ""),
                ])
            }
            if let topics = obj["RelatedTopics"] as? [Any] {
                for t in topics.prefix(12) {
                    if let d = t as? [String: Any], let text = d["Text"] as? String,
                        let u = d["FirstURL"] as? String
                    {
                        results.append([
                            "title": text,
                            "url": u,
                            "snippet": text,
                            "source_domain": (URL(string: u)?.host ?? ""),
                        ])
                    }
                }
            }
            return ToolEnvelope.success(
                tool: composite,
                result: [
                    "query": q,
                    "backend": "duckduckgo_instant_answer",
                    "results": results,
                ])
        } catch {
            return ToolEnvelope.fromError(error, tool: composite)
        }
    }

    /// Image-oriented results from the same Instant Answer API (topic image + related icons). Not full image SERP parity.
    private static func searchImages(composite: String, arguments: [String: Any]) async -> String {
        let q =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["query", "q", "text"])
            ?? ""
        guard !q.isEmpty else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Pass `query` (search text).",
                field: "query"
            )
        }
        do {
            let obj = try await duckDuckGoInstantAnswerObject(query: q, news: false)
            var images: [[String: Any]] = []
            func appendImage(url: String, title: String, source: String) {
                guard case .allowed(let safe) = GrizzyOutboundHTTPURLPolicy.validateAgentHTTPURL(url) else { return }
                images.append([
                    "title": title,
                    "url": safe.absoluteString,
                    "source": source,
                ])
            }
            if let img = obj["Image"] as? String, !img.isEmpty {
                let heading = obj["Heading"] as? String ?? q
                appendImage(url: img, title: heading, source: "instant_answer_image")
            }
            if let topics = obj["RelatedTopics"] as? [Any] {
                for t in topics.prefix(24) {
                    if let d = t as? [String: Any],
                       let icon = d["Icon"] as? [String: Any],
                       let u = icon["URL"] as? String,
                       !u.isEmpty
                    {
                        let title = d["Text"] as? String ?? ""
                        appendImage(url: u, title: title, source: "related_topic_icon")
                    }
                }
            }
            return ToolEnvelope.success(
                tool: composite,
                result: [
                    "query": q,
                    "backend": "duckduckgo_instant_answer",
                    "images": images,
                    "note":
                        "Image hits come from DuckDuckGo Instant Answer (topic image and related icons), not a full image search index.",
                ])
        } catch {
            return ToolEnvelope.fromError(error, tool: composite)
        }
    }

    private static func searchAndExtract(composite: String, arguments: [String: Any]) async -> String {
        let q =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["query", "q", "text"])
            ?? ""
        guard !q.isEmpty else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Pass `query`.",
                field: "query"
            )
        }
        let n = min(
            max(OsaurusBuiltinToolArguments.int(from: arguments, keys: ["n", "top", "limit"], default: 2), 1),
            4
        )
        let searchJSON = await search(
            composite: "osaurus.search.search", arguments: ["query": q], news: false)
        guard ToolEnvelope.isSuccess(searchJSON),
            let data = searchJSON.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let ok = root["ok"] as? Bool, ok,
            let res = root["result"] as? [String: Any],
            let rows = res["results"] as? [[String: Any]]
        else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "search_failed",
                message: "Search step did not return usable results.",
                retryable: true
            )
        }
        var enriched: [[String: Any]] = []
        for row in rows.prefix(n) {
            guard let u = row["url"] as? String else { continue }
            guard case .allowed(let url) = GrizzyOutboundHTTPURLPolicy.validateAgentHTTPURL(u) else {
                continue
            }
            do {
                let fr = try await OsaurusBuiltinHTTPClient.perform(
                    url: url,
                    method: "GET",
                    headers: ["User-Agent": "GrizzyClawAgent/1.0 (bundled fetch)"],
                    body: nil,
                    maxBodyBytes: GrizzyOutboundHTTPURLPolicy.defaultMaxBodyBytes
                )
                let text =
                    String(data: fr.body, encoding: .utf8)
                    ?? String(data: fr.body, encoding: .isoLatin1)
                    ?? ""
                let extract =
                    OsaurusBuiltinToolArguments.string(from: arguments, keys: ["extract", "mode"])
                    ?? "markdown"
                let meta = OsaurusHTMLReadabilityLite.extract(from: text, extract: extract)
                var merged = row
                merged["markdown"] = meta["markdown"] ?? ""
                merged["title"] = meta["title"] ?? row["title"] ?? ""
                merged["extracted"] = true
                merged["word_count"] = meta["word_count"] ?? 0
                enriched.append(merged)
            } catch {
                var merged = row
                merged["extracted"] = false
                merged["error"] = error.localizedDescription
                enriched.append(merged)
            }
        }
        return ToolEnvelope.success(tool: composite, result: ["query": q, "results": enriched])
    }
}
