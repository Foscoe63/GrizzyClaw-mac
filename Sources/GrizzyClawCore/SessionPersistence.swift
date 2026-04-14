import Foundation

/// One message in `~/.grizzyclaw/sessions/{workspace}_{user}.json` (Python `AgentCore._save_session`).
public struct PersistedChatTurn: Codable, Sendable, Equatable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// Read/write chat history compatible with the Python app (`gui_user` default).
public enum SessionPersistence {
    /// Default chat user id in the Python GUI (`main_window.py` / CLI).
    public static let defaultUserId = "gui_user"

    public enum SessionError: LocalizedError, Sendable {
        case invalidJSON(URL)

        public var errorDescription: String? {
            switch self {
            case .invalidJSON(let url):
                return "Could not read session file: \(url.path)"
            }
        }
    }

    public static func sessionFileURL(workspaceId: String, userId: String = defaultUserId) -> URL {
        let safeWs = safeSegment(workspaceId, fallback: "default")
        let safeUser = safeSegment(userId, fallback: "user")
        return GrizzyClawPaths.sessionsDirectory
            .appendingPathComponent("\(safeWs)_\(safeUser).json", isDirectory: false)
    }

    private static func safeSegment(_ raw: String, fallback: String) -> String {
        var s = raw.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_")
        if s.isEmpty { s = fallback }
        if s.count > 64 { s = String(s.prefix(64)) }
        return s
    }

    /// Loads persisted turns; returns empty if missing, invalid, or persistence disabled by caller.
    public static func loadTurns(workspaceId: String, userId: String = defaultUserId) throws -> [PersistedChatTurn] {
        let url = sessionFileURL(workspaceId: workspaceId, userId: userId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard let arr = decoded as? [[String: Any]] else {
            throw SessionError.invalidJSON(url)
        }
        return arr.compactMap { dict in
            let r = dict["role"] as? String ?? "user"
            let c = dict["content"] as? String ?? ""
            return PersistedChatTurn(role: r, content: c)
        }
    }

    public static func saveTurns(_ turns: [PersistedChatTurn], workspaceId: String, userId: String = defaultUserId) throws {
        try GrizzyClawPaths.ensureSessionsDirectoryExists()
        let url = sessionFileURL(workspaceId: workspaceId, userId: userId)
        let payload = turns.map { ["role": $0.role, "content": $0.content] }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: url, options: .atomic)
    }

    public static func clearFile(workspaceId: String, userId: String = defaultUserId) throws {
        let url = sessionFileURL(workspaceId: workspaceId, userId: userId)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        clearRecordedModificationDate(workspaceId: workspaceId)
    }

    // MARK: - Track A (mtime, archive)

    private static func mtimeStorageKey(workspaceId: String) -> String {
        "grizzy.sessionFileMtime.\(workspaceId)"
    }

    /// Current session file modification date, if the file exists.
    public static func fileModificationDate(workspaceId: String, userId: String = defaultUserId) -> Date? {
        let url = sessionFileURL(workspaceId: workspaceId, userId: userId)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let v = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return v?.contentModificationDate
    }

    /// Returns `true` if the file exists and its mtime differs from the last value recorded by this app (external or other writer).
    public static func hasSessionFileChangedSinceRecorded(workspaceId: String, userId: String = defaultUserId) -> Bool {
        guard let disk = fileModificationDate(workspaceId: workspaceId, userId: userId) else {
            return false
        }
        let prev = UserDefaults.standard.double(forKey: mtimeStorageKey(workspaceId: workspaceId))
        guard prev > 0 else { return false }
        return abs(disk.timeIntervalSince1970 - prev) > 0.001
    }

    /// Call after loading from disk or after saving so the next sync can detect external edits.
    public static func recordSessionFileModificationDate(workspaceId: String, userId: String = defaultUserId) {
        guard let d = fileModificationDate(workspaceId: workspaceId, userId: userId) else {
            UserDefaults.standard.removeObject(forKey: mtimeStorageKey(workspaceId: workspaceId))
            return
        }
        UserDefaults.standard.set(d.timeIntervalSince1970, forKey: mtimeStorageKey(workspaceId: workspaceId))
    }

    /// Clears the remembered mtime (e.g. after deleting the session file).
    public static func clearRecordedModificationDate(workspaceId: String) {
        UserDefaults.standard.removeObject(forKey: mtimeStorageKey(workspaceId: workspaceId))
    }

    /// Moves the active session file to a timestamped name in `sessions/` if it exists and is non-empty. Returns the archive URL, or `nil` if there was nothing to archive.
    public static func archiveCurrentSessionIfNonEmpty(workspaceId: String, userId: String = defaultUserId) throws -> URL? {
        let src = sessionFileURL(workspaceId: workspaceId, userId: userId)
        guard FileManager.default.fileExists(atPath: src.path) else { return nil }
        let turns = try loadTurns(workspaceId: workspaceId, userId: userId)
        guard !turns.isEmpty else { return nil }
        try GrizzyClawPaths.ensureSessionsDirectoryExists()
        let dest = archivedSessionURL(workspaceId: workspaceId, userId: userId)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: src, to: dest)
        clearRecordedModificationDate(workspaceId: workspaceId)
        return dest
    }

    private static func archivedSessionURL(workspaceId: String, userId: String) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let stamp = f.string(from: Date())
        let safeWs = safeSegment(workspaceId, fallback: "default")
        let safeUser = safeSegment(userId, fallback: "user")
        return GrizzyClawPaths.sessionsDirectory
            .appendingPathComponent("\(safeWs)_\(safeUser)_archived_\(stamp).json", isDirectory: false)
    }
}
