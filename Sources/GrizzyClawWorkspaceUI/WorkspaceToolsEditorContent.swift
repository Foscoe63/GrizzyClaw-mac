import GrizzyClawCore
import SwiftUI

/// Shared workspace MCP tool allowlist UI (Mac workspace editor + iPad workspace detail).
public struct WorkspaceToolsEditorContent: View {
    let workspaceId: String?
    @Binding var enforceToolAllowlist: Bool
    @Binding var discoveredTools: [String: [MCPToolDescriptor]]
    @Binding var toolSwitchOn: [String: Bool]
    @Binding var expandedToolServers: Set<String>
    var toolsRefreshing: Bool
    var toolsDiscoveryMessage: String?
    let mcpServersFileDisplay: String
    let persistedAllowlistCap: [(String, String)]?
    let onRefresh: () -> Void
    var showsLongFormHelp: Bool

    @State private var expandedAirPluginSlugs: Set<String> = []

    private var allToolsToggle: Binding<Bool> {
        Binding(
            get: {
                guard !discoveredTools.isEmpty else { return true }
                for (srv, tools) in discoveredTools {
                    for t in tools {
                        let k = WorkspaceToolAllowlistKey.composite(server: srv, tool: t.name)
                        if toolSwitchOn[k] ?? true == false {
                            return false
                        }
                    }
                }
                return true
            },
            set: { enabled in
                var next = toolSwitchOn
                for (srv, tools) in discoveredTools {
                    for t in tools {
                        let k = WorkspaceToolAllowlistKey.composite(server: srv, tool: t.name)
                        next[k] = enabled
                    }
                }
                toolSwitchOn = next
            }
        )
    }

