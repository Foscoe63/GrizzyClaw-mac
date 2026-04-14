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

    /// `~/.grizzyclaw/sessions/` — per-workspace chat JSON (`{workspaceId}_{userId}.json`, matches Python `AgentCore`).
    public static var sessionsDirectory: URL {
        userDataDirectory.appendingPathComponent("sessions", isDirectory: true)
    }

    /// `~/.grizzyclaw/workspace_templates.json`
    public static var workspaceTemplatesJSON: URL {
        userDataDirectory.appendingPathComponent("workspace_templates.json")
    }

    /// `~/.grizzyclaw/skill_marketplace.json` (Python `load_skill_marketplace` fallback).
    public static var skillMarketplaceJSON: URL {
        userDataDirectory.appendingPathComponent("skill_marketplace.json")
    }

    /// `~/.grizzyclaw/skills.json` — per-skill options (`load_user_skills` / `SkillConfigDialog` in Python).
    public static var skillsJSON: URL {
        userDataDirectory.appendingPathComponent("skills.json", isDirectory: false)
    }

    /// `~/.grizzyclaw/watchers/` — per-file watcher JSON (Python `watcher_store`).
    public static var watchersDirectory: URL {
        userDataDirectory.appendingPathComponent("watchers", isDirectory: true)
    }

    /// `~/.grizzyclaw/scheduled_tasks.json` — Python `AgentCore._scheduled_tasks_path()` / `SchedulerDialog`.
    public static var scheduledTasksJSON: URL {
        userDataDirectory.appendingPathComponent("scheduled_tasks.json")
    }

    /// `~/.grizzyclaw/daemon.sock` — Python `IPCServer` Unix socket when the background daemon is running.
    public static var daemonSocket: URL {
        userDataDirectory.appendingPathComponent("daemon.sock")
    }

    /// `~/.grizzyclaw/daemon_stderr.log` — Python daemon stderr redirect (troubleshooting).
    public static var daemonStderrLog: URL {
        userDataDirectory.appendingPathComponent("daemon_stderr.log")
    }

    /// `~/.grizzyclaw/triggers.json` — Python `automation.triggers.load_triggers` / `TriggersDialog`.
    public static var triggersJSON: URL {
        userDataDirectory.appendingPathComponent("triggers.json")
    }

    /// Creates `~/.grizzyclaw` (and parents) if needed.
    @discardableResult
    public static func ensureUserDataDirectoryExists() throws -> URL {
        let url = userDataDirectory
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Ensures `sessions/` exists (Python `_sessions_dir()`).
    @discardableResult
    public static func ensureSessionsDirectoryExists() throws -> URL {
        let url = sessionsDirectory
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Ensures `watchers/` exists (Python `watcher_store.ensure_watchers_dir`).
    @discardableResult
    public static func ensureWatchersDirectoryExists() throws -> URL {
        let url = watchersDirectory
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// `~/.grizzyclaw/mlx_models/` — Hugging Face hub download root for bundled MLX models (mlx-swift-lm).
    public static var mlxModelsDirectory: URL {
        userDataDirectory.appendingPathComponent("mlx_models", isDirectory: true)
    }

    /// Creates `mlx_models/` if needed.
    @discardableResult
    public static func ensureMLXModelsDirectoryExists() throws -> URL {
        let url = mlxModelsDirectory
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Resolves Hugging Face hub download root for MLX (`HubApi(downloadBase:)`). Empty or nil `userConfiguredPath` uses ``mlxModelsDirectory``; otherwise expands `~` and ensures the directory exists.
    public static func mlxDownloadRoot(userConfiguredPath: String?) throws -> URL {
        let raw = userConfiguredPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url: URL
        if raw.isEmpty {
            url = mlxModelsDirectory
        } else {
            let exp = (raw as NSString).expandingTildeInPath
            url = URL(fileURLWithPath: exp, isDirectory: true)
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                throw NSError(
                    domain: "GrizzyClawPaths",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "MLX models path is not a directory: \(url.path)"]
                )
            }
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

