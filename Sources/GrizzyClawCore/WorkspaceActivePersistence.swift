import Foundation

/// Writes only the top-level `active_workspace_id` field in `workspaces.json`, preserving the rest of the file
/// (same semantics as Python `WorkspaceManager.set_active_workspace` + `_save_workspaces`).
public enum WorkspaceActivePersistence {
    public enum PersistenceError: Swift.Error, LocalizedError {
        case fileMissing(URL)
        case invalidRoot
        case invalidWorkspacesArray
        case unknownWorkspaceId(String)

        public var errorDescription: String? {
            switch self {
            case .fileMissing(let url):
                return "workspaces.json not found at \(url.path)"
            case .invalidRoot:
                return "workspaces.json root must be a JSON object"
            case .invalidWorkspacesArray:
                return "workspaces.json must contain a \"workspaces\" array"
            case .unknownWorkspaceId(let id):
                return "No workspace with id \"\(id)\""
            }
        }
    }

    /// Updates `active_workspace_id` if it differs; validates that `id` appears in `workspaces`.
    /// Uses `JSONSerialization` so nested objects/arrays are preserved exactly.
    public static func setActiveWorkspaceId(_ id: String, fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw PersistenceError.fileMissing(fileURL)
        }
        let data = try Data(contentsOf: fileURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PersistenceError.invalidRoot
        }
        guard let workspaces = root["workspaces"] as? [[String: Any]] else {
            throw PersistenceError.invalidWorkspacesArray
        }
        let knownIds = Set(workspaces.compactMap { $0["id"] as? String })
        guard knownIds.contains(id) else {
            throw PersistenceError.unknownWorkspaceId(id)
        }
        if (root["active_workspace_id"] as? String) == id {
            return
        }
        root["active_workspace_id"] = id
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
        try out.write(to: fileURL, options: .atomic)
    }

    /// Updates `baseline_workspace_id` if it differs; validates that `id` appears in `workspaces`.
    public static func setBaselineWorkspaceId(_ id: String, fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw PersistenceError.fileMissing(fileURL)
        }
        let data = try Data(contentsOf: fileURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PersistenceError.invalidRoot
        }
        guard let workspaces = root["workspaces"] as? [[String: Any]] else {
            throw PersistenceError.invalidWorkspacesArray
        }
        let knownIds = Set(workspaces.compactMap { $0["id"] as? String })
        guard knownIds.contains(id) else {
            throw PersistenceError.unknownWorkspaceId(id)
        }
        if (root["baseline_workspace_id"] as? String) == id {
            return
        }
        root["baseline_workspace_id"] = id
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
        try out.write(to: fileURL, options: .atomic)
    }
}
