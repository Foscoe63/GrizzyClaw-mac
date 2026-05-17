import XCTest
@testable import GrizzyClawCore

final class MCPToolsDiscoveryTests: XCTestCase {
    func testProbeRowsSkipsDisabledServers() {
        let rows = [
            MCPServerRow(name: "enabled-1", enabled: true, dictionary: ["url": "https://example.com/a"]),
            MCPServerRow(name: "disabled-1", enabled: false, dictionary: ["url": "https://example.com/b"]),
            MCPServerRow(name: "enabled-2", enabled: true, dictionary: ["url": "https://example.com/c"]),
        ]

        let probed = MCPToolsDiscovery.probeRows(rows: rows)
        XCTAssertEqual(probed.map(\.name), ["enabled-1", "enabled-2"])
    }

    func testProbeRowsWithFilterStillSkipsDisabledServers() {
        let rows = [
            MCPServerRow(name: "enabled-1", enabled: true, dictionary: ["url": "https://example.com/a"]),
            MCPServerRow(name: "disabled-1", enabled: false, dictionary: ["url": "https://example.com/b"]),
        ]

        let probed = MCPToolsDiscovery.probeRows(rows: rows, onlyServerNames: ["enabled-1", "disabled-1"])
        XCTAssertEqual(probed.map(\.name), ["enabled-1"])
        XCTAssertTrue(probed.allSatisfy(\.enabled))
    }

    func testProbeRowsOnIOSFiltersOutStdioServers() {
        let rows = [
            MCPServerRow(name: "remote", enabled: true, dictionary: ["url": "https://mcp.example/s"]),
            MCPServerRow(name: "local", enabled: true, dictionary: ["command": "npx", "args": ["-y", "@x/mcp"]]),
        ]
        let probed = MCPToolsDiscovery.probeRows(rows: rows)
#if os(iOS)
        XCTAssertEqual(probed.map(\.name), ["remote"])
#else
        XCTAssertEqual(Set(probed.map(\.name)), Set(["remote", "local"]))
#endif
    }

    func testIPadFirstPartyCatalogUsesGrizzyclawAirWithoutOsaurusServerKeys() {
        let d = GrizzyClawAirFirstPartyToolCatalog.iPadChatDiscovery()
        XCTAssertFalse(d.servers.isEmpty)
        XCTAssertNil(d.servers["osaurus.search"], "Model-facing catalog must not expose osaurus.* server keys.")
        XCTAssertNotNil(d.servers["grizzyclaw"])
        XCTAssertNotNil(d.servers[GrizzyClawAirFirstPartyToolCatalog.airServerName])
        XCTAssertTrue(
            d.servers[GrizzyClawAirFirstPartyToolCatalog.airServerName]?.contains(where: { $0.name == "search.search" })
                == true)
        let mapped = GrizzyClawAirFirstPartyToolCatalog.osaurusDelegation(
            server: GrizzyClawAirFirstPartyToolCatalog.airServerName,
            tool: "search.search"
        )
        XCTAssertEqual(mapped?.0, "osaurus.search")
        XCTAssertEqual(mapped?.1, "search")
    }

    func testAllowlistOsaurusAliasesExpandToAir() {
        let pairs = [("osaurus.search", "search")]
        let expanded = GrizzyClawAirFirstPartyToolCatalog.allowlistPairsIncludingAirAliases(pairs)
        XCTAssertTrue(expanded.contains { $0.0 == "grizzyclaw_air" && $0.1 == "search.search" })
    }

    func testBundledManifestMapsNotesSlugToAppleNotesTitle() {
        XCTAssertEqual(
            OsaurusBundledPluginToolRegistry.bundledAirSlugDisplayTitles["notes"],
            "Apple Notes"
        )
        XCTAssertEqual(GrizzyClawAirFirstPartyToolCatalog.displayTitle(forAirPluginSlug: "notes"), "Apple Notes")
    }
}
