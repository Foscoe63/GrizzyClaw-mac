import AppKit
import GrizzyClawCore

/// macOS shell integrations (Finder, etc.).
public enum GrizzyClawShell {
    /// Ensures `~/.grizzyclaw` exists and opens it in Finder.
    public static func revealUserDataFolder() {
        do {
            try GrizzyClawPaths.ensureUserDataDirectoryExists()
            NSWorkspace.shared.open(GrizzyClawPaths.userDataDirectory)
        } catch {
            NSWorkspace.shared.open(GrizzyClawPaths.userDataDirectory)
        }
    }
}
