import Foundation

/// Paths aligned with the Python app (`grizzyclaw.config` / `WorkspaceManager`): `~/.grizzyclaw/`.
public enum GrizzyClawPaths {
    /// `~/.grizzyclaw` — same as Python `_user_config_dir()` / workspace `data_dir`.
    public static var userDataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grizzyclaw", isDirectory: true)
    }

    /// `~/.grizzyclaw/config.yaml` — GUI load/save path (`get_config_path_for_app()`).
    public static var configYAML: URL {
        userDataDirectory.appendingPathComponent("config.yaml")
    }

    /// `~/.grizzyclaw/workspaces.json`
    public static var workspacesJSON: URL {
        userDataDirectory.appendingPathComponent("workspaces.json")
    }

    /// `~/.grizzyclaw/workspace_templates.json`
    public static var workspaceTemplatesJSON: URL {
        userDataDirectory.appendingPathComponent("workspace_templates.json")
    }

    /// `~/.grizzyclaw/watchers/` — per-file watcher JSON (Python `watcher_store`).
    public static var watchersDirectory: URL {
        userDataDirectory.appendingPathComponent("watchers", isDirectory: true)
    }

    /// Creates `~/.grizzyclaw` (and parents) if needed.
    @discardableResult
    public static func ensureUserDataDirectoryExists() throws -> URL {
        let url = userDataDirectory
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
