import Foundation
import GrizzyClawCore

/// In-memory key for `(server, tool)` toggles; must match `MCPToolsDiscovery` / chat tool identity (`\u{1E}`).
public enum WorkspaceToolAllowlistKey {
    public static func composite(server: String, tool: String) -> String {
        "\(server)\u{1E}\(tool)"
    }

    public static func toolSwitchMap(
        discovered: [String: [MCPToolDescriptor]],
        capPairs: [(String, String)]?
    ) -> [String: Bool] {
        let capSet: Set<String>? = capPairs.map { pairs in
            Set(pairs.map { composite(server: $0.0, tool: $0.1) })
        }
        var next: [String: Bool] = [:]
        for (srv, pairs) in discovered {
            for p in pairs {
                let key = composite(server: srv, tool: p.name)
                if let s = capSet {
                    next[key] = s.contains(key)
                } else {
                    next[key] = true
                }
            }
        }
        return next
    }

    /// Minimal discovery map from persisted `mcp_tool_allowlist` (descriptions empty until refresh).
    public static func discoveredToolsFromAllowlistPairs(_ pairs: [(String, String)]) -> [String: [MCPToolDescriptor]] {
        var dict: [String: [MCPToolDescriptor]] = [:]
        for (srv, tool) in pairs {
            guard !srv.isEmpty, !tool.isEmpty else { continue }
            dict[srv, default: []].append(MCPToolDescriptor(name: tool, description: ""))
        }
        for srv in dict.keys {
            dict[srv]?.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return dict
    }
}
