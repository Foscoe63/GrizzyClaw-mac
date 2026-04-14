import GrizzyClawAgent
import GrizzyClawCore
import SwiftUI

// MARK: - Python `SlideSwitch` (ToolsPickerPopup tool rows)

/// Rounded track + white knob — parity with `main_window.SlideSwitch` beside each tool name.
private struct ComposerSlideSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(isOn ? Color(red: 0.2, green: 0.78, blue: 0.35) : Color(red: 0.90, green: 0.90, blue: 0.92))
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.12), radius: 1, x: 0, y: 0.5)
                    .frame(width: 20, height: 20)
                    .padding(2)
                    .offset(x: isOn ? 20 : 0)
            }
            .frame(width: 44, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isOn ? "On" : "Off"))
    }
}

// MARK: - Model popup (Python `ModelSelectorPopup` — width 360, min/max height, collapsible providers)

private let kModelPopupWidth: CGFloat = 360
private let kModelPopupScrollMinHeight: CGFloat = 400
private let kModelPopupScrollMaxHeight: CGFloat = 440
private let kModelPopupRowHeight: CGFloat = 34
/// Python `ToolsPickerPopup`: same outer width and scroll height as model popup (`_POPUP_OUTER_*`).
private let kToolsPopupWidth: CGFloat = 360

/// Below this toolbar width, shorten MCP controls and tighten model/tools dropdowns.
private let kComposerToolbarNarrowWidth: CGFloat = 760

/// Python `composer_bar`: Model + ↻, Tools + ↻ — centered above the input, `composer_bar_toolbutton_stylesheet` parity.
struct ChatComposerToolbar: View {
    @ObservedObject var guiPrefs: GuiChatPrefsStore
    @ObservedObject var configStore: ConfigStore
    @ObservedObject var workspaceStore: WorkspaceStore
    var selectedWorkspaceId: String?

    @Environment(\.colorScheme) private var colorScheme

    private var snap: UserConfigSnapshot { configStore.snapshot }

    @State private var modelsByProvider: [String: [ModelPickerModels.Row]] = [:]
    @State private var modelListLoading = false
    @State private var expandedProviders: Set<String> = []
    @State private var isRefreshingModels = false
    @State private var isRefreshingTools = false
    @State private var showModelPopover = false
    @State private var showToolsPopover = false
    /// Python `ToolsPickerPopup._expanded_servers` — only servers still in discovery stay expanded on refresh.
    @State private var expandedToolServers: Set<String> = []

    private var mutedLabel: Color {
        Color(red: 0.56, green: 0.56, blue: 0.58)
    }

    private var isDark: Bool { colorScheme == .dark }

    private var dropdownBorder: Color {
        isDark ? Color(red: 0.28, green: 0.28, blue: 0.29) : Color(red: 0.82, green: 0.82, blue: 0.84)
    }

