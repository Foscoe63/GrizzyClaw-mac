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
        }
    }
}
