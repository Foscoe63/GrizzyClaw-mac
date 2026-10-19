import Foundation
import GrizzyClawCore

/// Executes tools advertised by bundled [osaurus-tools plugin manifests](https://github.com/osaurus-ai/osaurus-tools/tree/master/plugins)
/// using **native Swift** implementations inside Grizzy (no external plugin host).
public enum OsaurusBundledPluginToolHandlers {
    /// - Returns: JSON tool envelope string, or `nil` if `server` is not a bundled Osaurus plugin id.
    public static func bundledResultIfApplicable(
        server: String,
        tool: String,
        arguments: [String: Any]
    ) async -> String? {
        guard OsaurusBundledPluginToolRegistry.isBundledPluginServer(server) else { return nil }
        return await resultAsync(server: server, tool: tool, arguments: arguments)
    }

    /// Same as ``bundledResultIfApplicable(server:tool:arguments:)`` but safe to call from `@MainActor`
    /// with actor-isolated `[String: Any]` tool arguments (deep-copies via JSON before leaving the actor).
    @MainActor
    public static func bundledResultIfApplicableFromMainActor(
        server: String,
        tool: String,
        arguments: [String: Any]
    ) async -> String? {
        guard OsaurusBundledPluginToolRegistry.isBundledPluginServer(server) else { return nil }
        let argsData: Data
        if JSONSerialization.isValidJSONObject(arguments),
            let d = try? JSONSerialization.data(withJSONObject: arguments, options: [])
        {
            argsData = d
        } else {
            argsData = Data("{}".utf8)
        }
        let srv = server
        let tls = tool
        return await Task.detached { @Sendable in
            let argsCopy = (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]
            return await bundledResultIfApplicable(server: srv, tool: tls, arguments: argsCopy)
        }.value
    }

    /// Back-compat shim: only `osaurus.time` is resolved synchronously; other bundled servers return `nil`
    /// so callers should use ``bundledResultIfApplicable(server:tool:arguments:)``.
    public static func handleIfBundled(
        server: String,
        tool: String,
        arguments: [String: Any]
    ) -> String? {
        guard OsaurusBundledPluginToolRegistry.isBundledPluginServer(server) else { return nil }
        let srv = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if srv == "osaurus.time" {
            return OsaurusTimeBuiltinTools.result(tool: tool, arguments: arguments)
        }
        return nil
    }

    /// Unit tests and quick `osaurus.time` checks. Other servers return a failure asking for the async API.
    public static func result(
        server: String,
        tool: String,
        arguments: [String: Any]
    ) -> String {
        guard OsaurusBundledPluginToolRegistry.isBundledPluginServer(server) else {
            return ToolEnvelope.failure(
                tool: "\(server).\(tool)",
                kind: "unknown_server",
                message: "Not a bundled Osaurus server id.",
                retryable: false
            )
        }
        let srv = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if srv == "osaurus.time" {
            return OsaurusTimeBuiltinTools.result(tool: tool, arguments: arguments)
        }
        return ToolEnvelope.failure(
            tool: "\(srv).\(tool)",
            kind: "async_tool",
            message:
                "This bundled tool runs on the async path. Use `bundledResultIfApplicable` from chat code, or call the specific `Osaurus*BuiltinTools` helper in tests.",
            retryable: false
        )
    }

    private static func resultAsync(
        server: String,
        tool: String,
        arguments: [String: Any]
    ) async -> String {
        let srv = server.trimmingCharacters(in: .whitespacesAndNewlines)
        let composite = "\(srv).\(tool)"
        if srv == "osaurus.time" {
            return OsaurusTimeBuiltinTools.result(tool: tool, arguments: arguments)
        }
        switch srv {
        case "osaurus.fetch":
            return await OsaurusFetchBuiltinTools.result(tool: tool, arguments: arguments)
        case "osaurus.search":
            return await OsaurusSearchBuiltinTools.result(tool: tool, arguments: arguments)
        case "osaurus.maps":
            return await OsaurusMapsBuiltinTools.result(tool: tool, arguments: arguments)
        case "osaurus.browser":
            return await OsaurusBrowserBuiltinTools.result(tool: tool, arguments: arguments)
        case "osaurus.calendar":
            return await OsaurusEventKitBuiltinTools.calendar(tool: tool, arguments: arguments)
        case "osaurus.reminders":
            return await OsaurusEventKitBuiltinTools.reminders(tool: tool, arguments: arguments)
        case "osaurus.contacts":
            return await OsaurusContactsBuiltinTools.result(tool: tool, arguments: arguments)
        case "osaurus.vision":
            return await OsaurusVisionBuiltinTools.result(tool: tool, arguments: arguments)
        case "osaurus.images":
            return OsaurusImagesBuiltinTools.result(tool: tool, arguments: arguments)
        case "osaurus.telegram":
            return await OsaurusTelegramBuiltinTools.result(tool: tool, arguments: arguments)
        case "osaurus.resend":
            return await OsaurusResendBuiltinTools.result(tool: tool, arguments: arguments)
        case "osaurus.macos-use":
            return OsaurusMacOSUseBuiltinSubset.result(tool: tool, arguments: arguments)
        case "osaurus.mail", "osaurus.messages", "osaurus.notes":
            return ToolEnvelope.failure(
                tool: composite,
                kind: "not_available_builtin",
                message:
                    "Mail, Messages, and Apple Notes do not expose a supported automation API to third-party apps. Grizzy cannot drive those apps from built-in tools.",
                retryable: false
            )
        case "osaurus.emacs":
            return ToolEnvelope.failure(
                tool: composite,
                kind: "not_available_builtin",
                message:
                    "Emacs integration is not part of Grizzy's built-in toolset. Use local files and `fetch` for remote text sources instead.",
                retryable: false
            )
        case "osaurus.music":
            return ToolEnvelope.failure(
                tool: composite,
                kind: "not_available_builtin",
                message: "Apple Music control is not implemented as a built-in Grizzy tool yet.",
                retryable: false
            )
        case "osaurus.pptx", "osaurus.xlsx":
            return ToolEnvelope.failure(
                tool: composite,
                kind: "not_available_builtin",
                message:
                    "Office file tooling is not implemented inside Grizzy yet. Export to PDF/text externally if you need document extraction.",
                retryable: false
            )
        default:
            return ToolEnvelope.failure(
                tool: composite,
                kind: "not_available_builtin",
                message:
                    "Grizzy does not ship a built-in Swift implementation for this bundled plugin tool yet.",
                retryable: false
            )
        }
    }
}