    public init(
        workspaceId: String?,
        enforceToolAllowlist: Binding<Bool>,
        discoveredTools: Binding<[String: [MCPToolDescriptor]]>,
        toolSwitchOn: Binding<[String: Bool]>,
        expandedToolServers: Binding<Set<String>>,
        toolsRefreshing: Bool,
        toolsDiscoveryMessage: String?,
        mcpServersFileDisplay: String,
        persistedAllowlistCap: [(String, String)]?,
        onRefresh: @escaping () -> Void,
        showsLongFormHelp: Bool = true
    ) {
        self.workspaceId = workspaceId
        _enforceToolAllowlist = enforceToolAllowlist
        _discoveredTools = discoveredTools
        _toolSwitchOn = toolSwitchOn
        _expandedToolServers = expandedToolServers
        self.toolsRefreshing = toolsRefreshing
        self.toolsDiscoveryMessage = toolsDiscoveryMessage
        self.mcpServersFileDisplay = mcpServersFileDisplay
        self.persistedAllowlistCap = persistedAllowlistCap
        self.onRefresh = onRefresh
        self.showsLongFormHelp = showsLongFormHelp
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsLongFormHelp {
                Text("Workspace tool allowlist (hard cap)")
                    .font(.headline)
                Text(
                    "When enabled, this workspace can only call the tools you select here. "
                        + "The chat Tools dropdown can still filter further, but cannot enable anything outside this list. "
                        + "Discovery reads your MCP servers JSON and probes each enabled server."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
#if os(iOS)
                Text(
                    "On iPad, only MCP servers with http:// or https:// URLs are probed; stdio/command servers are omitted from discovery (and removed from the MCP JSON when you open MCP settings)."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
#endif
            }

            Text("MCP file: \(mcpServersFileDisplay)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)

            Toggle("Enforce allowlist for this workspace", isOn: $enforceToolAllowlist)

            Toggle("Enable all tools", isOn: allToolsToggle)
                .disabled(discoveredTools.isEmpty)

            HStack {
                Button("Enable all") {
                    var next = toolSwitchOn
                    for (srv, pairs) in discoveredTools {
                        for p in pairs {
                            next[WorkspaceToolAllowlistKey.composite(server: srv, tool: p.name)] = true
                        }
                    }
                    toolSwitchOn = next
                }
                .disabled(discoveredTools.isEmpty)

                Button("Disable all") {
                    var next = toolSwitchOn
                    for (srv, pairs) in discoveredTools {
                        for p in pairs {
                            next[WorkspaceToolAllowlistKey.composite(server: srv, tool: p.name)] = false
                        }
                    }
                    toolSwitchOn = next
                }
                .disabled(discoveredTools.isEmpty)

                Spacer()

                Button {
                    onRefresh()
                } label: {
                    if toolsRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Refresh")
                    }
                }
                .disabled(toolsRefreshing)
            }

            if let toolsDiscoveryMessage, !toolsDiscoveryMessage.isEmpty {
                Text(toolsDiscoveryMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if discoveredTools.isEmpty {
                Text("Tap Refresh to discover tools (built-in tools appear even with no MCP servers).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let sorted = discoveredTools.keys.sorted()
                let grizzly = sorted.filter { $0.lowercased() == "grizzyclaw" }
                let macuse = sorted.filter { $0.lowercased() == "macuse" }
                let others = sorted.filter {
                    $0.lowercased() != "grizzyclaw" && $0.lowercased() != "macuse"
                }

                if !grizzly.isEmpty {
                    Text("Built-in")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(grizzly, id: \.self) { srv in
                        mcpServerDisclosure(srv)
                    }
                }

                if !macuse.isEmpty {
                    Text("Osaurus-style (Macuse MCP)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, grizzly.isEmpty ? 0 : 8)
                    Text("Real Calendar, Mail, Notes, Reminders, etc. — requires Mac + Macuse installed; add from MCP preferences if missing.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(macuse, id: \.self) { srv in
                        mcpServerDisclosure(srv)
                    }
                }

                if !others.isEmpty {
                    Text("Other MCP servers")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, (grizzly.isEmpty && macuse.isEmpty) ? 0 : 8)
                    ForEach(others, id: \.self) { srv in
                        mcpServerDisclosure(srv)
                    }
                }
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .onAppear {
            guard let workspaceId else { return }
            var d = discoveredTools
            var t = toolSwitchOn
            var x = expandedToolServers
            WorkspaceToolDiscoveryBootstrap.seedIfNeeded(
                workspaceId: workspaceId,
                persistedCap: persistedAllowlistCap,
                discoveredTools: &d,
                toolSwitchOn: &t,
                expandedToolServers: &x,
                scheduleFullRefresh: onRefresh
            )
            discoveredTools = d
            toolSwitchOn = t
            expandedToolServers = x
        }
    }

    @ViewBuilder
    private func mcpServerDisclosure(_ srv: String) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedToolServers.contains(srv) },
                set: { on in
                    if on { expandedToolServers.insert(srv) } else { expandedToolServers.remove(srv) }
                }
            ),
            content: {
                if srv == GrizzyClawAirFirstPartyToolCatalog.airServerName {
                    grizzyAirToolsGrouped(srv: srv)
                } else {
                    let pairs = discoveredTools[srv] ?? []
                    ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                        toolToggleRow(server: srv, pair: pair)
                    }
                }
            },
            label: {
                HStack {
                    Text(srv)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(discoveredTools[srv]?.count ?? 0)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        )
    }

    /// First path segment of `grizzyclaw_air` tool ids (`notes.search_notes` → `notes`).
    private func airPluginSlug(fromAirToolName name: String) -> String {
        guard let dot = name.firstIndex(of: ".") else {
            return GrizzyClawAirFirstPartyToolCatalog.airToolUncategorizedSlug
        }
        return String(name[..<dot])
    }

    @ViewBuilder
    private func grizzyAirToolsGrouped(srv: String) -> some View {
        let pairs = discoveredTools[srv] ?? []
        let groups = Dictionary(grouping: pairs, by: { airPluginSlug(fromAirToolName: $0.name) })
        let sortedSlugs = groups.keys.sorted { a, b in
            GrizzyClawAirFirstPartyToolCatalog.displayTitle(forAirPluginSlug: a)
                .localizedCaseInsensitiveCompare(
                    GrizzyClawAirFirstPartyToolCatalog.displayTitle(forAirPluginSlug: b)
                ) == .orderedAscending
        }
        ForEach(sortedSlugs, id: \.self) { slug in
            let rows = (groups[slug] ?? []).sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedAirPluginSlugs.contains(slug) },
                    set: { on in
                        if on { expandedAirPluginSlugs.insert(slug) } else { expandedAirPluginSlugs.remove(slug) }
                    }
                ),
                content: {
                    ForEach(rows, id: \.name) { pair in
                        toolToggleRow(server: srv, pair: pair)
                    }
                },
                label: {
                    HStack {
                        Text(GrizzyClawAirFirstPartyToolCatalog.displayTitle(forAirPluginSlug: slug))
                            .font(.subheadline)
                        Spacer()
                        Text("\(rows.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            )
        }
    }

    @ViewBuilder
    private func toolToggleRow(server srv: String, pair: MCPToolDescriptor) -> some View {
        let key = WorkspaceToolAllowlistKey.composite(server: srv, tool: pair.name)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(pair.name)
                    .font(.body)
                if !pair.description.isEmpty {
                    Text(pair.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer()
            Toggle(
                "",
                isOn: Binding(
                    get: { toolSwitchOn[key] ?? true },
                    set: { toolSwitchOn[key] = $0 }
                )
            )
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
