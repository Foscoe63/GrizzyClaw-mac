import Foundation

/// Helpers for HTTP to **local** LLM APIs (Ollama, LM Studio). Using `127.0.0.1` instead of `localhost`
/// avoids some dual-stack resolution paths that trigger noisy `nw_connection_*` logs on macOS when URLSession
/// touches connection metadata on not-yet-connected sockets (benign but alarming in Xcode).
///
/// **Console noise you may still see:** Apple’s CFNetwork/Network stack can log
/// `nw_connection_copy_protocol_metadata_internal`, `nw_connection_copy_connected_*_endpoint`, and
/// `nw_protocol_instance_set_output_handler … ne_filter` even for successful `http://127.0.0.1` probes.
/// Those often come from the system filter path (`ne_filter`), not from application bugs. If the model list
/// loads, you can ignore them or filter the Xcode console for your process / subsystem.
public enum LocalHTTPSession {
    /// Shared session for quick GETs to local model list endpoints (no cookies, no cache).
    public static let modelProbe: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 30
        c.waitsForConnectivity = false
        c.httpShouldSetCookies = false
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpMaximumConnectionsPerHost = 1
        c.allowsCellularAccess = false
        return URLSession(configuration: c)
    }()

    /// Prefer IPv4 loopback so the client does not rely on `localhost` → IPv6 / multiple address resolution.
    public static func preferIPv4Loopback(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        if parts.host?.lowercased() == "localhost" {
            parts.host = "127.0.0.1"
        }
        return parts.url ?? url
    }

    /// Same as ``preferIPv4Loopback(_:)`` when you only have a string (must be a parseable absolute URL).
    public static func preferIPv4LoopbackString(_ string: String) -> String {
        let t = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: t) else { return string }
        return preferIPv4Loopback(u).absoluteString
    }
}
