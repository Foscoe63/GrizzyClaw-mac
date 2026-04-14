import Foundation
import SQLite3

// MARK: - Path (Python `WorkspaceManager` + `workspace.get_memory_db_path` / shared channel DB)

extension WorkspaceRecord {
    /// Resolved absolute URL of the workspace memory SQLite file under `~/.grizzyclaw/`, matching Python agent `settings.database_url`.
    public func memoryDatabaseURL() -> URL {
        let base = GrizzyClawPaths.userDataDirectory
        if config?.bool(forKey: "use_shared_memory") == true {
            let raw = config?.string(forKey: "inter_agent_channel")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let channel = raw.isEmpty ? "default" : raw
            return base.appendingPathComponent("shared_memory_\(channel).db")
        }
        if let mf = config?.string(forKey: "memory_file") {
            let trimmed = mf.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if trimmed.hasPrefix("/") {
                    return URL(fileURLWithPath: trimmed)
                }
                return base.appendingPathComponent(trimmed)
            }
        }
        return base.appendingPathComponent("workspace_\(id).db")
    }
}

// MARK: - Rows / summary (Python `memory_dialog` + `sqlite_store`)

public struct MemoryCategorySummary: Identifiable, Hashable, Sendable {
    public let name: String
    public let itemCount: Int
    public var id: String { name }
}

public struct MemoryItemRow: Identifiable, Sendable {
    public let id: String
    public let userId: String
    public let content: String
    public let category: String
    public let createdAt: Date?
}

public struct MemoryUserSummary: Sendable {
    public let totalItems: Int
    public let categories: [MemoryCategorySummary]
    public let recentItems: [MemoryItemRow]
}

/// Read/write the same `memory_items` table as Python `SQLiteMemoryStore` (`grizzyclaw/memory/sqlite_store.py`).
public enum WorkspaceMemorySQLite {
    public static func loadSummary(userId: String, dbURL: URL) throws -> MemoryUserSummary {
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            return MemoryUserSummary(totalItems: 0, categories: [], recentItems: [])
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw MemorySQLiteError.openFailed
        }
        defer { sqlite3_close(db) }

        let total = try countItems(db: db, userId: userId)
        let cats = try fetchCategories(db: db, userId: userId)
        let recent = try queryMemories(db: db, userId: userId, limit: 5, category: nil)
        return MemoryUserSummary(totalItems: total, categories: cats, recentItems: recent)
    }

    public static func listMemories(userId: String, limit: Int, category: String?, dbURL: URL) throws -> [MemoryItemRow] {
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw MemorySQLiteError.openFailed
        }
        defer { sqlite3_close(db) }
        return try queryMemories(db: db, userId: userId, limit: limit, category: category)
    }

    public static func deleteMemory(id: String, dbURL: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return false }
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            throw MemorySQLiteError.openFailed
        }
        defer { sqlite3_close(db) }

        try deleteVecRowIfPresent(db: db, memoryId: id)
        var stmt: OpaquePointer?
        let sql = "DELETE FROM memory_items WHERE id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MemorySQLiteError.prepareFailed
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, id)
        let rc = sqlite3_step(stmt)
        return rc == SQLITE_DONE && sqlite3_changes(db) > 0
    }

    /// Deletes all rows for `userId`; returns row count removed. Matches Python `clear_all` (delete each + vec cleanup).
    public static func deleteAllForUser(userId: String, dbURL: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return 0 }
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
            throw MemorySQLiteError.openFailed
        }
        defer { sqlite3_close(db) }

        let ids = try listAllIds(db: db, userId: userId)
        for mid in ids {
            try deleteVecRowIfPresent(db: db, memoryId: mid)
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM memory_items WHERE user_id = ?", -1, &stmt, nil) == SQLITE_OK else {
            throw MemorySQLiteError.prepareFailed
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, userId)
        _ = sqlite3_step(stmt)
        return Int(sqlite3_changes(db))
    }

    private static func listAllIds(db: OpaquePointer, userId: String) throws -> [String] {
        var stmt: OpaquePointer?
        let sql = "SELECT id FROM memory_items WHERE user_id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MemorySQLiteError.prepareFailed
        }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, userId)
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) {
                out.append(String(cString: c))
            }
        }
        return out
    }
}

