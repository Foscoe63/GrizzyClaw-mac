import Foundation
import GrizzyClawCore

public enum WorkspaceToolDiscoveryBootstrap {
    /// Seeds `discoveredTools` / `toolSwitchOn` / `expandedToolServers` like the Mac workspace editor on first appear.
    @MainActor
    public static func seedIfNeeded(
        workspaceId: String,
        persistedCap: [(String, String)]?,
        discoveredTools: inout [String: [MCPToolDescriptor]],
        toolSwitchOn: inout [String: Bool],
        expandedToolServers: inout Set<String>,
        scheduleFullRefresh: @escaping () -> Void
    ) {
        guard discoveredTools.isEmpty else { return }

        if let cached = WorkspaceEditorMCPCache.discovery[workspaceId], !cached.isEmpty {
            discoveredTools = cached
            toolSwitchOn = WorkspaceToolAllowlistKey.toolSwitchMap(discovered: cached, capPairs: persistedCap)
            if !cached.isEmpty {
                expandedToolServers = Set(cached.keys.sorted().prefix(1))
            }
            return
        }

        if let pairs = persistedCap, !pairs.isEmpty {
            let seeded = WorkspaceToolAllowlistKey.discoveredToolsFromAllowlistPairs(pairs)
            discoveredTools = seeded
            toolSwitchOn = WorkspaceToolAllowlistKey.toolSwitchMap(discovered: seeded, capPairs: pairs)
            if !seeded.isEmpty {
                expandedToolServers = Set(seeded.keys.sorted().prefix(1))
            }
            scheduleFullRefresh()
            return
        }

        scheduleFullRefresh()
    }
}
