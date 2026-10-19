import Foundation
import GrizzyClawCore

enum OsaurusFetchBuiltinTools {
    private static let maxBytes = GrizzyOutboundHTTPURLPolicy.defaultMaxBodyBytes

    static func result(tool: String, arguments: [String: Any]) async -> String {
        let composite = "osaurus.fetch.\(tool)"
        switch tool {
        case "fetch":
            return await fetch(composite: composite, arguments: arguments, jsonBody: false, htmlExtract: nil)
        case "fetch_json":
            return await fetch(composite: composite, arguments: arguments, jsonBody: true, htmlExtract: nil)
        case "fetch_html":
            return await fetch(composite: composite, arguments: arguments, jsonBody: false, htmlExtract: "markdown")
        case "download":
            return await download(composite: composite, arguments: arguments)
        default:
            return ToolEnvelope.failure(
                tool: composite,
                kind: "unknown_tool",
                message: "Unknown osaurus.fetch tool `\(tool)`."
            )
        }
    }

    // MARK: - fetch / fetch_json / fetch_html

    private static func fetch(
        composite: String,
        arguments: [String: Any],
        jsonBody: Bool,
        htmlExtract: String?
    ) async -> String {
        let rawURL =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["url", "href", "endpoint"])
            ?? ""
        guard case .allowed(let url) = GrizzyOutboundHTTPURLPolicy.validateAgentHTTPURL(rawURL) else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_url",
                message: "Provide a public `http`/`https` URL (private hosts are blocked).",
                field: "url"
            )
        }
        let method = (OsaurusBuiltinToolArguments.string(from: arguments, keys: ["method", "verb"]) ?? "GET")
            .uppercased()
        var hdr =
            OsaurusBuiltinToolArguments.dictionary(from: arguments, keys: ["headers", "header"])
            ?? [:]
        if jsonBody {
            hdr["Accept"] = hdr["Accept"] ?? "application/json"
        }
        let bodyStr = OsaurusBuiltinToolArguments.string(from: arguments, keys: ["body", "data", "payload"])
        let bodyData = bodyStr.flatMap { Data($0.utf8) }
        do {
            let res = try await OsaurusBuiltinHTTPClient.perform(
                url: url,
                method: method,
                headers: hdr,
                body: bodyData,
                maxBodyBytes: maxBytes
            )
            let text = String(data: res.body, encoding: .utf8)
                ?? String(data: res.body, encoding: .isoLatin1)
                ?? ""
            if jsonBody {
                var payload: [String: Any] = [
                    "status": res.status,
                    "final_url": res.finalURL?.absoluteString ?? url.absoluteString,
                    "headers": res.headers,
                ]
                if let data = try? JSONSerialization.jsonObject(with: res.body) {
                    payload["json"] = data
                } else {
                    payload["json"] = NSNull()
                    payload["body"] = text
                }
                return ToolEnvelope.success(tool: composite, result: payload)
            }
            if htmlExtract != nil {
                let extract =
                    OsaurusBuiltinToolArguments.string(from: arguments, keys: ["extract", "mode"])
                    ?? "markdown"
                let meta = OsaurusHTMLReadabilityLite.extract(from: text, extract: extract)
                var payload: [String: Any] = [
                    "status": res.status,
                    "final_url": res.finalURL?.absoluteString ?? url.absoluteString,
                    "headers": res.headers,
                ]
                payload.merge(meta) { _, new in new }
                return ToolEnvelope.success(tool: composite, result: payload)
            }
            let cap = 200_000
            let truncated = text.count > cap
            let bodyOut = truncated ? String(text.prefix(cap)) : text
            var result: [String: Any] = [
                "status": res.status,
                "final_url": res.finalURL?.absoluteString ?? url.absoluteString,
                "headers": res.headers,
                "body": bodyOut,
            ]
            if truncated {
                result["truncated"] = true
                result["note"] = "Body truncated to \(cap) UTF-8 characters for the transcript."
            }
            return ToolEnvelope.success(tool: composite, result: result)
        } catch {
            return ToolEnvelope.fromError(error, tool: composite)
        }
    }

    // MARK: - download

    private static func download(composite: String, arguments: [String: Any]) async -> String {
        let rawURL =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["url", "href"])
            ?? ""
        guard case .allowed(let url) = GrizzyOutboundHTTPURLPolicy.validateAgentHTTPURL(rawURL) else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_url",
                message: "Provide a public `http`/`https` URL (private hosts are blocked).",
                field: "url"
            )
        }
        let nameRaw =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["filename", "name", "file"])
            ?? "download.bin"
        let filename = sanitizeFilename(nameRaw)
        guard let destDir = downloadsDirectory() else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "path_error",
                message: "Could not resolve Downloads directory.",
                retryable: false
            )
        }
        let destURL = destDir.appendingPathComponent(filename, isDirectory: false)
        guard isPath(destURL, under: destDir) else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Resolved path left the Downloads sandbox.",
                field: "filename"
            )
        }
        do {
            let res = try await OsaurusBuiltinHTTPClient.perform(
                url: url,
                method: "GET",
                headers: [:],
                body: nil,
                maxBodyBytes: maxBytes
            )
            guard (200..<300).contains(res.status) else {
                return ToolEnvelope.failure(
                    tool: composite,
                    kind: "http_error",
                    message: "HTTP \(res.status) while downloading.",
                    retryable: true
                )
            }
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            try res.body.write(to: destURL, options: .atomic)
            return ToolEnvelope.success(
                tool: composite,
                result: [
                    "path": destURL.path,
                    "bytes": res.body.count,
                    "filename": filename,
                ])
        } catch {
            return ToolEnvelope.fromError(error, tool: composite)
        }
    }

    private static func sanitizeFilename(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("~") { s.removeFirst() }
        s = (s as NSString).lastPathComponent
        if s.contains("..") || s.contains("/") || s.contains("\\") {
            return "download.bin"
        }
        if s.hasPrefix(".") || s.isEmpty {
            return "download.bin"
        }
        return s
    }

    private static func downloadsDirectory() -> URL? {
#if os(iOS)
        guard let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return nil }
        return base.appendingPathComponent("Downloads", isDirectory: true)
#else
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
#endif
    }

    private static func isPath(_ file: URL, under dir: URL) -> Bool {
        let f = file.standardizedFileURL.path
        let d = dir.standardizedFileURL.path
        return f.hasPrefix(d + "/") || f == d
    }
}
