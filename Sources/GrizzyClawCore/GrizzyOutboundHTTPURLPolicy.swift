import Foundation

/// SSRF-style guardrails for agent-initiated HTTP (bundled fetch/search, etc.).
///
/// This is best-effort: hostnames that later resolve to private IPs (DNS rebinding) are not fully
/// eliminated without a dedicated proxy. We still block obvious private hosts, schemes, and literals.
public enum GrizzyOutboundHTTPURLPolicy {
    public static let defaultMaxBodyBytes: Int64 = 10 * 1024 * 1024

    public enum Validation {
        case allowed(URL)
        case rejected(String)
    }

    public static func validateAgentHTTPURL(_ raw: String) -> Validation {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: t), let scheme = url.scheme?.lowercased() else {
            return .rejected("invalid_url")
        }
        guard scheme == "http" || scheme == "https" else {
            return .rejected("unsupported_scheme")
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return .rejected("missing_host")
        }
        if isBlockedHost(host) {
            return .rejected("blocked_host")
        }
        return .allowed(url)
    }

    public static func isBlockedHost(_ host: String) -> Bool {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if h == "localhost" || h == "localhost." { return true }
        if h.hasSuffix(".local") || h.hasSuffix(".internal") { return true }
        if h == "0.0.0.0" { return true }
        if h == "metadata.google.internal" || h == "metadata" { return true }
        if h == "[::1]" || h == "::1" { return true }
        if h.hasPrefix("[") {
            return isBlockedIPv6Literal(h)
        }
        if let ipv4 = parseIPv4(h) {
            return isBlockedIPv4(ipv4)
        }
        return false
    }

    // MARK: - IPv4

    private static func parseIPv4(_ host: String) -> (UInt8, UInt8, UInt8, UInt8)? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4,
            let a = UInt8(parts[0]),
            let b = UInt8(parts[1]),
            let c = UInt8(parts[2]),
            let d = UInt8(parts[3])
        else { return nil }
        return (a, b, c, d)
    }

    private static func isBlockedIPv4(_ ip: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        let (a, b, _, _) = ip
        if a == 127 { return true }
        if a == 0 { return true }
        if a == 10 { return true }
        if a == 192, b == 168 { return true }
        if a == 169, b == 254 { return true }
        if a == 172, b >= 16, b <= 31 { return true }
        if a == 100, b >= 64, b <= 127 { return true }
        return false
    }

    // MARK: - IPv6 (minimal literals)

    private static func isBlockedIPv6Literal(_ host: String) -> Bool {
        let s = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if s == "::1" { return true }
        if s.hasPrefix("fe80:") { return true }
        if s.hasPrefix("fc") || s.hasPrefix("fd") { return true }
        return false
    }
}
