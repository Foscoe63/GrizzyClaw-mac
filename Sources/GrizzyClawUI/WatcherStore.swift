import Combine
import GrizzyClawCore
import SwiftUI

/// Loads and saves `~/.grizzyclaw/watchers/*.json` (Python `watcher_store` format).
@MainActor
public final class WatcherStore: ObservableObject {
    @Published public private(set) var watchers: [FolderWatcherRecord] = []
    @Published public private(set) var loadError: String?
    @Published public var saveError: String?
    @Published public private(set) var isReloading = false

    public init() {}

    public func reload() {
        isReloading = true
        defer { isReloading = false }
        do {
            let rows = try WatchersPersistence.loadAll()
            watchers = rows.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
            GrizzyClawLog.error("watchers reload failed: \(error.localizedDescription)")
            watchers = []
        }
    }

    /// Writes one watcher file; creates `watchers/` if needed.
    public func save(_ watcher: FolderWatcherRecord) throws {
        do {
            try WatchersPersistence.save(watcher)
            saveError = nil
            reload()
        } catch {
            saveError = error.localizedDescription
            GrizzyClawLog.error("watcher save failed: \(error.localizedDescription)")
            throw error
        }
    }

    public func delete(id: String) throws {
        do {
            try WatchersPersistence.delete(id: id)
            saveError = nil
            reload()
        } catch {
            saveError = error.localizedDescription
            GrizzyClawLog.error("watcher delete failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Creates a new UUID file on disk and returns the record.
    @discardableResult
    public func create() throws -> FolderWatcherRecord {
        let w = FolderWatcherRecord.makeNew()
        try save(w)
        return w
    }
}
