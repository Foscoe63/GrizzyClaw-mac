import Foundation
import GrizzyClawCore

private actor OsaurusBrowserSessionStore {
    static let shared = OsaurusBrowserSessionStore()
    private var map: [UUID: (url: URL, markdown: String, title: String)] = [:]

    func navigate(url: URL) async throws -> (UUID, String, String) {
        let id = UUID()
        let res = try await OsaurusBuiltinHTTPClient.perform(
            url: url,
            method: "GET",
            headers: ["User-Agent": "GrizzyClawAgent/1.0 (bundled browser)"],
            body: nil,
            maxBodyBytes: GrizzyOutboundHTTPURLPolicy.defaultMaxBodyBytes
        )
        let text =
            String(data: res.body, encoding: .utf8)
            ?? String(data: res.body, encoding: .isoLatin1)
            ?? ""
        let meta = OsaurusHTMLReadabilityLite.extract(from: text, extract: "markdown")
        let md = (meta["markdown"] as? String) ?? ""
        let title = (meta["title"] as? String) ?? ""
        map[id] = (url, md, title)
        while map.count > 20, let k = map.keys.first {
            map.removeValue(forKey: k)
        }
        return (id, title, url.absoluteString)
    }

    func snapshot(id: UUID) -> (url: URL, markdown: String, title: String)? {
        map[id]
    }
}

enum OsaurusBrowserBuiltinTools {
    static func result(tool: String, arguments: [String: Any]) async -> String {
        let composite = "osaurus.browser.\(tool)"
        switch tool {
        case "browser_navigate":
            return await navigate(composite: composite, arguments: arguments)
        case "browser_snapshot":
            return await snapshot(composite: composite, arguments: arguments)
        case "browser_reset_session":
            return ToolEnvelope.success(
                tool: composite,
                result: ["cleared": true, "note": "Built-in browser sessions are ephemeral per navigate call."]
            )
        case "browser_click", "browser_type", "browser_select", "browser_hover", "browser_scroll",
            "browser_do", "browser_press_key", "browser_wait_for", "browser_screenshot",
            "browser_execute_script", "browser_console_messages", "browser_network_requests",
            "browser_handle_dialog", "browser_set_viewport", "browser_set_user_agent", "browser_cookies",
            "browser_lock", "browser_open_login":
            return ToolEnvelope.failure(
                tool: composite,
                kind: "not_available_builtin",
                message:
                    "Interactive browser automation is not part of Grizzy's built-in tools. Use `browser_navigate` plus `browser_snapshot` to read static HTML, or `fetch_html` for extraction.",
                retryable: false
            )
        default:
            return ToolEnvelope.failure(
                tool: composite,
                kind: "unknown_tool",
                message: "Unknown osaurus.browser tool `\(tool)`."
            )
        }
    }

    private static func navigate(composite: String, arguments: [String: Any]) async -> String {
        let raw =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["url", "href", "target"])
            ?? ""
        guard case .allowed(let url) = GrizzyOutboundHTTPURLPolicy.validateAgentHTTPURL(raw) else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_url",
                message: "Provide a public `http`/`https` URL.",
                field: "url"
            )
        }
        do {
            let (id, title, href) = try await OsaurusBrowserSessionStore.shared.navigate(url: url)
            return ToolEnvelope.success(
                tool: composite,
                result: [
                    "session_id": id.uuidString,
                    "url": href,
                    "title": title,
                ])
        } catch {
            return ToolEnvelope.fromError(error, tool: composite)
        }
    }

    private static func snapshot(composite: String, arguments: [String: Any]) async -> String {
        let sid =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["session_id", "session", "id"])
            ?? ""
        guard let uuid = UUID(uuidString: sid) else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Pass `session_id` from the latest `browser_navigate` result.",
                field: "session_id"
            )
        }
        guard let snap = await OsaurusBrowserSessionStore.shared.snapshot(id: uuid) else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "unknown_session",
                message: "Unknown or expired `session_id`. Call `browser_navigate` again.",
                retryable: false
            )
        }
        return ToolEnvelope.success(
            tool: composite,
            result: [
                "url": snap.url.absoluteString,
                "title": snap.title,
                "markdown": snap.markdown,
            ])
    }
}
