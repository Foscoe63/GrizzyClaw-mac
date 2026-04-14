import AppKit
import GrizzyClawCore
import SwiftUI

/// `ps` / HTTP status checks must not run in a MainActor `TaskGroup` (Swift inherits the actor; the UI then freezes after the first toggle).
private enum MCPServerRunningMapRefresh {
    static func compute(servers: [MCPServerRow]) async -> [String: Bool] {
        var map: [String: Bool] = [:]
        // Run ps auxww once for all local servers to be efficient and avoid truncation issues.
        let psSnapshot = await Task.detached {
            MCPServerRuntimeStatus.fetchPSSnapshot()
        }.value

        await withTaskGroup(of: (String, Bool).self) { group in
            for row in servers {
                group.addTask {
                    let record = row.mergedRecord()
                    let ok: Bool
                    if let u = row.dictionary["url"] as? String, !u.isEmpty {
                        var hdr: [String: String] = [:]
                        if let h = row.dictionary["headers"] as? [String: Any] {
                            for (k, v) in h { hdr[String(describing: k)] = String(describing: v) }
                        }
                        ok = await MCPServerRuntimeStatus.isRemoteURLReachable(urlString: u, headers: hdr)
                    } else if row.dictionary["command"] != nil {
                        let eval = await Task.detached {
                            MCPServerRuntimeStatus.evaluateLocalRunning(serverData: record, psSnapshot: psSnapshot)
                        }.value
                        GrizzyClawLog.debug("MCP recomputeRunningMap local: \(eval.detail)")
                        ok = eval.running
                    } else {
                        ok = false
                    }
                    return (row.name, ok)
                }
            }
            for await pair in group {
                map[pair.0] = pair.1
            }
        }
        return map
    }
}

@MainActor
private enum MCPServersPreferencesCache {
    static var toolCountsByJSONPath: [String: [String: Int]] = [:]
    static var runningMapByJSONPath: [String: [String: Bool]] = [:]
}

/// Parity with Python `MCPTab` / `mcp_servers_dialog.py` — layout, JSON file, and core actions.
struct MCPServersPreferencesView: View {
    @ObservedObject var doc: ConfigYamlDocument
    /// Shared with the main chat toolbar so Tools ▾ shows the same discovery after editing MCP here.
    @ObservedObject var guiChatPrefs: GuiChatPrefsStore
    @ObservedObject private var mcpRunner = MCPLocalMCPProcessController.shared

    @Environment(\.colorScheme) private var colorScheme

    @State private var servers: [MCPServerRow] = []
    @State private var selectedName: String?
    @State private var quickAddText = ""
    @State private var toolCounts: [String: Int] = [:]
    @State private var loadError: String?
    @State private var busyDiscover = false
    @State private var editorPayload: MCPServerEditorPayload?
    @State private var confirmDeleteName: String?
    @State private var alertInfo: String?
    @State private var errorLogText: String?
    @State private var discoverPick: [MCPBonjourDiscovery.Entry]?
    @State private var marketplacePromptURL = false
    @State private var customMarketplaceURL = ""
    /// When non-nil, marketplace picker uses this URL for JSON fetch instead of the config field (custom menu).
    @State private var marketplaceRemoteURLOverride: String?
    @State private var marketplaceSheet = false
    @State private var discoverSelection: Int?
    /// Cached 🟢/🔴 status (expensive checks run off the main thread).
    @State private var runningMap: [String: Bool] = [:]
    /// After the user clicks stop, keep status 🔴 until `ps` no longer matches — `recomputeRunningMap` can
    /// immediately set `runningMap` back to true when patterns overlap (e.g. multiple `npx` MCPs) or the OS is slow to reap PIDs.
    @State private var statusSuppressedUntilPSClear: Set<String> = []
    @State private var testAllInProgress = false

    private var jsonURL: URL {
        MCPServersFileIO.resolveJSONURL(mcpServersFile: doc.string("mcp_servers_file", default: "~/.grizzyclaw/grizzyclaw.json"))
    }

    private var cacheKey: String {
        jsonURL.path
    }

    private var isDark: Bool {
        colorScheme == .dark
    }

    private var bg: Color { isDark ? Color(red: 0.12, green: 0.12, blue: 0.12) : Color(nsColor: .windowBackgroundColor) }
    private var fg: Color { isDark ? .white : Color(red: 0.11, green: 0.11, blue: 0.12) }
    private var secondary: Color { Color(nsColor: .secondaryLabelColor) }
    private var card: Color { isDark ? Color(red: 0.18, green: 0.18, blue: 0.18) : Color(red: 0.98, green: 0.98, blue: 0.98) }
    private var border: Color { isDark ? Color(red: 0.23, green: 0.23, blue: 0.24) : Color(red: 0.90, green: 0.90, blue: 0.92) }
    private var accent: Color { Color(nsColor: .controlAccentColor) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("MCP Servers")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(fg)
                Text("Model Context Protocol servers for extended tools.")
                    .font(.system(size: 13))
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)