    private var dropdownBackground: LinearGradient {
        if isDark {
            return LinearGradient(
                colors: [
                    Color(red: 0.23, green: 0.23, blue: 0.24),
                    Color(red: 0.17, green: 0.17, blue: 0.18),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        return LinearGradient(
            colors: [
                Color.white,
                Color(red: 0.95, green: 0.95, blue: 0.97),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var dropdownForeground: Color {
        isDark ? .white : Color(red: 0.11, green: 0.11, blue: 0.12)
    }

    /// Current GUI override for selection highlight (Python `_model_override`).
    private var selectionPair: (provider: String?, model: String?) {
        guard let l = guiPrefs.preferences.llm,
              let p = l.provider?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty
        else {
            return (nil, nil)
        }
        let m = l.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (p, (m?.isEmpty ?? true) ? nil : m)
    }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < kComposerToolbarNarrowWidth
            HStack {
                Spacer(minLength: 0)
                composerBarRow(compact: compact)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 36)
        .onAppear {
            refreshModelsList()
            refreshTools()
        }
        .onChange(of: configStore.snapshot.mcpServersFile) { _ in
            refreshTools()
        }
    }

    @ViewBuilder
    private func composerBarRow(compact: Bool) -> some View {
        let rowSpacing: CGFloat = compact ? 6 : 10
        HStack(alignment: .center, spacing: rowSpacing) {
                Text("Model")
                    .font(AppearanceTheme.swiftUIFont(snap, delta: -1, weight: .medium))
                    .foregroundColor(mutedLabel)

                Button {
                    showModelPopover.toggle()
                } label: {
                    Text(guiPrefs.modelButtonTitle())
                        .font(.system(size: 13))
                        .foregroundColor(dropdownForeground)
                        .lineLimit(1)
                        .frame(minWidth: compact ? 168 : 260, maxWidth: compact ? 220 : 280, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .frame(minHeight: 28, maxHeight: 28)
                        .background(dropdownBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(dropdownBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Choose provider and model")
                .popover(isPresented: $showModelPopover, arrowEdge: .bottom) {
                    modelSelectorPopover
                }

                Button {
                    refreshModelsList()
                } label: {
                    Text("↻")
                        .font(AppearanceTheme.swiftUIFont(snap, delta: 1, weight: .medium))
                        .foregroundColor(dropdownForeground)
                        .frame(width: 28, height: 28)
                        .background(dropdownBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(dropdownBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isRefreshingModels)
                .help("Refresh model list from providers")

                Text("Tools")
                    .font(AppearanceTheme.swiftUIFont(snap, delta: -1, weight: .medium))
                    .foregroundColor(mutedLabel)
                    .padding(.leading, 8)

                Button {
                    showToolsPopover.toggle()
                } label: {
                    Text(toolsMenuButtonTitle)
                        .font(.system(size: 13))
                        .foregroundColor(dropdownForeground)
                        .lineLimit(1)
                        .frame(minWidth: compact ? 128 : 200, maxWidth: compact ? 200 : 280, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .frame(minHeight: 28, maxHeight: 28)
                        .background(dropdownBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(dropdownBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showToolsPopover, arrowEdge: .bottom) {
                    toolsPickerPopover
                }

                Button {
                    refreshTools()
                } label: {
                    Text("↻")
                        .font(AppearanceTheme.swiftUIFont(snap, delta: 1, weight: .medium))
                        .foregroundColor(dropdownForeground)
                        .frame(width: 28, height: 28)
                        .background(dropdownBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(dropdownBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isRefreshingTools)
                .help("Refresh tool list from MCP servers")

                if !compact {
                    Text("MCP chat")
                        .font(AppearanceTheme.swiftUIFont(snap, delta: -1, weight: .medium))
                        .foregroundColor(mutedLabel)
                        .padding(.leading, 8)
                }

                mcpTranscriptMenu(compact: compact)
            }
    }

    @ViewBuilder
    private func mcpTranscriptMenu(compact: Bool) -> some View {
        Menu {
            ForEach(GuiChatPreferences.McpTranscriptMode.allCases, id: \.self) { mode in
                Button {
                    guiPrefs.setMcpTranscriptMode(mode)
                } label: {
                    HStack {
                        Text(Self.mcpTranscriptMenuRowLabel(mode))
                        if guiPrefs.mcpTranscriptMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            if compact {
                Label {
                    Text(guiPrefs.mcpTranscriptModeCompactToken())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(dropdownForeground)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(dropdownForeground)
                }
                .labelStyle(.titleAndIcon)
                .frame(minWidth: 88, maxWidth: 140, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(minHeight: 28, maxHeight: 28)
                .background(dropdownBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(dropdownBorder, lineWidth: 1)
                )
            } else {
                Text("Show: \(guiPrefs.mcpTranscriptModeMenuLabel())")
                    .font(.system(size: 13))
                    .foregroundColor(dropdownForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
                    .frame(minWidth: 152, maxWidth: 220, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .frame(minHeight: 28, maxHeight: 28)
                    .background(dropdownBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(dropdownBorder, lineWidth: 1)
                    )
            }
        }
        .menuStyle(.borderlessButton)
        .help("What to show after MCP tool calls: assistant text, raw tool output, or both.")
        .accessibilityLabel("MCP transcript, \(guiPrefs.mcpTranscriptModeMenuLabel())")
    }

    private static func mcpTranscriptMenuRowLabel(_ mode: GuiChatPreferences.McpTranscriptMode) -> String {
        switch mode {
        case .assistant: return "Assistant reply"
        case .tool: return "Tool output"
        case .both: return "Both"
        }
    }

    // MARK: - Model selector popover (Python `ModelSelectorPopup`)

    private var modelSelectorPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isDark ? .white : Color(red: 0.11, green: 0.11, blue: 0.18))

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if modelListLoading {
                        Text("Loading models…")
                            .font(.system(size: 14))
                            .foregroundColor(mutedLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    } else {
                        defaultModelRow
                        ForEach(modelsByProvider.keys.sorted(), id: \.self) { prov in
                            providerSection(provider: prov, rows: modelsByProvider[prov] ?? [])
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: kModelPopupScrollMinHeight, maxHeight: kModelPopupScrollMaxHeight)
        }
        .padding(12)
        .frame(width: kModelPopupWidth)
        .background(modelPopupBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(modelPopupStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 14, x: 0, y: 8)
        .onAppear {
            if modelsByProvider.isEmpty && !modelListLoading {
                refreshModelsList()
            }
        }
    }

    private var modelPopupBackground: Color {
        isDark ? Color(red: 0.17, green: 0.17, blue: 0.18) : Color.white
    }

    private var modelPopupStroke: Color {
        isDark ? Color(red: 0.28, green: 0.28, blue: 0.29) : Color(red: 0.82, green: 0.82, blue: 0.84)
    }

    private var accent: Color {
        isDark ? Color(red: 0.04, green: 0.52, blue: 1) : Color(red: 0, green: 0.48, blue: 1)
    }

    /// Python `tools_menu_btn` label from `_tools_filtered` + merged discovery.
    private var toolsMenuButtonTitle: String {
        guiPrefs.toolsButtonTitle(effectiveDiscovery: discoveryForToolsUI())
    }

    /// Raw discovery + internal grizzyclaw tools + optional workspace `mcp_tool_allowlist` cap.
    private func discoveryForToolsUI() -> MCPToolsDiscoveryResult? {
        guard let raw = guiPrefs.lastDiscovery else { return nil }
        var m = raw.mergingPythonInternalTools()
        if let cap = workspaceAllowlistCap(), !cap.isEmpty {
            m = m.filteredByWorkspaceAllowlist(cap)
        }
        return m
    }

    private func workspaceAllowlistCap() -> [(String, String)]? {
        guard let ws = currentWorkspace(), let cfg = ws.config else { return nil }
        let p = cfg.mcpToolAllowlistPairs(forKey: "mcp_tool_allowlist")
        guard let p, !p.isEmpty else { return nil }
        return p
    }

    private func syncExpandedToolServersWithDiscovery() {
        let keys = Set(discoveryForToolsUI()?.servers.keys.map(\.self) ?? [])
        expandedToolServers = expandedToolServers.intersection(keys)
    }

    private var defaultModelRow: some View {
        let isSel = selectionPair.provider == nil
        return Button {
            guiPrefs.setLlmDefault()
            showModelPopover = false
        } label: {
            Text("  Default — use app settings")
                .font(.system(size: 14))
                .foregroundColor(isDark ? .white : Color(red: 0.11, green: 0.11, blue: 0.12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: kModelPopupRowHeight)
                .background(defaultRowBackground(selected: isSel))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSel ? accent : borderSubtle, lineWidth: isSel ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func defaultRowBackground(selected: Bool) -> Color {
        if selected {
            return isDark ? Color(red: 0.28, green: 0.28, blue: 0.29) : Color(red: 0.91, green: 0.95, blue: 1)
        }
        return isDark ? Color(red: 0.23, green: 0.23, blue: 0.24) : Color(red: 0.98, green: 0.98, blue: 0.98)
    }

    private var borderSubtle: Color {
        isDark ? Color(red: 0.23, green: 0.23, blue: 0.24) : Color(red: 0.82, green: 0.82, blue: 0.84)
    }

    private func providerSection(provider: String, rows: [ModelPickerModels.Row]) -> some View {
        let expanded = expandedProviders.contains(provider)
        let bgHead = isDark ? Color(red: 0.17, green: 0.17, blue: 0.18) : Color(red: 0.95, green: 0.95, blue: 0.97)
        let fgMuted = mutedLabel

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if expanded { expandedProviders.remove(provider) } else { expandedProviders.insert(provider) }
            } label: {
                HStack(spacing: 8) {
                    Text(expanded ? "▼" : "▶")
                        .font(.system(size: 12))
                        .foregroundColor(fgMuted)
                        .frame(width: 18, alignment: .leading)
                    Text(provider)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isDark ? .white : Color(red: 0.11, green: 0.11, blue: 0.12))
                    Spacer(minLength: 0)
                    Text("\(rows.count)")
                        .font(.system(size: 12))
                        .foregroundColor(fgMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(bgHead)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(borderSubtle, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rows) { row in
                        modelRowButton(provider: provider, row: row)
                    }
                }
                .padding(.leading, 6)
                .padding(.trailing, 4)
                .padding(.top, 4)
                .padding(.bottom, 6)
            }
        }
    }

    private func modelRowButton(provider: String, row: ModelPickerModels.Row) -> some View {
        let curP = selectionPair.provider
        let curM = selectionPair.model
        let isSel = curP == provider && curM == row.modelId
        return Button {
            guiPrefs.setLlm(provider: provider, model: row.modelId)
            showModelPopover = false
        } label: {
            Text("    \(row.displayName)")
                .font(.system(size: 13))
                .foregroundColor(isDark ? .white : Color(red: 0.11, green: 0.11, blue: 0.12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: kModelPopupRowHeight)
                .background(isSel ? (isDark ? Color(red: 0.28, green: 0.28, blue: 0.29) : Color(red: 0.91, green: 0.95, blue: 1)) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSel ? accent : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func currentWorkspace() -> WorkspaceRecord? {
        guard let idx = workspaceStore.index else { return nil }
        let wid = selectedWorkspaceId ?? idx.activeWorkspaceId
        guard let wid else { return nil }
        return idx.workspaces.first(where: { $0.id == wid })
    }

    private func refreshModelsList() {
        isRefreshingModels = true
        modelListLoading = true
        let cfg = currentWorkspace()?.config
        let user = configStore.snapshot
        let routing = configStore.routingExtras
        Task {
            let secrets: UserConfigSecrets
            do {
                secrets = try UserConfigLoader.loadSecretsWithKeychain()
            } catch {
                secrets = .empty
            }
            let data = await ModelPickerModels.fetch(
                workspaceConfig: cfg,
                user: user,
                routing: routing,
                secrets: secrets
            )
            await MainActor.run {
                modelsByProvider = data
                modelListLoading = false
                isRefreshingModels = false
            }
        }
    }

    private func refreshTools() {
        guard !isRefreshingTools else { return }
        isRefreshingTools = true
        let path = configStore.snapshot.mcpServersFile
        let failsafe = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(20 * 1_000_000_000))
            isRefreshingTools = false
        }
        Task {
            defer { failsafe.cancel() }
            do {
                try await GrizzyAsyncTimeout.run(seconds: 20, timeoutError: GrizzyMCPNativeError.timeout) {
                    let r = try await MCPToolsDiscovery.discover(mcpServersFile: path)
                    await MainActor.run {
                        guiPrefs.applyDiscovery(r)
                    }
                }
            } catch {
                await MainActor.run {
                    GrizzyClawLog.error("ChatComposerToolbar MCP discovery: \(error.localizedDescription)")
                }
            }
            await MainActor.run {
                isRefreshingTools = false
            }
        }
    }

    // MARK: - Tools picker (Python `ToolsPickerPopup`)

    private var toolsPickerPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MCP tools")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isDark ? .white : Color(red: 0.11, green: 0.11, blue: 0.18))

            if let err = guiPrefs.lastDiscovery?.errorMessage, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            HStack(spacing: 8) {
                toolsMassButton(title: "Enable all") {
                    guiPrefs.toolsEnableAll(usingDiscovery: discoveryForToolsUI())
                }
                toolsMassButton(title: "Disable all") {
                    guiPrefs.toolsDisableAll(usingDiscovery: discoveryForToolsUI())
                }
                Spacer(minLength: 0)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if let disc = discoveryForToolsUI(), !disc.servers.isEmpty {
                        ForEach(disc.servers.keys.sorted(), id: \.self) { srv in
                            toolServerSection(server: srv, tools: disc.servers[srv] ?? [])
                        }
                    } else {
                        Text("No tools loaded yet. Tap ↻ beside Tools.")
                            .font(.system(size: 14))
                            .foregroundColor(mutedLabel)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: kModelPopupScrollMinHeight, maxHeight: kModelPopupScrollMaxHeight)
        }
        .padding(12)
        .frame(width: kToolsPopupWidth)
        .background(modelPopupBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(modelPopupStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 14, x: 0, y: 8)
        .onAppear {
            syncExpandedToolServersWithDiscovery()
        }
    }

    private func toolsMassButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(isDark ? Color(red: 0.04, green: 0.52, blue: 1) : Color(red: 0, green: 0.48, blue: 1))
                .background(isDark ? Color(red: 0.23, green: 0.23, blue: 0.24) : Color(red: 0.95, green: 0.95, blue: 0.97))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(borderSubtle, lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func toolServerSection(server: String, tools: [(name: String, description: String)]) -> some View {
        let expanded = expandedToolServers.contains(server)
        let bgHead = isDark ? Color(red: 0.17, green: 0.17, blue: 0.18) : Color(red: 0.95, green: 0.95, blue: 0.97)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if expanded {
                    expandedToolServers.remove(server)
                } else {
                    expandedToolServers.insert(server)
                }
            } label: {
                HStack(spacing: 8) {
                    Text(expanded ? "▼" : "▶")
                        .font(.system(size: 12))
                        .foregroundColor(mutedLabel)
                        .frame(width: 18, alignment: .leading)
                    Text(server)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isDark ? .white : Color(red: 0.11, green: 0.11, blue: 0.12))
                    Spacer(minLength: 0)
                    Text("\(tools.count)")
                        .font(.system(size: 12))
                        .foregroundColor(mutedLabel)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(bgHead)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(borderSubtle, lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(tools.enumerated()), id: \.offset) { _, t in
                        toolRow(server: server, toolName: t.name)
                    }
                }
                .padding(.leading, 6)
                .padding(.trailing, 4)
                .padding(.top, 4)
                .padding(.bottom, 6)
            }
        }
    }

    private func toolRow(server: String, toolName: String) -> some View {
        let fg = isDark ? Color.white : Color(red: 0.11, green: 0.11, blue: 0.12)
        return HStack(alignment: .center, spacing: 8) {
            Text(toolName)
                .font(.system(size: 13))
                .foregroundColor(fg)
                .lineLimit(1)
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { guiPrefs.isToolOn(server: server, tool: toolName) },
                set: { new in
                    guiPrefs.setToolEnabled(server: server, tool: toolName, enabled: new)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity)
        .frame(height: kModelPopupRowHeight)
        .background(isDark ? Color(red: 0.17, green: 0.17, blue: 0.18) : Color(red: 0.98, green: 0.98, blue: 0.98))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(borderSubtle, lineWidth: 1)
                .allowsHitTesting(false)
        )
    }
}
