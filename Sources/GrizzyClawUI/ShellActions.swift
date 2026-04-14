import AppKit
import GrizzyClawCore
import UniformTypeIdentifiers

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

    /// Selects a file in Finder if it exists; otherwise reveals its parent folder (e.g. before first save).
    public static func revealInFinder(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let dir = url.deletingLastPathComponent()
            _ = try? GrizzyClawPaths.ensureUserDataDirectoryExists()
            if FileManager.default.fileExists(atPath: dir.path) {
                NSWorkspace.shared.open(dir)
            }
        }
    }

    /// Zips essential `~/.grizzyclaw` files (config, workspaces, sessions, watchers, templates) after a save panel.
    public static func presentBackupSavePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "grizzyclaw-backup.zip"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Self.createBackupZip(at: url)
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Backup failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    private static func createBackupZip(at destination: URL) throws {
        try GrizzyClawPaths.ensureUserDataDirectoryExists()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let rel = [
            ".grizzyclaw/config.yaml",
            ".grizzyclaw/workspaces.json",
            ".grizzyclaw/workspace_templates.json",
            ".grizzyclaw/sessions",
            ".grizzyclaw/watchers",
        ]
        let existing = rel.filter { FileManager.default.fileExists(atPath: home.appendingPathComponent($0).path) }
        guard !existing.isEmpty else {
            throw BackupError.nothingToBackup
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        var args = ["-r", destination.path]
        args.append(contentsOf: existing)
        p.arguments = args
        p.currentDirectoryURL = home
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw BackupError.zipFailed(code: p.terminationStatus)
        }
    }

    private enum BackupError: LocalizedError {
        case nothingToBackup
        case zipFailed(code: Int32)

        var errorDescription: String? {
            switch self {
            case .nothingToBackup:
                return "No ~/.grizzyclaw files found to include in the archive."
            case .zipFailed(let code):
                return "zip exited with status \(code)."
            }
        }
    }
}
