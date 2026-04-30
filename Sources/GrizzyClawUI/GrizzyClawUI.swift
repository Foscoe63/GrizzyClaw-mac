import AppKit
import Combine
import GrizzyClawCore
import SwiftUI

extension Notification.Name {
    /// Posted from the app menu to activate the baseline workspace.
    public static let grizzyReturnToBaseline = Notification.Name("GrizzyClaw.returnToBaseline")
    /// Open the Workspaces window (menu / shortcuts when `openWindow` is not in environment).
    public static let grizzyOpenWorkspacesWindow = Notification.Name("GrizzyClaw.openWorkspacesWindow")
    /// Open the Memory window (Python `MemoryDialog` parity).
    public static let grizzyOpenMemoryWindow = Notification.Name("GrizzyClaw.openMemoryWindow")
    /// Open the Scheduler window (Python `SchedulerDialog` parity).
    public static let grizzyOpenSchedulerWindow = Notification.Name("GrizzyClaw.openSchedulerWindow")
    /// Open the Browser window (Python `BrowserDialog` parity).
    public static let grizzyOpenBrowserWindow = Notification.Name("GrizzyClaw.openBrowserWindow")
    /// Open the Conversation history window (`conversation_history_dialog.py` parity).
    public static let grizzyOpenConversationHistoryWindow = Notification.Name("GrizzyClaw.openConversationHistoryWindow")
    /// Open the Usage dashboard (`usage_dashboard_dialog.py` parity).
    public static let grizzyOpenUsageDashboardWindow = Notification.Name("GrizzyClaw.openUsageDashboardWindow")
    /// Open the Folder Watchers window (Python **Watchers** dialog parity; `~/.grizzyclaw/watchers/`).
    public static let grizzyOpenWatchersWindow = Notification.Name("GrizzyClaw.openWatchersWindow")
    /// Open the Preferences window (Python `SettingsDialog` / `Preferences` title parity).
    public static let grizzyOpenPreferencesWindow = Notification.Name("GrizzyClaw.openPreferencesWindow")
    public static let grizzyOpenTriggersWindow = Notification.Name("GrizzyClaw.openTriggersWindow")
}

/// Main window + Workspaces window + menu commands (shared by the Xcode app and `swift run` executable).
public struct GrizzyClawRootScene: Scene {
    @StateObject private var session = GrizzyClawSession()

    public init() {}

