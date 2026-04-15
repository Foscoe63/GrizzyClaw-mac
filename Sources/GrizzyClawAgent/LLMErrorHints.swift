import Foundation

/// User-facing error text + short hints for common LLM stream / HTTP failures.
public enum LLMErrorHints {
    public static func formattedMessage(for error: Error) -> String {
        if let http = error as? LLMStreamHTTPError {
            return formatHTTP(http)
        }
        if let url = error as? URLError {
            return formatURLError(url)
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return formatNSURLCode(ns.code, description: ns.localizedDescription)
        }
        let le = error as? LocalizedError
        var text = le?.errorDescription ?? error.localizedDescription
        if let hint = genericHint(for: error) {
            text += "\n\n\(hint)"
        } else if let r = le?.recoverySuggestion, !r.isEmpty {
            text += "\n\n\(r)"
        }
        return text
    }

    private static func formatHTTP(_ error: LLMStreamHTTPError) -> String {
        let code: Int
        let body: String
        switch error {
        case .httpStatus(let c, let b):
            code = c
            body = b
        }
        let tail = body.trimmingCharacters(in: .whitespacesAndNewlines)
        var line = (error as LocalizedError).errorDescription
            ?? (tail.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(tail.prefix(500))")
        if let h = httpHint(statusCode: code) {
            line += "\n\n\(h)"
        }
        return line
    }

    private static func httpHint(statusCode: Int) -> String? {
        switch statusCode {
        case 401:
            return "Hint: Unauthorized — check API key in ~/.grizzyclaw/config.yaml or macOS Keychain (same account names as YAML keys; see Config tab), plus workspace LLM provider settings."
        case 403:
            return "Hint: Forbidden — key or token may be invalid for this model/region, or account lacks access."
        case 404:
            return "Hint: Verify base URL, model name, and that the server exposes this endpoint."
        case 408, 504:
            return "Hint: Server or network timed out — retry, or increase timeouts if your provider allows it."
        case 429:
            return "Hint: Rate limited — wait and retry, reduce request frequency, or upgrade the provider plan."
        case 500...599:
            return "Hint: Provider or local server error — check server logs (Ollama/LM Studio) and try again later."
        default:
            return nil
        }
    }

    /// User-facing text for **Test connection** / ping failures (merges raw URLSession message with the same hints as streaming HTTP errors).
    public static func formattedPingFailureMessage(_ message: String) -> String {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = "Connection test failed."
        if !m.isEmpty {
            out += "\n" + m
        }
        if let h = pingFailureHint(for: m) {
            out += "\n\n" + h
        }
        return out
    }

    private static func pingFailureHint(for message: String) -> String? {
        let lower = message.lowercased()
        if lower.contains("http 401") || lower.range(of: #"\b401\b"#, options: .regularExpression) != nil {
            return httpHint(statusCode: 401)
        }
        if lower.contains("http 403") || lower.range(of: #"\b403\b"#, options: .regularExpression) != nil {
            return httpHint(statusCode: 403)
        }
        if lower.contains("http 404") || lower.range(of: #"\b404\b"#, options: .regularExpression) != nil {
            return httpHint(statusCode: 404)
        }
        if lower.contains("http 429") || lower.range(of: #"\b429\b"#, options: .regularExpression) != nil {
            return httpHint(statusCode: 429)
        }
        if lower.range(of: #"http 5\d\d"#, options: .regularExpression) != nil {
            return httpHint(statusCode: 500)
        }
        if lower.contains("connection refused") || lower.contains("could not connect") || lower.contains("failed to connect") {
            return "Hint: Connection refused or host down — confirm the API base URL and port; start Ollama, LM Studio, or your local server."
        }
        if lower.contains("timed out") || lower.contains("timeout") {
            return "Hint: Request timed out — retry, check VPN/firewall, or increase timeouts if configurable."
        }
        if lower.contains("could not find host") || lower.contains("hostname could not be found") {
            return "Hint: DNS / hostname — check the URL in config and workspace (typos, wrong host)."
        }
        return genericHintFromPlainText(message)
    }

    /// Fallback when the failure is a plain string (no typed `URLError`).
    private static func genericHintFromPlainText(_ message: String) -> String? {
        let s = message.lowercased()
        if s.contains("connection refused") || s.contains("refused") {
            return "Hint: Nothing is listening on that address/port — start Ollama/LM Studio or fix the URL."
        }
        return nil
    }

    private static func formatURLError(_ e: URLError) -> String {
        var line = e.localizedDescription
        switch e.code {
        case .notConnectedToInternet:
            line += "\n\nHint: Connect to the network, then retry."
        case .cannotFindHost, .dnsLookupFailed:
            line += "\n\nHint: Check hostname in the URL (Ollama/LM Studio/OpenAI base URL)."
        case .cannotConnectToHost, .networkConnectionLost:
            line += "\n\nHint: Is the LLM server running? For Ollama/LM Studio, start the app and confirm the port."
        case .timedOut:
            line += "\n\nHint: Server may be slow or unreachable — confirm URL and firewall settings."
        case .appTransportSecurityRequiresSecureConnection:
            line += "\n\nHint: This app build blocked plain HTTP. Use HTTPS, or allow ATS exceptions for local/LAN LLM servers."
        case .secureConnectionFailed:
            line += "\n\nHint: TLS/HTTPS issue — check URL scheme (http vs https) and certificates."
        default:
            if let h = genericHint(for: e) { line += "\n\n\(h)" }
        }
        return line
    }

    private static func formatNSURLCode(_ code: Int, description: String) -> String {
        var line = description
        // Common CFNetwork / URLSession codes
        switch code {
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
            line += "\n\nHint: Connection refused or host not found — confirm the API base URL and that the service is listening."
        case NSURLErrorTimedOut:
            line += "\n\nHint: Request timed out — retry or check VPN/firewall."
        case NSURLErrorNotConnectedToInternet:
            line += "\n\nHint: No network route — connect to the internet and retry."
        default:
            break
        }
        return line
    }

    private static func genericHint(for error: Error) -> String? {
        let s = String(describing: error).lowercased()
        if s.contains("full disk access required") {
            return """
            Hint: This action needs macOS Full Disk Access for the automation helper. Open System Settings → Privacy & Security → Full Disk Access, enable the helper app, then restart it and retry.
            """
        }
        if s.contains("templateexception")
            || s.contains("jinja.")
            || s.contains("jinjaerror")
            || s.contains("jina.") // NSError / autocorrect sometimes shows “Jina” for Jinja
        {
            return "Hint: On-device MLX uses the model’s Hugging Face chat template (Jinja). Tool results with `{{` / `{%`-like text used to confuse the template — that case is sanitized in current builds; if this persists, try Clear chat or a shorter history."
        }
        if s.contains("connection refused") || s.contains("refused") {
            return "Hint: Nothing is listening on that address/port — start Ollama/LM Studio or fix the URL."
        }
        return nil
    }
}
