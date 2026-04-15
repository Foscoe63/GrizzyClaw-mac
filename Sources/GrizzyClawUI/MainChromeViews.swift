import AppKit
import GrizzyClawCore
import SwiftUI

// MARK: - Sidebar (parity with Python `SidebarWidget` + `GrizzyClawApp.setup_ui`)

/// Primary navigation — matches `main_window.py` sidebar order and labels (plus Watchers for native).
enum SidebarNav: String, CaseIterable, Identifiable {
    case chat
    case workspaces
    case memory
    case scheduler
    case browser
    case sessions
    case swarm
    case subagents
    case conversationHistory
    case usage
    case watchers
    case settings

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .chat: return "💬"
        case .workspaces: return "🗂️"
        case .memory: return "🧠"
        case .scheduler: return "⏰"
        case .browser: return "🌐"
        case .sessions: return "👥"
        case .swarm: return "🐝"
        case .subagents: return "🤖"
        case .conversationHistory: return "📜"
        case .usage: return "📊"
        case .watchers: return "👁️"
        case .settings: return "⚙️"
        }
    }

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .workspaces: return "Workspaces"
        case .memory: return "Memory"
        case .scheduler: return "Scheduler"
        case .browser: return "Browser"
        case .sessions: return "Sessions"
        case .swarm: return "Swarm activity"
        case .subagents: return "Sub-agents"
        case .conversationHistory: return "Conversation history"
        case .usage: return "Usage"
        case .watchers: return "Watchers"
        case .settings: return "Settings"
        }
    }
}

/// Left column: logo, MENU, nav pills, workspace list, status — ~240pt like Python.
struct GrizzyClawSidebarChrome: View {
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedNav: SidebarNav
    @ObservedObject var workspaceStore: WorkspaceStore
    @Binding var selectedWorkspaceId: String?
    /// Opens the dedicated Workspaces window (Python “Workspaces” dialog).
    var openWorkspacesWindow: () -> Void
    /// `config.yaml` `theme` — drives sidebar chrome for named palettes (Nord, Dracula, …).
    var themeName: String

