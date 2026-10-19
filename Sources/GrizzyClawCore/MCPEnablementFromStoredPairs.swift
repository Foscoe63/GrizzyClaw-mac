import Foundation

/// Decides whether a discovered `(server, tool)` is enabled given saved `mcpEnabledPairs` from `gui_chat_prefs.json`.
/// Aligns with “resolve stored rows against **current** discovery” (similar to registering MCP tools against live `list_tools`).
public enum MCPEnablementFromStoredPairs: Sendable {
    /// - `storedPairs` `nil` → nothing saved → all tools enabled.
    /// - empty array → treated like `nil` (all enabled). JSON often encodes “unset” as `[]`, which must not brick discovery.
    public static func isDiscoveredToolEnabled(
        storedPairs: [[String]]?,
        discoveredServer: String,
        discoveredTool: String,
        merged: MCPToolsDiscoveryResult
    ) -> Bool {
        guard let pairs = storedPairs, !pairs.isEmpty else { return true }
        let known = Array(merged.servers.keys)
        for row in pairs where row.count >= 2 {
            let cs = MCPIdentityResolution.canonicalServerName(modelOutput: row[0], knownServers: known)
            guard cs == discoveredServer else { continue }
            guard let toolNames = merged.servers[discoveredServer]?.map(\.name) else { continue }
            let ct = MCPIdentityResolution.canonicalToolName(modelOutput: row[1], knownTools: toolNames)
            if ct == discoveredTool { return true }
        }
        // Legacy prefs used `osaurus.<slug>` + tool name; catalog exposes `grizzyclaw_air` + `<slug>.<tool>`.
        if discoveredServer == GrizzyClawAirFirstPartyToolCatalog.airServerName {
            for row in pairs where row.count >= 2 {
                let rawSrv = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let rawTool = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard rawSrv.hasPrefix("osaurus.") else { continue }
                if GrizzyClawAirFirstPartyToolCatalog.airToolId(osaurusServer: rawSrv, osaurusTool: rawTool)
                    == discoveredTool
                {
                    return true
                }
            }
        }
        // Single-tool server: prefs still say e.g. `search` but MCP `list_tools` now reports a different id (package-specific).
        guard let nameList = merged.servers[discoveredServer], nameList.count == 1, nameList[0].name == discoveredTool else {
            return false
        }
        let toolNames = nameList.map(\.name)
        for row in pairs where row.count >= 2 {
            let cs = MCPIdentityResolution.canonicalServerName(modelOutput: row[0], knownServers: known)
            guard cs == discoveredServer else { continue }
            let ct = MCPIdentityResolution.canonicalToolName(modelOutput: row[1], knownTools: toolNames)
            if toolNames.contains(ct) {
                continue
            }
            return true
        }
        return false
    }
}
