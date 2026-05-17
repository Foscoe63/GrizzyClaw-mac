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
        if !discoveredTools.isEmpty,
            GrizzyClawAirFirstPartyToolCatalog.cacheIncludesFirstPartyCatalog(discoveredTools)
        {
            return
        }

        let cached = WorkspaceEditorMCPCache.discovery[workspaceId]
        let seeded = GrizzyClawAirFirstPartyToolCatalog.workspaceEditorServers(
            cached: (cached?.isEmpty == false) ? cached : nil,
            allowlistSeed: persistedCap
        )
        discoveredTools = seeded
        let expandedCap = persistedCap.map {
            GrizzyClawAirFirstPartyToolCatalog.allowlistPairsIncludingAirAliases($0)
        }
        toolSwitchOn = WorkspaceToolAllowlistKey.toolSwitchMap(
            discovered: seeded, capPairs: expandedCap)
        if !seeded.isEmpty {
            expandedToolServers = Set(seeded.keys.sorted().prefix(1))
        }

        let needsRemoteProbe =
            cached == nil
            || (cached?.isEmpty == true)
            || !GrizzyClawAirFirstPartyToolCatalog.cacheIncludesFirstPartyCatalog(cached ?? [:])
        if needsRemoteProbe {
            scheduleFullRefresh()
        }
    }
}
