import Foundation

public enum WatchersPersistenceError: LocalizedError, Sendable {
    case directoryUnavailable
    case encodeFailed
    case writeFailed(String)
    case deleteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .directoryUnavailable:
            return "Could not access ~/.grizzyclaw/watchers/"
        case .encodeFailed:
            return "Could not encode watcher JSON."
        case .writeFailed(let s): return s
        case .deleteFailed(let s): return s
        }
    }
}

/// Read/write `~/.grizzyclaw/watchers/*.json` compatible with Python `watcher_store.py`.
public enum WatchersPersistence {
    public static func loadAll(directory: URL = GrizzyClawPaths.watchersDirectory) throws -> [FolderWatcherRecord] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let jsonFiles = urls.filter { $0.pathExtension.lowercased() == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var out: [FolderWatcherRecord] = []
        out.reserveCapacity(jsonFiles.count)
        for url in jsonFiles {
            do {
                let data = try Data(contentsOf: url)
                var row = try JSONDecoder().decode(FolderWatcherRecord.self, from: data)
                if row.id.isEmpty {
                    row.id = url.deletingPathExtension().lastPathComponent
                }
                out.append(row)
            } catch {
                continue
            }
        }
        return out
    }

    public static func save(_ watcher: FolderWatcherRecord, directory: URL = GrizzyClawPaths.watchersDirectory) throws {
        try GrizzyClawPaths.ensureWatchersDirectoryExists()
        let url = directory.appendingPathComponent("\(watcher.id).json")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try enc.encode(watcher)
        } catch {
            throw WatchersPersistenceError.encodeFailed
        }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            throw WatchersPersistenceError.writeFailed(error.localizedDescription)
        }
    }

    public static func delete(id: String, directory: URL = GrizzyClawPaths.watchersDirectory) throws {
        let url = directory.appendingPathComponent("\(id).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw WatchersPersistenceError.deleteFailed(error.localizedDescription)
        }
    }
}