public enum MemorySQLiteError: Error {
    case openFailed
    case prepareFailed
}

// MARK: - Private SQLite helpers

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) {
    _ = value.withCString { c in
        sqlite3_bind_text(stmt, idx, c, -1, SQLITE_TRANSIENT)
    }
}

private func countItems(db: OpaquePointer, userId: String) throws -> Int {
    var stmt: OpaquePointer?
    let sql = "SELECT COUNT(*) FROM memory_items WHERE user_id = ?"
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw MemorySQLiteError.prepareFailed
    }
    defer { sqlite3_finalize(stmt) }
    bindText(stmt, 1, userId)
    guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
    return Int(sqlite3_column_int64(stmt, 0))
}

private func fetchCategories(db: OpaquePointer, userId: String) throws -> [MemoryCategorySummary] {
    var stmt: OpaquePointer?
    let sql = """
        SELECT COALESCE(category, 'general') AS category, COUNT(*) AS item_count
        FROM memory_items
        WHERE user_id = ?
        GROUP BY category
        ORDER BY item_count DESC
        """
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw MemorySQLiteError.prepareFailed
    }
    defer { sqlite3_finalize(stmt) }
    bindText(stmt, 1, userId)
    var out: [MemoryCategorySummary] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        let name = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "general"
        let count = Int(sqlite3_column_int64(stmt, 1))
        out.append(MemoryCategorySummary(name: name, itemCount: count))
    }
    return out
}

private func queryMemories(db: OpaquePointer, userId: String, limit: Int, category: String?) throws -> [MemoryItemRow] {
    var stmt: OpaquePointer?
    let sql: String
    if category != nil {
        sql = """
            SELECT id, user_id, content, category, created_at
            FROM memory_items
            WHERE user_id = ? AND COALESCE(category, 'general') = ?
            ORDER BY created_at DESC
            LIMIT ?
            """
    } else {
        sql = """
            SELECT id, user_id, content, category, created_at
            FROM memory_items
            WHERE user_id = ?
            ORDER BY created_at DESC
            LIMIT ?
            """
    }
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        throw MemorySQLiteError.prepareFailed
    }
    defer { sqlite3_finalize(stmt) }
    bindText(stmt, 1, userId)
    if let cat = category {
        bindText(stmt, 2, cat)
        sqlite3_bind_int64(stmt, 3, Int64(limit))
    } else {
        sqlite3_bind_int64(stmt, 2, Int64(limit))
    }
    var out: [MemoryItemRow] = []
    while sqlite3_step(stmt) == SQLITE_ROW {
        let id = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
        let uid = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
        let content = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
        let catCol = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : sqlite3_column_text(stmt, 3).map { String(cString: $0) }
        let category = catCol?.isEmpty == false ? catCol! : "general"
        let createdStr = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
        let created = createdStr.flatMap { parseSQLiteDate($0) }
        out.append(MemoryItemRow(id: id, userId: uid, content: content, category: category, createdAt: created))
    }
    return out
}

private func deleteVecRowIfPresent(db: OpaquePointer, memoryId: String) throws {
    var stmt: OpaquePointer?
    let sqlRow = "SELECT rowid FROM memory_items WHERE id = ?"
    guard sqlite3_prepare_v2(db, sqlRow, -1, &stmt, nil) == SQLITE_OK else { return }
    defer { sqlite3_finalize(stmt) }
    bindText(stmt, 1, memoryId)
    guard sqlite3_step(stmt) == SQLITE_ROW else { return }
    let rowid = sqlite3_column_int64(stmt, 0)
    var del: OpaquePointer?
    if sqlite3_prepare_v2(db, "DELETE FROM vec_memory WHERE rowid = ?", -1, &del, nil) == SQLITE_OK {
        defer { sqlite3_finalize(del) }
        sqlite3_bind_int64(del, 1, rowid)
        _ = sqlite3_step(del)
    }
}

private func parseSQLiteDate(_ s: String) -> Date? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return nil }
    let isoFrac = ISO8601DateFormatter()
    isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = isoFrac.date(from: t) { return d }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    if let d = iso.date(from: t) { return d }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f.date(from: t) ?? f.date(from: String(t.prefix(19)))
}
