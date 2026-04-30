import GrizzyClawCore
import SwiftUI

/// Menu commands (app menu additions). Kept separate from `GrizzyClawRootApp` for readability.
public struct GrizzyClawMenuCommands: Commands {
    public init() {}

    public var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Open ~/.grizzyclaw in Finder…") {
                GrizzyClawShell.revealUserDataFolder()
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
            Button("Workspaces…") {
                NotificationCenter.default.post(name: .grizzyOpenWorkspacesWindow, object: nil)
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            Button("Memory…") {
                NotificationCenter.default.post(name: .grizzyOpenMemoryWindow, object: nil)
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Scheduled Tasks…") {
                NotificationCenter.default.post(name: .grizzyOpenSchedulerWindow, object: nil)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Browser Automation…") {
                NotificationCenter.default.post(name: .grizzyOpenBrowserWindow, object: nil)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])
            Button("Conversation history…") {
                NotificationCenter.default.post(name: .grizzyOpenConversationHistoryWindow, object: nil)
            }
            Button("Usage & Performance…") {
                NotificationCenter.default.post(name: .grizzyOpenUsageDashboardWindow, object: nil)
            }
            Button("Watchers…") {
                NotificationCenter.default.post(name: .grizzyOpenWatchersWindow, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Preferences…") {
                NotificationCenter.default.post(name: .grizzyOpenPreferencesWindow, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
            Button("Automation Triggers…") {
                NotificationCenter.default.post(name: .grizzyOpenTriggersWindow, object: nil)
            }
            Button("Return to baseline workspace") {
                NotificationCenter.default.post(name: .grizzyReturnToBaseline, object: nil)
            }
            .keyboardShortcut("b", modifiers: [.control, .shift])
            Divider()
            Button("Create backup of ~/.grizzyclaw…") {
                GrizzyClawShell.presentBackupSavePanel()
            }
        }
    }
}