    private let sidebarWidth: CGFloat = 240
    /// Extra height for the MENU/nav pane vs. the workspace pane (moves divider + agents down).
    private let sidebarNavOverWorkspaceBias: CGFloat = 125
    /// Divider + vertical padding + gap before workspace scroll (between the two flexible panes).
    private let sidebarBetweenPanesFixed: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logoRow
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)

            Text("MENU")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 0.56, green: 0.56, blue: 0.58).opacity(colorScheme == .dark ? 0.9 : 1))
                .padding(.leading, 28)
                .padding(.top, 22)
                .padding(.bottom, 8)

            GeometryReader { geo in
                let h = geo.size.height
                let flex = max(0, h - sidebarBetweenPanesFixed)
                let half = flex / 2
                // Equal split would be `half` each; bias moves +125pt to MENU/nav and −125pt to workspaces (divider + agents shift down 125pt).
                let navH = min(flex, half + sidebarNavOverWorkspaceBias)
                let wsH = flex - navH

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(SidebarNav.allCases) { nav in
                                sidebarNavButton(nav)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.visible, axes: .vertical)
                    .frame(height: max(0, navH))

                    Divider()
                        .opacity(0.6)
                        .padding(.vertical, 4)

                    workspaceScroll
                        .padding(.top, 4)
                        .frame(height: max(0, wsH))
                }
            }
            .frame(minHeight: 0, maxHeight: .infinity)

            Divider()
                .opacity(0.6)

            statusRow
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(width: sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(borderColor)
                .frame(width: 1)
        }
    }

    private var logoRow: some View {
        HStack(alignment: .center, spacing: 6) {
            Text("🐻")
                .font(.system(size: 28))
            Text("Grizzy")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(colorScheme == .dark ? Color.white.opacity(0.92) : Color(red: 0.11, green: 0.11, blue: 0.12))
            Text("Claw")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.accentColor)
            Spacer()
        }
    }

    /// Parity with Python `apply_appearance_settings` + named theme palettes (`AppearanceTheme`).
    private var sidebarBackground: Color {
        AppearanceTheme.sidebarBackground(theme: themeName, colorScheme: colorScheme)
    }

    private var borderColor: Color {
        AppearanceTheme.sidebarBorder(theme: themeName, colorScheme: colorScheme)
    }

    private func sidebarNavButton(_ nav: SidebarNav) -> some View {
        let selected = selectedNav == nav
        return Button {
            selectedNav = nav
        } label: {
            HStack(spacing: 8) {
                Text(nav.emoji)
                Text(nav.title)
                    .font(.system(size: 14))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(
                selected
                    ? Color.white
                    : (colorScheme == .dark ? Color.white.opacity(0.85) : Color(red: 0.24, green: 0.24, blue: 0.26))
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var workspaceScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if let idx = workspaceStore.index {
                    ForEach(idx.workspaces) { ws in
                        workspaceChip(ws: ws, active: ws.id == (selectedWorkspaceId ?? idx.activeWorkspaceId))
                    }
                } else {
                    Text("No workspaces loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible, axes: .vertical)
    }

    private func workspaceChip(ws: WorkspaceRecord, active: Bool) -> some View {
        Button {
            selectedWorkspaceId = ws.id
            workspaceStore.persistActiveWorkspace(id: ws.id)
        } label: {
            HStack(spacing: 6) {
                Text(ws.icon ?? "🤖")
                Text(ws.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? Color.accentColor : Color.clear)
            )
            .foregroundStyle(
                active
                    ? Color.white
                    : (colorScheme == .dark ? Color.white.opacity(0.88) : Color(red: 0.11, green: 0.11, blue: 0.12))
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Workspace settings…") {
                selectedWorkspaceId = ws.id
                workspaceStore.persistActiveWorkspace(id: ws.id)
                openWorkspacesWindow()
            }
        }
    }

    private var statusRow: some View {
        EmptyView()
    }
}

/// Full-width status bar at the bottom.
/// Parity with Python `QStatusBar` style and behavior.
struct GrizzyClawStatusBar: View {
    @ObservedObject var store: StatusBarStore
    /// Active workspace work folder (`work_folder_path`) — Cursor-style “Connected in … at …”.
    var workFolderPath: String
    @Environment(\.colorScheme) private var colorScheme

    private var primaryMuted: Color {
        colorScheme == .dark ? .white.opacity(0.7) : Color(red: 0.24, green: 0.24, blue: 0.26)
    }

    private var secondaryMuted: Color {
        colorScheme == .dark ? .white.opacity(0.55) : Color(red: 0.42, green: 0.42, blue: 0.44)
    }

    private var tertiaryMuted: Color {
        colorScheme == .dark ? .white.opacity(0.45) : Color(red: 0.56, green: 0.56, blue: 0.58)
    }

    private var barBackground: Color {
        colorScheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color(red: 0.96, green: 0.96, blue: 0.97)
    }

    private var connectionRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if workFolderPath.isEmpty {
                Text("Connected in GrizzyClaw")
                    .foregroundStyle(primaryMuted)
                Text(" — no project folder")
                    .foregroundStyle(secondaryMuted)
            } else {
                Text("Connected in GrizzyClaw at ")
                    .foregroundStyle(primaryMuted)
                Text(workFolderPath)
                    .foregroundStyle(secondaryMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(workFolderPath)
            }
        }
        .font(.system(size: 12))
    }

    private var ephemeralMessage: Bool {
        store.statusMessage != "Ready"
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(colorScheme == .dark ? Color.black.opacity(0.3) : Color(red: 0.90, green: 0.90, blue: 0.92))

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: ephemeralMessage ? 3 : 0) {
                    connectionRow
                    if ephemeralMessage {
                        Text(store.statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(tertiaryMuted)
                            .lineLimit(2)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                Text(store.sessionStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(colorScheme == .dark ? .white.opacity(0.5) : Color(red: 0.56, green: 0.56, blue: 0.58))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, ephemeralMessage ? 5 : 6)
            .frame(minHeight: ephemeralMessage ? 38 : 28)
            .background(barBackground)
        }
    }
}

// MARK: - Placeholders (Python app features not in native yet)

struct NativeFeaturePlaceholder: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Main shell

/// Horizontal layout matching Python: fixed sidebar + main content (`QHBoxLayout` + splitter for chat).
public struct GrizzyClawMainShell: View {
    @ObservedObject var workspaceStore: WorkspaceStore
    @ObservedObject var configStore: ConfigStore
    @ObservedObject var chatSession: ChatSessionModel
    @ObservedObject var statusBarStore: StatusBarStore
    @ObservedObject var visualCanvas: VisualCanvasModel
    @ObservedObject var guiChatPrefs: GuiChatPrefsStore
    @Binding var selectedWorkspaceId: String?
    /// Bound to `GrizzyClawSession.visualCanvasWindowOpen`; drives the separate Visual Canvas window.
    @Binding var visualCanvasWindowOpen: Bool
    var openWorkspacesWindow: () -> Void
    var openMemoryWindow: () -> Void
    var openSchedulerWindow: () -> Void
    var openBrowserWindow: () -> Void
    var openSessionsWindow: () -> Void
    var openConversationHistoryWindow: () -> Void
    var openUsageDashboardWindow: () -> Void
    var openSwarmWindow: () -> Void
    var openSubagentsWindow: () -> Void
    var openWatchersWindow: () -> Void
    var openPreferencesWindow: () -> Void

    @State private var selectedNav: SidebarNav = .chat
    public init(
        workspaceStore: WorkspaceStore,
        configStore: ConfigStore,
        chatSession: ChatSessionModel,
        statusBarStore: StatusBarStore,
        visualCanvas: VisualCanvasModel,
        guiChatPrefs: GuiChatPrefsStore,
        selectedWorkspaceId: Binding<String?>,
        visualCanvasWindowOpen: Binding<Bool>,
        openWorkspacesWindow: @escaping () -> Void,
        openMemoryWindow: @escaping () -> Void,
        openSchedulerWindow: @escaping () -> Void,
        openBrowserWindow: @escaping () -> Void,
        openSessionsWindow: @escaping () -> Void,
        openConversationHistoryWindow: @escaping () -> Void,
        openUsageDashboardWindow: @escaping () -> Void,
        openSwarmWindow: @escaping () -> Void,
        openSubagentsWindow: @escaping () -> Void,
        openWatchersWindow: @escaping () -> Void,
        openPreferencesWindow: @escaping () -> Void
    ) {
        self.workspaceStore = workspaceStore
        self.configStore = configStore
        self.chatSession = chatSession
        self.statusBarStore = statusBarStore
        self.visualCanvas = visualCanvas
        self.guiChatPrefs = guiChatPrefs
        self._selectedWorkspaceId = selectedWorkspaceId
        self._visualCanvasWindowOpen = visualCanvasWindowOpen
        self.openWorkspacesWindow = openWorkspacesWindow
        self.openMemoryWindow = openMemoryWindow
        self.openSchedulerWindow = openSchedulerWindow
        self.openBrowserWindow = openBrowserWindow
        self.openSessionsWindow = openSessionsWindow
        self.openConversationHistoryWindow = openConversationHistoryWindow
        self.openUsageDashboardWindow = openUsageDashboardWindow
        self.openSwarmWindow = openSwarmWindow
        self.openSubagentsWindow = openSubagentsWindow
        self.openWatchersWindow = openWatchersWindow
        self.openPreferencesWindow = openPreferencesWindow
    }

    /// Work folder for the selected workspace (`work_folder_path`), for the bottom-left connection line.
    private var statusBarWorkFolderPath: String {
        guard let id = selectedWorkspaceId,
              let ws = workspaceStore.index?.workspaces.first(where: { $0.id == id }) else {
            return ""
        }
        return ws.workFolderPath
    }

    public var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                GrizzyClawSidebarChrome(
                    selectedNav: $selectedNav,
                    workspaceStore: workspaceStore,
                    selectedWorkspaceId: $selectedWorkspaceId,
                    openWorkspacesWindow: openWorkspacesWindow,
                    themeName: configStore.snapshot.theme
                )

                detailContent
                    .frame(minWidth: 600, minHeight: 480)
            }

            GrizzyClawStatusBar(store: statusBarStore, workFolderPath: statusBarWorkFolderPath)
        }
        .environmentObject(statusBarStore)
        .frame(minWidth: 1080, minHeight: 700)
        .onChange(of: selectedNav) { _, new in
            switch new {
            case .workspaces:
                openWorkspacesWindow()
                selectedNav = .chat
            case .memory:
                openMemoryWindow()
                selectedNav = .chat
            case .scheduler:
                openSchedulerWindow()
                selectedNav = .chat
            case .browser:
                break
            case .sessions:
                openSessionsWindow()
                selectedNav = .chat
            case .conversationHistory:
                openConversationHistoryWindow()
                selectedNav = .chat
            case .usage:
                openUsageDashboardWindow()
                selectedNav = .chat
            case .swarm:
                openSwarmWindow()
                selectedNav = .chat
            case .subagents:
                openSubagentsWindow()
                selectedNav = .chat
            case .watchers:
                openWatchersWindow()
                selectedNav = .chat
            case .settings:
                openPreferencesWindow()
                selectedNav = .chat
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedNav {
        case .chat:
            ChatPane(
                session: chatSession,
                workspaceStore: workspaceStore,
                configStore: configStore,
                guiChatPrefs: guiChatPrefs,
                canvasModel: visualCanvas,
                statusBarStore: statusBarStore,
                canvasPanelVisible: $visualCanvasWindowOpen,
                selectedWorkspaceId: selectedWorkspaceId
            )
        case .workspaces:
            Color(nsColor: .windowBackgroundColor)
        case .memory:
            Color(nsColor: .windowBackgroundColor)
        case .scheduler:
            Color(nsColor: .windowBackgroundColor)
        case .browser:
            BrowserMainView(theme: configStore.snapshot.theme)
                .id(configStore.snapshot.theme)
        case .sessions:
            Color(nsColor: .windowBackgroundColor)
        case .swarm:
            Color(nsColor: .windowBackgroundColor)
        case .subagents:
            Color(nsColor: .windowBackgroundColor)
        case .conversationHistory:
            Color(nsColor: .windowBackgroundColor)
        case .usage:
            Color(nsColor: .windowBackgroundColor)
        case .watchers:
            Color(nsColor: .windowBackgroundColor)
        case .settings:
            Color(nsColor: .windowBackgroundColor)
        }
    }
}