                mcpCard
            }
            .padding(EdgeInsets(top: 20, leading: 24, bottom: 24, trailing: 24))
            .frame(maxWidth: MCPServersPreferencesView.maxContentWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg)
        .onAppear {
            toolCounts = MCPServersPreferencesCache.toolCountsByJSONPath[cacheKey] ?? [:]
            runningMap = MCPServersPreferencesCache.runningMapByJSONPath[cacheKey] ?? [:]
            reloadMCPFile()
            Task {
                await refreshToolCounts()
                await recomputeRunningMap()
            }
        }
        .sheet(item: $editorPayload) { payload in
            MCPServerEditorSheet(
                payload: payload,
                onSave: { row, originalName in
                    applyEditor(row: row, originalName: originalName)
                    editorPayload = nil
                },
                onCancel: { editorPayload = nil }
            )
        }
        .alert("GrizzyClaw", isPresented: Binding(
            get: { alertInfo != nil },
            set: { if !$0 { alertInfo = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertInfo ?? "")
        }
        .confirmationDialog(
            "Delete MCP server?",
            isPresented: Binding(
                get: { confirmDeleteName != nil },
                set: { if !$0 { confirmDeleteName = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let n = confirmDeleteName { removeServer(named: n) }
                confirmDeleteName = nil
            }
            Button("Cancel", role: .cancel) { confirmDeleteName = nil }
        } message: {
            if let n = confirmDeleteName {
                Text("Delete “\(n)” from the MCP JSON file?")
            }
        }
        .sheet(isPresented: Binding(
            get: { errorLogText != nil },
            set: { if !$0 { errorLogText = nil } }
        )) {
            errorLogSheet
        }
        .sheet(isPresented: Binding(
            get: { discoverPick != nil },
            set: { if !$0 { discoverPick = nil } }
        )) {
            discoverSheet
        }
        .sheet(isPresented: $marketplaceSheet, onDismiss: { marketplaceRemoteURLOverride = nil }) {
            MCPMarketplacePickerView(
                existingNamesLowercased: Set(servers.map { $0.name.lowercased() }),
                optionalRemoteMarketplaceURL: marketplaceRemoteURLOverride ?? doc.optionalString("mcp_marketplace_url"),
                onAdd: { row in applyMarketplaceInstall(row) },
                onClose: { marketplaceSheet = false }
            )
        }
        .alert("Custom Marketplace URL", isPresented: $marketplacePromptURL) {
            TextField("URL", text: $customMarketplaceURL)
            Button("Browse & add…") {
                let t = customMarketplaceURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let u = URL(string: t), u.scheme == "http" || u.scheme == "https" else {
                    alertInfo = "Enter a valid http(s) URL to a JSON marketplace."
                    marketplacePromptURL = false
                    return
                }
                marketplaceRemoteURLOverride = t
                marketplacePromptURL = false
                marketplaceSheet = true
            }
            Button("Cancel", role: .cancel) { marketplacePromptURL = false }
        } message: {
            Text("Enter a JSON URL listing MCP servers (same format as Python GrizzyClaw). You can browse the list and add servers without opening a browser.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .mcpLocalProcessExitedEarly)) { note in
            let name = (note.userInfo?["name"] as? String) ?? "MCP server"
            let detail = (note.userInfo?["detail"] as? String) ?? ""
            alertInfo = "\(name) exited\n\n\(detail)"
            Task { await recomputeRunningMap() }
        }
    }

    private static let maxContentWidth: CGFloat = 680

    private var mcpCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🔌 MCP Servers")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(fg)
            Text("Add and manage MCP servers using the official Swift MCP SDK (HTTP + stdio), like Osaurus — no Python required for discovery or tool calls. Set GRIZZYCLAW_MCP_USE_PYTHON=1 to force the legacy Python helpers.")
                .font(.system(size: 12))
                .foregroundStyle(secondary)

            HStack(alignment: .firstTextBaseline) {
                Text("MCP Marketplace URL:")
                    .foregroundStyle(fg)
                TextField(
                    "Optional: JSON URL to auto-discover ClawHub MCP servers",
                    text: doc.bindingOptionalStringNull("mcp_marketplace_url")
                )
                .textFieldStyle(.roundedBorder)
                .frame(height: 32)
            }
            Text("Leave empty to use built-in list. In chat, use skill mcp_marketplace → discover / install.")
                .font(.system(size: 11))
                .foregroundStyle(secondary)
            Link("How to add MCP servers", destination: URL(string: "https://modelcontextprotocol.io/introduction")!)
                .font(.system(size: 12))
                .tint(accent)

            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            serverTable

            Text(
                "Use: enable/disable server for all model providers.  🟢 Running  🔴 Stopped  •  "
                    + "Disabled servers are not loaded by LM Studio, OpenAI, or any other provider."
            )
            .font(.system(size: 11))
            .foregroundStyle(secondary)
            .padding(.vertical, 4)

            HStack {
                TextField(
                    "Paste URL or command (e.g. npx -y @modelcontextprotocol/server-foo or https://...)",
                    text: $quickAddText
                )
                .textFieldStyle(.roundedBorder)
                Button("Quick add") {
                    quickAdd()
                }
                .help("Parse URL or command and open Add Server with suggested name and config; Test before saving.")
            }

            marketplaceAndActionsRow
            secondRowButtons
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(card)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(border, lineWidth: 1)
                )
        )
    }

    private var serverTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Server").frame(maxWidth: .infinity, alignment: .leading)
                Text("Use").frame(width: 42)
                Text("Status").frame(width: 45)
                Text("Tools").frame(width: 47)
                Text("Test").frame(width: 40)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isDark ? Color(red: 0.23, green: 0.23, blue: 0.24) : Color(red: 0.96, green: 0.96, blue: 0.97))

            Divider()

            ForEach(servers) { row in
                mcpRow(row)
                Divider().opacity(0.35)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(border, lineWidth: 1)
        )
        .frame(minHeight: 240)
        .frame(maxHeight: 400)
    }

    private func displayName(for row: MCPServerRow) -> String {
        var n = row.name
        if row.dictionary["url"] != nil {
            n += " 🌐"
        }
        return n
    }

    private func effectiveRunning(_ row: MCPServerRow) -> Bool {
        if mcpRunner.isTrackedRunning(name: row.name) { return true }
        if statusSuppressedUntilPSClear.contains(row.name) { return false }
        return runningMap[row.name] ?? false
    }

    private func mcpRow(_ row: MCPServerRow) -> some View {
        let running = effectiveRunning(row)

        return HStack(spacing: 0) {
            Text(displayName(for: row))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(fg)
                .padding(.leading, 8)
                .contentShape(Rectangle())
                .onTapGesture { selectedName = row.name }

            Toggle("", isOn: Binding(
                get: { row.enabled },
                set: { newVal in
                    setEnabled(name: row.name, enabled: newVal)
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 42)
            .help("Use this server for all model providers (LM Studio, OpenAI, etc.). Uncheck to disable.")

            Button {
                toggleMCPConnection(row)
            } label: {
                Text(running ? "🟢" : "🔴")
            }
            .buttonStyle(.borderless)
            .frame(width: 45)
            .help(
                row.dictionary["url"] != nil
                    ? "Click to test HTTP connection to this remote MCP URL."
                    : (running
                        ? "Running — click to stop (or use pgrep if started outside this window)."
                        : "Stopped — click to start the local MCP process (stdio). The agent can also start it when you use tools in chat.")
            )

            Text(toolCounts[row.name].map { String($0) } ?? "—")
                .frame(width: 47)
                .multilineTextAlignment(.center)
                .font(.system(size: 12, weight: .medium))

            Button("Test") {
                Task { await testOne(row) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(width: 40)
            .help("Test server and show tool count")
        }
        .padding(.vertical, 4)
        .background(selectedName == row.name ? accent.opacity(0.12) : Color.clear)
        .id("mcp-row-\(row.name)")
    }

    private var marketplaceAndActionsRow: some View {
        HStack(spacing: 8) {
            Button("+ Add Server") {
                editorPayload = MCPServerEditorPayload(originalName: nil, initial: nil)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Menu {
                Button("── Built-in ──") {}
                    .disabled(true)
                Button("  Built-in Marketplace") {
                    marketplaceRemoteURLOverride = nil
                    marketplaceSheet = true
                }
                Divider()
                Button("── GitHub Repositories ──") {}
                    .disabled(true)
                Button("  awesome-mcp-servers") {
                    openSafari("https://api.github.com/repos/appcypher/awesome-mcp-servers/contents")
                }
                Button("  Official MCP Examples") {
                    openSafari("https://modelcontextprotocol.io/examples")
                }
                Divider()
                Button("── Web Directories ──") {}
                    .disabled(true)
                Button("  mcp-awesome.com (1200+ servers)") { openSafari("https://mcp-awesome.com") }
                Button("  mcpservers.org") { openSafari("https://mcpservers.org") }
                Button("  mcplist.ai") { openSafari("https://mcplist.ai") }
                Button("  mcp.so") { openSafari("https://mcp.so") }
                Button("  mcpnodes.com") { openSafari("https://mcpnodes.com") }
                Button("  agentmcp.net") { openSafari("https://agentmcp.net") }
                Divider()
                Button("── Custom ──") {}
                    .disabled(true)
                Button("  Enter custom URL…") {
                    customMarketplaceURL = doc.optionalString("mcp_marketplace_url")
                    marketplacePromptURL = true
                }
            } label: {
                Label("📦 Add from Marketplace…", systemImage: "chevron.down")
            }
            .frame(minWidth: 200)

            Button("Discover on network") {
                discoverNetwork()
            }
            .disabled(busyDiscover)
            .help("Find MCP servers on the local network (mDNS / ZeroConf; servers must advertise _mcp._tcp.local.)")

            Button("Edit") {
                guard let name = selectedName ?? servers.first?.name,
                      let row = servers.first(where: { $0.name == name }) else {
                    alertInfo = "Select an MCP server in the list first."
                    return
                }
                editorPayload = MCPServerEditorPayload(originalName: row.name, initial: row)
            }

            Button("Remove") {
                guard let name = selectedName ?? servers.first?.name else { return }
                confirmDeleteName = name
            }
            Spacer(minLength: 0)
        }
    }

    private var secondRowButtons: some View {
        HStack(spacing: 8) {
            Button("🔄 Refresh") {
                Task {
                    await refreshStatusesAndTools()
                }
            }
            .help("Refresh status and tool counts (uses the same discovery helper as chat).")

            Button("🧪 Test All") {
                Task {
                    await MainActor.run { testAllInProgress = true }
                    await testAllAsync()
                    await MainActor.run { testAllInProgress = false }
                }
            }
            .disabled(testAllInProgress)
            Button("📋 Error Log") {
                errorLogText = loadErrorLog()
            }
            .help("View recent errors for all MCP servers (~/.grizzyclaw/mcp_errors.json).")
            Spacer(minLength: 0)
        }
    }

    private var errorLogSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("📋 Recent MCP Server Errors")
                .font(.headline)
            Text("Errors are saved to ~/.grizzyclaw/mcp_errors.json (written by the Python GrizzyClaw app when discovery fails).")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(errorLogText ?? "")
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(errorLogText ?? "", forType: .string)
                }
                Spacer()
                Button("Close") { errorLogText = nil }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 360)
    }

    private var discoverSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add discovered server")
                .font(.headline)
            List(selection: $discoverSelection) {
                ForEach(Array((discoverPick ?? []).enumerated()), id: \.offset) { idx, e in
                    Text("\(e.name) — \(e.host):\(e.port)")
                        .tag(Optional(idx))
                }
            }
            HStack {
                Button("Add selected") {
                    guard let list = discoverPick,
                          let idx = discoverSelection,
                          idx >= 0, idx < list.count else { return }
                    let entry = list[idx]
                    let port = entry.port > 0 ? entry.port : 80
                    let host = entry.host
                    let url = "http://\(host):\(port)"
                    let safeName = entry.name.replacingOccurrences(of: " ", with: "_")
                    let row = MCPServerRow(name: String(safeName.prefix(64)), enabled: true, dictionary: ["url": url])
                    servers.append(row)
                    saveMCPFile()
                    discoverPick = nil
                    discoverSelection = nil
                    Task {
                        await refreshToolCounts()
                        await recomputeRunningMap()
                    }
                }
                Spacer()
                Button("Close") {
                    discoverPick = nil
                    discoverSelection = nil
                }
            }
        }
        .padding(16)
        .frame(minWidth: 400, minHeight: 280)
    }

    // MARK: - Actions

    private func reloadMCPFile() {
        loadError = nil
        do {
            var loaded = try MCPServersFileIO.load(url: jsonURL)
            var seen = Set<String>()
            loaded = loaded.filter { seen.insert($0.name).inserted }
            servers = loaded
            let names = Set(loaded.map(\.name))
            toolCounts = toolCounts.filter { names.contains($0.key) }
            runningMap = runningMap.filter { names.contains($0.key) }
            persistCachedViewState()
        } catch {
            loadError = error.localizedDescription
            servers = []
        }
    }

    private func saveMCPFile() {
        loadError = nil
        do {
            try MCPServersFileIO.save(url: jsonURL, servers: servers)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func setEnabled(name: String, enabled: Bool) {
        guard let i = servers.firstIndex(where: { $0.name == name }) else { return }
        servers[i].enabled = enabled
        saveMCPFile()
    }

    private func applyEditor(row: MCPServerRow, originalName: String?) {
        if let o = originalName, let idx = servers.firstIndex(where: { $0.name == o }) {
            if o != row.name {
                servers.remove(at: idx)
                servers.append(row)
            } else {
                servers[idx] = row
            }
        } else {
            servers.append(row)
        }
        servers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveMCPFile()
        Task {
            await refreshToolCounts()
            await recomputeRunningMap()
        }
    }

    private func removeServer(named: String) {
        servers.removeAll { $0.name == named }
        selectedName = nil
        saveMCPFile()
        Task {
            await refreshToolCounts()
            await recomputeRunningMap()
        }
    }

    private func quickAdd() {
        guard let d = MCPServersFileIO.parseQuickAdd(quickAddText) else {
            alertInfo = "Paste a URL (https://...) or command (e.g. npx -y @modelcontextprotocol/server-foo) first."
            return
        }
        let name = (d["name"] as? String) ?? "mcp_server"
        var dict = d
        dict.removeValue(forKey: "name")
        editorPayload = MCPServerEditorPayload(
            originalName: nil,
            initial: MCPServerRow(name: name, enabled: true, dictionary: dict)
        )
        quickAddText = ""
    }

    private func openSafari(_ s: String) {
        if let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }

    private func applyMarketplaceInstall(_ row: MCPServerRow) {
        let key = row.name.lowercased()
        if servers.contains(where: { $0.name.lowercased() == key }) {
            alertInfo = "An MCP server named “\(row.name)” is already in the list."
            return
        }
        servers.append(row)
        servers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveMCPFile()
        Task {
            await refreshToolCounts()
            await recomputeRunningMap()
        }
    }

    private func discoverNetwork() {
        busyDiscover = true
        Task {
            let found = await MCPBonjourDiscovery.discover(timeoutSeconds: 5)
            await MainActor.run {
                busyDiscover = false
                if found.isEmpty {
                    alertInfo = "No MCP servers found. Servers must advertise _mcp._tcp on the local network (ZeroConf). If you use Python GrizzyClaw, ensure `zeroconf` is installed for identical discovery."
                } else {
                    discoverPick = found
                }
            }
        }
    }

    private func refreshStatusesAndTools() async {
        await refreshToolCounts()
        await recomputeRunningMap()
    }

    /// Python `toggle_mcp_connection`: remote rows → connection check; local `command` → start/stop via `MCPLocalMCPProcessController`.
    private func toggleMCPConnection(_ row: MCPServerRow) {
        if let u = row.dictionary["url"] as? String, !u.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var hdr: [String: String] = [:]
            if let h = row.dictionary["headers"] as? [String: Any] {
                for (k, v) in h { hdr[String(describing: k)] = String(describing: v) }
            }
            Task {
                let ok = await MCPServerRuntimeStatus.isRemoteURLReachable(urlString: u, headers: hdr)
                await MainActor.run {
                    alertInfo = ok
                        ? "Remote MCP “\(row.name)” is reachable."
                        : "Remote MCP “\(row.name)” is not reachable. Check the URL, headers, and network."
                }
                await recomputeRunningMap()
            }
            return
        }
        guard row.dictionary["command"] != nil else {
            alertInfo = "No command or URL configured for “\(row.name)”."
            return
        }
        if effectiveRunning(row) {
            let snapshot = row
            Task {
                let rec = snapshot.mergedRecord()
                await mcpRunner.stopAwaitingCompletion(serverData: rec)
                await MainActor.run {
                    var next = runningMap
                    next[snapshot.name] = false
                    runningMap = next
                    statusSuppressedUntilPSClear.insert(snapshot.name)
                    persistCachedViewState()
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
                await recomputeRunningMap()
            }
            return
        }
        let snapshot = row
        Task {
            _ = await MainActor.run { () -> Void in
                statusSuppressedUntilPSClear.remove(snapshot.name)
            }
            let rec = snapshot.mergedRecord()
            do {
                try await mcpRunner.start(serverData: rec)
                GrizzyClawLog.debug("MCP toggle after start: name=\(snapshot.name) isTrackedRunning=\(mcpRunner.isTrackedRunning(name: snapshot.name))")
                await recomputeRunningMap()
            } catch {
                await MainActor.run { alertInfo = error.localizedDescription }
            }
        }
    }

    private func recomputeRunningMap() async {
        let list = await MainActor.run { servers }
        let psMap = await MCPServerRunningMapRefresh.compute(servers: list)
        let rowsSnapshot = await MainActor.run { servers }
        let summary = psMap.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
        GrizzyClawLog.debug("MCP recomputeRunningMap summary (psMap): \(summary)")
        await MainActor.run {
            // Merge ps-map into runningMap, but let the PID-based tracker always win.
            // If mcpRunner.isTrackedRunning says a server is running, force it green
            // regardless of what the broad ps-pattern scan returned for other servers.
            // This prevents cross-pattern contamination (e.g. two npx servers where one
            // server's patterns match the other's process) from flipping states incorrectly.
            var merged = psMap
            for row in rowsSnapshot {
                if mcpRunner.isTrackedRunning(name: row.name) {
                    merged[row.name] = true
                }
            }
            runningMap = merged
            // Drop suppression only once ps no longer matches AND the tracker agrees it stopped.
            statusSuppressedUntilPSClear = statusSuppressedUntilPSClear.filter {
                merged[$0] == true
            }
            persistCachedViewState()
        }
        mcpRunner.reconcilePsGhosts(rows: rowsSnapshot)
    }

    private func refreshToolCounts() async {
        let path = doc.string("mcp_servers_file", default: "~/.grizzyclaw/grizzyclaw.json")
        do {
            let r = try await MCPToolsDiscovery.discover(mcpServersFile: path)
            var counts: [String: Int] = [:]
            for (k, v) in r.servers { counts[k] = v.count }
            await MainActor.run {
                toolCounts = counts
                persistCachedViewState()
            }
        } catch {
            await MainActor.run {
                persistCachedViewState()
            }
        }
    }

    private func testOne(_ row: MCPServerRow) async {
        let path = await MainActor.run {
            doc.string("mcp_servers_file", default: "~/.grizzyclaw/grizzyclaw.json")
        }
        let rowName = row.name
        do {
            // Only probe this server — full-file discovery connects to every enabled server and can hang or fail silently.
            let r = try await MCPToolsDiscovery.discover(mcpServersFile: path, onlyServerNames: Set([rowName]))
            let n = r.servers[rowName]?.count ?? 0
            if let err = r.errorMessage, !err.isEmpty {
                await MainActor.run { presentMcpSheetAlert(title: "MCP test", message: "Test: \(rowName)\n\(err)") }
            } else {
                await MainActor.run {
                    var next = toolCounts
                    next[rowName] = n
                    toolCounts = next
                    persistCachedViewState()
                    presentMcpSheetAlert(title: "MCP test", message: "Test: \(rowName)\nOK — \(n) tools")
                }
            }
        } catch {
            await MainActor.run {
                presentMcpSheetAlert(title: "MCP test", message: "Test: \(rowName)\n\(error.localizedDescription)")
            }
        }
    }

    /// SwiftUI `.alert` often fails to present from nested Preferences tabs; use AppKit like `testAllAsync`.
    private func presentMcpSheetAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Status checks + one tool-discovery pass — work is **async** so the main thread never blocks (unlike the old synchronous `testAll`).
    private func testAllAsync() async {
        let rows = await MainActor.run { servers }
        let jsonPath = await MainActor.run { jsonURL.path }
        let mcpCount = rows.count
        var statusByName: [String: Bool] = [:]
        await withTaskGroup(of: (String, Bool).self) { group in
            for row in rows {
                group.addTask {
                    let record = row.mergedRecord()
                    let ok: Bool
                    if let u = row.dictionary["url"] as? String, !u.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        var hdr: [String: String] = [:]
                        if let h = row.dictionary["headers"] as? [String: Any] {
                            for (k, v) in h { hdr[String(describing: k)] = String(describing: v) }
                        }
                        ok = await MCPServerRuntimeStatus.isRemoteURLReachable(urlString: u, headers: hdr)
                    } else if row.dictionary["command"] != nil {
                        let eval = await Task.detached {
                            MCPServerRuntimeStatus.evaluateLocalRunning(serverData: record)
                        }.value
                        GrizzyClawLog.debug("MCP testAllAsync local: \(eval.detail)")
                        ok = eval.running
                    } else {
                        ok = false
                    }
                    return (row.name, ok)
                }
            }
            for await (name, ok) in group {
                statusByName[name] = ok
            }
        }
        var running = 0
        var lines: [String] = []
        for row in rows {
            let ok = statusByName[row.name] ?? false
            if ok { running += 1 }
            lines.append("  \(row.name): \(ok ? "✓ running" : "✗ stopped")")
        }
        let names = rows.map(\.name).prefix(5).joined(separator: ", ")
        let path = await MainActor.run {
            doc.string("mcp_servers_file", default: "~/.grizzyclaw/grizzyclaw.json")
        }
        var toolSummary = ""
        do {
            let r = try await MCPToolsDiscovery.discover(mcpServersFile: path)
            let totalTools = r.servers.values.reduce(0) { $0 + $1.count }
            toolSummary = "\n\nTool discovery: \(totalTools) tools listed across \(r.servers.count) server(s)."
            if let e = r.errorMessage, !e.isEmpty {
                toolSummary += "\nDiscovery note: \(e)"
            }
            await MainActor.run {
                var next = toolCounts
                for (k, v) in r.servers { next[k] = v.count }
                toolCounts = next
                persistCachedViewState()
            }
        } catch {
            toolSummary = "\n\nTool discovery failed: \(error.localizedDescription)"
        }
        let body = """
        MCP File: \(jsonPath)
        Configured: \(mcpCount)
        Reachable / process running: \(running)/\(mcpCount)

        Status:
        \(lines.joined(separator: "\n"))

        Names: \(names.isEmpty ? "none" : names)\(toolSummary)
        """
        await MainActor.run {
            // AppKit alert: SwiftUI `.alert` on nested Preferences tabs often does not present on macOS.
            // Parity with Python `QMessageBox.information(self, "Test MCP", msg)`.
            let alert = NSAlert()
            alert.messageText = "Test MCP"
            alert.informativeText = body
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func loadErrorLog() -> String {
        let url = GrizzyClawPaths.userDataDirectory.appendingPathComponent("mcp_errors.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let errors = obj["errors"] as? [String: Any], !errors.isEmpty
        else {
            return "✅ No errors recorded.\n\nErrors will appear here when MCP server connections or tool discoveries fail (typically when using the Python GrizzyClaw app)."
        }
        var lines: [String] = []
        for name in errors.keys.sorted() {
            lines.append("━━━ \(name) ━━━")
            if let val = errors[name] {
                if let arr = val as? [[String: Any]] {
                    for e in arr.reversed().prefix(5) {
                        let t = e["time"] as? String ?? ""
                        let msg = e["error"] as? String ?? "\(e)"
                        lines.append("  [\(t)]")
                        lines.append("  • \(msg)")
                    }
                } else if let s = val as? String {
                    lines.append("  • \(s)")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func persistCachedViewState() {
        MCPServersPreferencesCache.toolCountsByJSONPath[cacheKey] = toolCounts
        MCPServersPreferencesCache.runningMapByJSONPath[cacheKey] = runningMap
    }
}

// MARK: - Editor payload

struct MCPServerEditorPayload: Identifiable {
    let id = UUID()
    var originalName: String?
    var initial: MCPServerRow?
}

struct MCPServerEditorSheet: View {
    var payload: MCPServerEditorPayload
    var onSave: (MCPServerRow, String?) -> Void
    var onCancel: () -> Void

    @State private var name: String = ""
    @State private var remote = false
    @State private var url = ""
    @State private var headersJSON = ""
    @State private var command = ""
    @State private var argsText = ""
    @State private var envText = ""
    @State private var timeoutText = ""
    @State private var maxConcText = ""
    @State private var fsAllow = ""
    @State private var validating = false
    @State private var validateAlertMessage: String?
    @State private var saveErrorAlert: String?

    private static let labelWidth: CGFloat = 148

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(payload.originalName != nil ? "Edit MCP Server" : "Add MCP Server")
                .font(.system(size: 13, weight: .semibold))

            ScrollView {
                mcpFormRows
            }
            .frame(maxHeight: 380)

            HStack {
                Spacer(minLength: 0)
                Button("Validate") { validate() }
                    .disabled(validating)
                    .help("Test connection / list tools before saving")
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(validating)
                Button("Cancel", role: .cancel) { onCancel() }
                    .disabled(validating)
            }
        }
        .padding(EdgeInsets(top: 30, leading: 30, bottom: 30, trailing: 30))
        .frame(width: 560, height: 520)
        .onAppear {
            if let row = payload.initial {
                name = row.name
                remote = row.dictionary["url"] != nil
                url = (row.dictionary["url"] as? String) ?? ""
                if let h = row.dictionary["headers"] as? [String: Any],
                   let data = try? JSONSerialization.data(withJSONObject: h, options: [.prettyPrinted]),
                   let s = String(data: data, encoding: .utf8) {
                    headersJSON = s
                }
                command = (row.dictionary["command"] as? String) ?? ""
                let rawArgs = MCPServerRuntimeStatus.normalizeMCPArgs(row.dictionary["args"])
                let split = MCPServerRuntimeStatus.splitAllowFromArgs(rawArgs)
                argsText = split.remainingArgs.joined(separator: " ")
                if !split.allowPaths.isEmpty {
                    fsAllow = split.allowPaths.joined(separator: ", ")
                }
                if let env = row.dictionary["env"] as? [String: Any] {
                    envText = env.keys.sorted().map { k in "\(k)=\(env[k]!)" }.joined(separator: "\n")
                }
                if let t = row.dictionary["timeout_s"] as? Int { timeoutText = String(t) }
                if let m = row.dictionary["max_concurrency"] as? Int { maxConcText = String(m) }
            }
        }
        .alert("Validate", isPresented: Binding(
            get: { validateAlertMessage != nil },
            set: { if !$0 { validateAlertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { validateAlertMessage = nil }
        } message: {
            if let validateAlertMessage {
                Text(validateAlertMessage)
            }
        }
        .alert("Error", isPresented: Binding(
            get: { saveErrorAlert != nil },
            set: { if !$0 { saveErrorAlert = nil } }
        )) {
            Button("OK", role: .cancel) { saveErrorAlert = nil }
        } message: {
            if let saveErrorAlert {
                Text(saveErrorAlert)
            }
        }
    }

    @ViewBuilder
    private var mcpFormRows: some View {
        mcpLabeledRow("Name:") {
            TextField("", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(height: 32)
        }
        mcpLabeledRow("Remote:", alignment: .center) {
            Toggle("Remote MCP", isOn: $remote)
                .toggleStyle(.checkbox)
        }
        if remote {
            mcpLabeledRow("URL:") {
                TextField("", text: $url, prompt: Text("https://huggingface.co/mcp"))
                    .textFieldStyle(.roundedBorder)
                    .frame(height: 32)
            }
            mcpLabeledRow("Headers JSON:") {
                ZStack(alignment: .topLeading) {
                    if headersJSON.isEmpty {
                        Text(#"{"Authorization": "Bearer hf_your_token"}"#)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.65))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $headersJSON)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(height: 80)
                }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35), lineWidth: 1))
            }
        } else {
            mcpLabeledRow("Command:") {
                TextField("", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .frame(height: 32)
            }
            mcpLabeledRow("Arguments:") {
                ZStack(alignment: .topLeading) {
                    if argsText.isEmpty {
                        Text("Space-separated e.g. --port 8000 -m mcp_server")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.65))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $argsText)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(height: 120)
                }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35), lineWidth: 1))
            }
            mcpLabeledRow("Environment:") {
                ZStack(alignment: .topLeading) {
                    if envText.isEmpty {
                        Text("KEY=value (one per line)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary.opacity(0.65))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $envText)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(height: 80)
                }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.35), lineWidth: 1))
            }
            mcpLabeledRow("Default tool timeout (s):") {
                TextField("", text: $timeoutText, prompt: Text("e.g. 60 (5–300)"))
                    .textFieldStyle(.roundedBorder)
                    .frame(height: 28)
            }
            mcpLabeledRow("Max concurrent calls:") {
                TextField("", text: $maxConcText, prompt: Text("optional, e.g. 2"))
                    .textFieldStyle(.roundedBorder)
                    .frame(height: 28)
            }
            mcpLabeledRow("Filesystem allow paths:") {
                TextField("", text: $fsAllow, prompt: Text("For fast-filesystem: /Users/you/Documents, /Volumes/Storage"))
                    .textFieldStyle(.roundedBorder)
                    .frame(height: 28)
            }
            mcpLabeledRow("", alignment: .center) {
                Button("Pick folders…") { pickFolders() }
                    .help("Add folders to '--allow' (fast-filesystem)")
            }
        }
    }

    private func mcpLabeledRow<Content: View>(
        _ label: String,
        alignment: VerticalAlignment = .top,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: 12) {
            Text(label)
                .frame(width: Self.labelWidth, alignment: .trailing)
                .padding(.top, alignment == .top ? 6 : 0)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func parseEnv() -> [String: String] {
        let t = envText.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return [:] }
        if t.hasPrefix("{"), let data = t.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj.mapValues { String(describing: $0) }
        }
        var out: [String: String] = [:]
        for line in t.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(line)
            if line.hasPrefix("#") { continue }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                out[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        return out
    }

    private func pickFolders() {
        let p = NSOpenPanel()
        p.canChooseFiles = false
        p.canChooseDirectories = true
        p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let u = p.url else { return }
        let path = u.path
        var parts = fsAllow.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !parts.contains(path) { parts.append(path) }
        fsAllow = parts.joined(separator: ", ")
    }

    /// Args as persisted — normalized Arguments text plus `--allow` pairs from Filesystem allow paths (Python `get_config`).
    private func mergedLocalArgsForSave() -> [String] {
        var args = MCPServerRuntimeStatus.normalizeMCPArgs(argsText)
        let paths = fsAllow.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        for p in paths {
            args.append(contentsOf: ["--allow", p])
        }
        return args
    }

    private func validate() {
        if remote {
            guard !url.trimmingCharacters(in: .whitespaces).isEmpty else {
                validateAlertMessage = "Enter URL first."
                return
            }
            if !headersJSON.isEmpty {
                guard (try? JSONSerialization.jsonObject(with: Data(headersJSON.utf8))) is [String: Any] else {
                    validateAlertMessage = "Invalid headers JSON."
                    return
                }
            }
            var hdr: [String: String] = [:]
            if let data = headersJSON.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (k, v) in obj { hdr[String(describing: k)] = String(describing: v) }
            }
            Task {
                await MainActor.run { validating = true }
                do {
                    let n = try await GrizzyMCPNativeRuntime.shared.testRemote(urlString: url, headers: hdr)
                    await MainActor.run {
                        validating = false
                        validateAlertMessage = "OK — listed \(n) tool(s) via Swift MCP (same stack as Osaurus)."
                    }
                } catch {
                    await MainActor.run {
                        validating = false
                        validateAlertMessage = error.localizedDescription
                    }
                }
            }
        } else {
            guard !command.trimmingCharacters(in: .whitespaces).isEmpty else {
                validateAlertMessage = "Enter command first."
                return
            }
            let env = parseEnv()
            let argsForValidate = MCPServerRuntimeStatus.normalizeMCPArgs(argsText)
            Task {
                await MainActor.run { validating = true }
                do {
                    let n = try await GrizzyMCPNativeRuntime.shared.testLocal(
                        command: command,
                        args: mergedLocalArgsForSave(),
                        env: env
                    )
                    await MainActor.run {
                        validating = false
                        validateAlertMessage = "OK — listed \(n) tool(s) via Swift MCP stdio."
                    }
                } catch {
                    let legacy = await MCPToolsDiscovery.validateStdioConfiguration(
                        command: command,
                        args: argsForValidate,
                        env: env
                    )
                    await MainActor.run {
                        validating = false
                        if legacy.ok {
                            validateAlertMessage = "Python fallback: \(legacy.message)"
                        } else {
                            validateAlertMessage =
                                "Swift MCP: \(error.localizedDescription)\nPython: \(legacy.message)"
                        }
                    }
                }
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { saveErrorAlert = "Name is required."; return }
        if remote {
            guard !url.trimmingCharacters(in: .whitespaces).isEmpty else {
                saveErrorAlert = "URL required for remote."
                return
            }
            if !headersJSON.isEmpty {
                guard (try? JSONSerialization.jsonObject(with: Data(headersJSON.utf8))) is [String: Any] else {
                    saveErrorAlert = "Invalid headers JSON."
                    return
                }
            }
            var hdr: [String: Any] = [:]
            if let data = headersJSON.data(using: .utf8),
               let h = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                hdr = h
            }
            var dict: [String: Any] = ["url": url.trimmingCharacters(in: .whitespaces)]
            if !hdr.isEmpty { dict["headers"] = hdr }
            let row = MCPServerRow(name: n, enabled: payload.initial?.enabled ?? true, dictionary: dict)
            onSave(row, payload.originalName)
            return
        }
        let args = mergedLocalArgsForSave()
        let env = parseEnv()
        var dict: [String: Any] = [
            "command": command.trimmingCharacters(in: .whitespaces),
            "args": args,
            "env": env,
        ]
        if let t = Int(timeoutText.trimmingCharacters(in: .whitespaces)), t > 0 {
            dict["timeout_s"] = min(300, max(5, t))
        }
        if let m = Int(maxConcText.trimmingCharacters(in: .whitespaces)), m > 0 {
            dict["max_concurrency"] = min(16, max(1, m))
        }
        let row = MCPServerRow(name: n, enabled: payload.initial?.enabled ?? true, dictionary: dict)
        onSave(row, payload.originalName)
    }
}