    public var body: some Scene {
        Window("GrizzyClaw", id: "main") {
            GrizzyClawRootContentView(session: session)
        }
        .defaultSize(width: 1300, height: 850)
        .commands {
            GrizzyClawMenuCommands()
        }

        Window("🗂️ Workspaces", id: "workspaces") {
            AppThemedWindowRoot(configStore: session.configStore) {
                WorkspacesMainView(
                    workspaceStore: session.workspaceStore,
                    configStore: session.configStore,
                    chatSession: session.chatSession,
                    selectedWorkspaceId: Binding(
                        get: { session.selectedWorkspaceId },
                        set: { session.selectedWorkspaceId = $0 }
                    )
                )
                .id(session.configStore.snapshot.theme)
                .frame(minWidth: 880, minHeight: 620)
                .onAppear {
                    session.workspaceStore.reload()
                    session.configStore.reload()
                }
            }
        }

        /// Python `MemoryDialog`: separate window, title `🧠 Memory`, minimum 600×500 (`memory_dialog.py`).
        Window("🧠 Memory", id: "memory") {
            AppThemedWindowRoot(configStore: session.configStore) {
                MemoryMainView(
                    workspaceStore: session.workspaceStore,
                    selectedWorkspaceId: session.selectedWorkspaceId,
                    theme: session.configStore.snapshot.theme
                )
                .id(session.configStore.snapshot.theme)
                .frame(minWidth: 600, minHeight: 500)
                .onAppear {
                    session.workspaceStore.reload()
                    session.configStore.reload()
                }
            }
        }
        .defaultSize(width: 600, height: 520)

        /// Python `SchedulerDialog`: `setWindowTitle("⏰ Scheduled Tasks")`, `setMinimumSize(700, 500)` (`scheduler_dialog.py`).
        Window("⏰ Scheduled Tasks", id: "scheduler") {
            AppThemedWindowRoot(configStore: session.configStore) {
                SchedulerMainView(
                    scheduledTasksStore: session.scheduledTasksStore,
                    configStore: session.configStore,
                    runner: session.scheduledTaskRunner,
                    theme: session.configStore.snapshot.theme
                )
                .id(session.configStore.snapshot.theme)
                .frame(minWidth: 700, minHeight: 500)
                .onAppear {
                    session.workspaceStore.reload()
                    session.configStore.reload()
                    session.scheduledTasksStore.reload()
                }
            }
        }
        .defaultSize(width: 720, height: 520)

        /// Python `BrowserDialog`: `setWindowTitle("🌐 Browser Automation")`, `setMinimumSize(800, 600)` (`browser_dialog.py`).
        Window("🌐 Browser Automation", id: "browser") {
            AppThemedWindowRoot(configStore: session.configStore) {
                BrowserMainView(theme: session.configStore.snapshot.theme)
                    .id(session.configStore.snapshot.theme)
                    .frame(minWidth: 800, minHeight: 600)
                    .onAppear {
                        session.configStore.reload()
                    }
            }
        }
        .defaultSize(width: 880, height: 640)

        /// Python `ConversationHistoryDialog`: `setWindowTitle("Conversation history")`, `setMinimumWidth(360)`.
        Window("📜 Conversation history", id: "conversationHistory") {
            AppThemedWindowRoot(configStore: session.configStore) {
                ConversationHistoryMainView(
                    chatSession: session.chatSession,
                    configStore: session.configStore,
                    selectedWorkspaceId: Binding(
                        get: { session.selectedWorkspaceId },
                        set: { session.selectedWorkspaceId = $0 }
                    )
                )
                .id(session.configStore.snapshot.theme)
                .frame(minWidth: 360, minHeight: 220)
                .onAppear {
                    session.configStore.reload()
                    session.workspaceStore.reload()
                }
            }
        }
        .defaultSize(width: 420, height: 260)

        /// Python `UsageDashboardDialog`: `setWindowTitle("Usage & Performance")`, `setMinimumSize(640, 480)`.
        Window("📊 Usage & Performance", id: "usage") {
            AppThemedWindowRoot(configStore: session.configStore) {
                UsageDashboardMainView(
                    workspaceStore: session.workspaceStore,
                    configStore: session.configStore,
                    chatSession: session.chatSession,
                    selectedWorkspaceId: Binding(
                        get: { session.selectedWorkspaceId },
                        set: { session.selectedWorkspaceId = $0 }
                    )
                )
                .id(session.configStore.snapshot.theme)
                .frame(minWidth: 640, minHeight: 480)
                .onAppear {
                    session.configStore.reload()
                    session.workspaceStore.reload()
                }
            }
        }
        .defaultSize(width: 720, height: 560)

        /// Folder watchers: `~/.grizzyclaw/watchers/*.json` (Python **Watchers** dialog parity; Osaurus-style dedicated window).
        Window("👁️ Watchers", id: "watchers") {
            AppThemedWindowRoot(configStore: session.configStore) {
                WatchersMainView(store: session.watcherStore, workspaceStore: session.workspaceStore)
                    .id(session.configStore.snapshot.theme)
                    .frame(minWidth: 720, minHeight: 520)
                    .onAppear {
                        session.configStore.reload()
                        session.workspaceStore.reload()
                        session.watcherStore.reload()
                    }
            }
        }
        .defaultSize(width: 800, height: 600)

        /// Python `TriggersDialog`: `~/.grizzyclaw/triggers.json`.
        Window("⚡ Automation Triggers", id: "triggers") {
            AppThemedWindowRoot(configStore: session.configStore) {
                AutomationTriggersMainView()
                    .id(session.configStore.snapshot.theme)
                    .frame(minWidth: 650, minHeight: 500)
                    .onAppear {
                        session.configStore.reload()
                    }
            }
        }
        .defaultSize(width: 700, height: 560)

        /// Python `SettingsDialog`: `setWindowTitle("Preferences")`, `setMinimumSize(700, 550)` (`settings_dialog.py`).
        Window("Preferences", id: "preferences") {
            PreferencesMainView(
                configStore: session.configStore,
                workspaceStore: session.workspaceStore,
                guiChatPrefs: session.guiChatPrefs,
                telegramService: session.telegramService
            )
            .environmentObject(session.statusBarStore)
            .id(session.configStore.snapshot.theme)
            .frame(minWidth: 700, minHeight: 550)
            .onAppear {
                session.configStore.reload()
                session.workspaceStore.reload()
            }
        }
        .defaultSize(width: 780, height: 600)

        /// Visual Canvas: separate window (not split beside chat). Open/close from chat toolbar; auto-opens when the agent pushes canvas content.
        Window("Visual Canvas", id: "visualCanvas") {
            AppThemedWindowRoot(configStore: session.configStore) {
                VisualCanvasWindowContent(
                    model: session.visualCanvas,
                    onWindowWillClose: {
                        session.visualCanvasWindowOpen = false
                    }
                )
                .frame(minWidth: 480, minHeight: 440)
            }
        }
        .defaultSize(width: 720, height: 620)
    }
}

/// Legacy entry when using `SomeApp.main()` from a custom `main`; prefer `@main struct … App` + delegate + `GrizzyClawRootScene`.
public struct GrizzyClawRootApp: App {
    @NSApplicationDelegateAdaptor(GrizzyClawAppDelegate.self) private var appDelegate

    public init() {}

    public var body: some Scene {
        GrizzyClawRootScene()
    }
}

/// Legacy single-window preview; prefer `GrizzyClawRootContentView(session:)`.
public struct ContentView: View {
    @StateObject private var session = GrizzyClawSession()

    public init() {}

    public var body: some View {
        GrizzyClawRootContentView(session: session)
    }
}
