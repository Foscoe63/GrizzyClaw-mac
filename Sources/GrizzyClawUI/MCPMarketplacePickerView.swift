import AppKit
import GrizzyClawCore
import SwiftUI

/// In-app MCP marketplace browser (parity with Python `MarketplaceDialog`).
struct MCPMarketplacePickerView: View {
    let existingNamesLowercased: Set<String>
    /// When non-empty, try this JSON URL first (Python `MarketplaceDialog` with `mcp_marketplace_url`).
    let optionalRemoteMarketplaceURL: String?
    let onAdd: (MCPServerRow) -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var loadPhase: LoadPhase = .loading
    @State private var allServers: [MCPMarketplaceServerEntry] = []
    @State private var searchText = ""
    @State private var categoryFilter = "All Categories"
    @State private var sortMode: SortMode = .featured
    @State private var selected: MCPMarketplaceServerEntry?
    @State private var statusLine = ""

    private enum LoadPhase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private enum SortMode: String, CaseIterable {
        case featured = "Featured"
        case name = "Name"
        case tools = "Tools"
        case category = "Category"
    }

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : Color(red: 0.11, green: 0.11, blue: 0.12) }
    private var secondary: Color { Color(nsColor: .secondaryLabelColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MCP Server Marketplace")
                .font(.system(size: 18, weight: .bold))
            Text("Browse and add MCP servers to ~/.grizzyclaw/grizzyclaw.json. ⭐ = featured (same list as Python GrizzyClaw).")
                .font(.system(size: 12))
                .foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)

            filterBar

            Group {
                switch loadPhase {
                case .loading:
                    ProgressView("Loading marketplace…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let msg):
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Could not load marketplace")
                            .font(.headline)
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready:
                    HSplitView {
                        listColumn
                            .frame(minWidth: 360)
                        detailColumn
                            .frame(minWidth: 280)
                    }
                    .frame(minHeight: 320)
                }
            }

            Text(statusLine)
                .font(.caption)
                .foregroundStyle(secondary)
                .lineLimit(3)

            HStack {
                Button("Add selected") { addSelected() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil || loadPhase != .ready)
                Spacer()
                Button("Close") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
        .task { await load() }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            TextField("Search name or description…", text: $searchText)
                .textFieldStyle(.roundedBorder)
            Picker("Category", selection: $categoryFilter) {
                Text("All Categories").tag("All Categories")
                Text("⭐ Featured").tag("⭐ Featured")
                ForEach(MCPMarketplacePresentation.categories, id: \.title) { c in
                    Text(c.title).tag(c.title)
                }
            }
            .frame(width: 200)
            Picker("Sort", selection: $sortMode) {
                ForEach(SortMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .frame(width: 120)
        }
    }

    private var filtered: [MCPMarketplaceServerEntry] {
        var rows = allServers.filter { !existingNamesLowercased.contains($0.name.lowercased()) }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            rows = rows.filter {
                $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
            }
        }
        if categoryFilter == "⭐ Featured" {
            rows = rows.filter { MCPMarketplacePresentation.isFeatured($0) }
        } else if categoryFilter != "All Categories" {
            rows = rows.filter { MCPMarketplacePresentation.category(for: $0) == categoryFilter }
        }
        switch sortMode {
        case .name:
            rows.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .tools:
            rows.sort {
                let a = MCPMarketplacePresentation.estimatedTools[$0.name] ?? 0
                let b = MCPMarketplacePresentation.estimatedTools[$1.name] ?? 0
                return a > b
            }
        case .category:
            rows.sort {
                MCPMarketplacePresentation.category(for: $0).localizedCaseInsensitiveCompare(
                    MCPMarketplacePresentation.category(for: $1)
                ) == .orderedAscending
            }
        case .featured:
            rows.sort {
                let fa = MCPMarketplacePresentation.isFeatured($0)
                let fb = MCPMarketplacePresentation.isFeatured($1)
                if fa != fb { return fa && !fb }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
        return rows
    }

    private var listColumn: some View {
        List(selection: $selected) {
            ForEach(filtered) { s in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayTitle(s))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(fg)
                        Text(MCPMarketplacePresentation.category(for: s))
                            .font(.caption2)
                            .foregroundStyle(secondary)
                    }
                    Spacer(minLength: 8)
                    Text(MCPMarketplacePresentation.estimatedToolsLabel(for: s))
                        .font(.caption)
                        .foregroundStyle(secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                .tag(s)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func displayTitle(_ s: MCPMarketplaceServerEntry) -> String {
        let star = MCPMarketplacePresentation.isFeatured(s) ? "⭐ " : ""
        return star + s.name
    }

    private var detailColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let s = selected {
                    Text(s.name)
                        .font(.system(size: 15, weight: .semibold))
                    Text(s.description)
                        .font(.system(size: 12))
                        .foregroundStyle(secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let u = s.url, !u.isEmpty {
                        Text("URL: \(u)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(secondary)
                    } else {
                        let cmd = s.command ?? "npx"
                        let args = (s.args ?? []).joined(separator: " ")
                        Text("Command: \(cmd) \(args)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(secondary)
                            .textSelection(.enabled)
                    }
                    if MCPMarketplacePresentation.isFeatured(s) {
                        Text("Featured server")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } else {
                    Text("Select a server to see details.")
                        .foregroundStyle(secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    /// Loads JSON off the main thread. `load()` is MainActor-isolated (SwiftUI); synchronous file I/O in
    /// `loadBuiltIn()` was blocking the UI and causing a spinning cursor when opening the sheet.
    private func load() async {
        loadPhase = .loading
        statusLine = ""
        let remote = (optionalRemoteMarketplaceURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let servers: [MCPMarketplaceServerEntry]
            let note: String
            (servers, note) = try await Task.detached(priority: .userInitiated) { () async throws -> ([MCPMarketplaceServerEntry], String) in
                if !remote.isEmpty, let u = URL(string: remote), u.scheme == "http" || u.scheme == "https" {
                    do {
                        let s = try await MCPMarketplaceCatalog.fetchRemoteJSON(from: u)
                        return (s, "Loaded \(s.count) server(s) from your MCP Marketplace URL.")
                    } catch {
                        let fallback = try MCPMarketplaceCatalog.loadBuiltIn()
                        let msg = "Could not fetch marketplace URL (\(error.localizedDescription)). Using built-in list."
                        return (fallback, msg)
                    }
                }
                let s = try MCPMarketplaceCatalog.loadBuiltIn()
                return (s, "Loaded \(s.count) built-in server(s).")
            }.value
            allServers = servers
            statusLine = note
            loadPhase = .ready
            selected = filtered.first
        } catch {
            loadPhase = .failed(error.localizedDescription)
        }
    }

    private func addSelected() {
        guard let s = selected, let row = s.makeServerRow(enabled: true) else { return }
        let cmd = s.command ?? ""
        if cmd == "npx" || cmd == "uvx" {
            let args = s.args ?? []
            let pkg: String
            if args.count > 1, args[0] == "-y" {
                pkg = args[1]
            } else {
                pkg = args.first ?? s.name
            }
            let alert = NSAlert()
            alert.messageText = "Confirm installation"
            alert.informativeText =
                "You are about to add “\(s.name)” using \(cmd). This will download and run code from \(cmd == "npx" ? "npm" : "PyPI") when the MCP server starts. Only proceed if you trust this package.\n\nPackage: \(pkg)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Add")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertSecondButtonReturn { return }
        }
        onAdd(row)
        statusLine = "Added “\(row.name)”. It appears in the MCP Servers list — save is already applied to your JSON file."
        allServers.removeAll { $0.name == s.name }
        selected = filtered.first
    }
}
