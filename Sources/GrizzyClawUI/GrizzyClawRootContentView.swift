import AppKit
import GrizzyClawCore
import SwiftUI

/// Main window content: chat shell + shared session state.
public struct GrizzyClawRootContentView: View {
    @ObservedObject public var session: GrizzyClawSession
    /// Observed separately so `preferredColorScheme` and chrome update when Preferences saves YAML (`snapshot` publishes).
    @ObservedObject private var configStore: ConfigStore
    @Environment(\.openWindow) private var openWindow

    public init(session: GrizzyClawSession) {
        self.session = session
        _configStore = ObservedObject(wrappedValue: session.configStore)
    }

    public var body: some View {
        rootWithNotificationShortcuts
    }

    private var rootWithWorkspaceSync: some View {
        themedMainShell
            .onChange(of: session.visualCanvasWindowOpen) { _, open in
                if open {
                    openWindow(id: "visualCanvas")
                } else {
                    grizzyCloseVisualCanvasWindow()
                }
            }
            .onAppear(perform: performRootOnAppear)
            .onChange(of: session.selectedWorkspaceId) { _, newId in
                if let newId, let active = session.workspaceStore.index?.activeWorkspaceId, newId != active {
                    session.workspaceStore.persistActiveWorkspace(id: newId)
                }
                syncChatSessionWorkspace()
            }
            .onReceive(session.workspaceStore.$index) { _ in
                syncWorkspaceSelectionAfterLoad()
                syncChatSessionWorkspace()
            }
    }

    private var themedMainShell: some View {
        mainShell
            .preferredColorScheme(AppearanceTheme.resolvedColorScheme(for: configStore.snapshot.theme))
    }

    /// Notification shortcuts split from `body` so the compiler can type-check without timing out.
    private var rootWithNotificationShortcuts: some View {
        rootWithWorkspaceSync
            .onReceive(NotificationCenter.default.publisher(for: .grizzyReturnToBaseline)) { _ in
                session.workspaceStore.returnToBaselineWorkspace()
                session.selectedWorkspaceId = session.workspaceStore.index?.activeWorkspaceId
                syncChatSessionWorkspace()
            }
            .onReceive(NotificationCenter.default.publisher(for: .grizzyOpenWorkspacesWindow)) { _ in
                openWindow(id: "workspaces")
            }
            .onReceive(NotificationCenter.default.publisher(for: .grizzyOpenMemoryWindow)) { _ in
                openWindow(id: "memory")
            }
            .onReceive(NotificationCenter.default.publisher(for: .grizzyOpenSchedulerWindow)) { _ in
                openWindow(id: "scheduler")
            }
            .onReceive(NotificationCenter.default.publisher(for: .grizzyOpenBrowserWindow)) { _ in
                openWindow(id: "browser")
            }
            .onReceive(NotificationCenter.default.publisher(for: .grizzyOpenSessionsWindow)) { _ in
                openWindow(id: "sessions")
            }
            .onReceive(NotificationCenter.default.publisher(for: .grizzyOpenConversationHistoryWindow)) { _ in
                openWindow(id: "conversationHistory")
            }
            .onReceive(NotificationCenter.default.publisher(for: .grizzyOpenUsageDashboardWindow)) { _ in
                openWindow(id: "usage")
            }
            .onReceive(NotificationCenter.default.publisher(for: .grizzyOpenSwarmWindow)) { _ in
                openWindow(id: "swarm")
            }
            .onReceive(NotificationCenter.default.publisher(for: .grizzyOpenSubagentsWindow)) { _ in
                openWindow(id: "subagents")
            }
            .onReceive(NotificationCenter.default.publisher(for: .grizzyOpenWatchersWindow)) { _ in
                openWindow(id: "watchers")
            }
            .onReceive(NotificationCenter.default.publisher(for: .grizzyOpenPreferencesWindow)) { _ in
                openWindow(id: "preferences")
            }
            .onReceive(NotificationCenter.default.publisher(for: .grizzyOpenTriggersWindow)) { _ in
                openWindow(id: "triggers")
            }
    }

    private var mainShell: some View {
        GrizzyClawMainShell(
            workspaceStore: session.workspaceStore,
            configStore: configStore,
            chatSession: session.chatSession,
            statusBarStore: session.statusBarStore,
            visualCanvas: session.visualCanvas,
            guiChatPrefs: session.guiChatPrefs,
            selectedWorkspaceId: $session.selectedWorkspaceId,
            visualCanvasWindowOpen: $session.visualCanvasWindowOpen,
            openWorkspacesWindow: {
                openWindow(id: "workspaces")
            },
            openMemoryWindow: {
                openWindow(id: "memory")
            },
            openSchedulerWindow: {
                openWindow(id: "scheduler")
            },
            openBrowserWindow: {
                openWindow(id: "browser")
            },
            openSessionsWindow: {
                openWindow(id: "sessions")
            },
            openConversationHistoryWindow: {
                openWindow(id: "conversationHistory")
            },
            openUsageDashboardWindow: {
                openWindow(id: "usage")
            },
            openSwarmWindow: {
                openWindow(id: "swarm")
            },
            openSubagentsWindow: {
                openWindow(id: "subagents")
            },
            openWatchersWindow: {
                openWindow(id: "watchers")
            },
            openPreferencesWindow: {
                openWindow(id: "preferences")
            }
        )
    }

    /// Closes the Visual Canvas auxiliary window when the toolbar toggle turns off (title matches `Window("Visual Canvas", id: "visualCanvas")`).
    private func grizzyCloseVisualCanvasWindow() {
        let title = "Visual Canvas"
        for window in NSApplication.shared.windows where window.title == title {
            window.close()
        }
    }

    private func syncWorkspaceSelectionAfterLoad() {
        guard let idx = session.workspaceStore.index else {
            session.selectedWorkspaceId = nil
            return
        }
        if let s = session.selectedWorkspaceId, idx.workspaces.contains(where: { $0.id == s }) {
            return
        }
        session.selectedWorkspaceId = idx.activeWorkspaceId ?? idx.workspaces.first?.id
    }

    private func performRootOnAppear() {
        GrizzyClawLaunchDiagnostics.log("GrizzyClawRootContentView.onAppear")
        NSApplication.shared.activate(ignoringOtherApps: true)
        session.workspaceStore.reload()
        session.configStore.reload()
        // Local MCP subprocesses always exit when the app quits; restart rows that are still enabled in grizzyclaw.json.
        MCPAutoStart.startEnabledLocalServersIfNeeded(mcpServersFile: session.configStore.snapshot.mcpServersFile)
        syncWorkspaceSelectionAfterLoad()
        syncChatSessionWorkspace()
    }

    private func syncChatSessionWorkspace() {
        session.chatSession.syncWorkspace(
            selectedWorkspaceId: session.selectedWorkspaceId,
            config: session.configStore.snapshot
        )
    }
}
