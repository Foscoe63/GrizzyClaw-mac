import Foundation

/// Lists Hugging Face model repo ids found on disk under an MLX ``GrizzyClawPaths``/Hub download root (no MLX frameworks — safe for GrizzyClawAgent).
///
/// Matches **swift-transformers** `HubApi` layout (`models/<namespace>/<repo>/`) and optional **Python** `hub/models--*` cache folders.
public enum CachedMLXHubRepoIds {
    /// `namespace/name` with exactly one `/` (Hugging Face repo id shape).
    static func isValidRepoIdString(_ s: String) -> Bool {
        let parts = s.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return false }
        return !parts[0].isEmpty && !parts[1].isEmpty
    }

    /// Decodes `models--namespace--repo-name` folder names (Python hub cache).
    private static func repoIdFromHubCacheFolderName(_ folderName: String) -> String? {
        guard folderName.hasPrefix("models--") else { return nil }
        let body = String(folderName.dropFirst("models--".count))
        var start = body.startIndex
        while start < body.endIndex {
            guard let range = body[start...].range(of: "--") else { break }
            let left = String(body[..<range.lowerBound])
            let right = String(body[range.upperBound...])
            let candidate = "\(left)/\(right)"
            if isValidRepoIdString(candidate) {
                return candidate
            }
            start = body.index(after: range.lowerBound)
        }
        return nil
    }

    private static func listRepoIdsFromPythonHubLayout(downloadRoot: URL) -> [String] {
        let hub = downloadRoot.appendingPathComponent("hub", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: hub,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var ids: Set<String> = []
        for u in contents {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            let name = u.lastPathComponent
            guard let id = repoIdFromHubCacheFolderName(name) else { continue }
            ids.insert(id)
        }
        return Array(ids)
    }

    private static func listRepoIdsFromSwiftHubLayout(downloadRoot: URL) -> [String] {
        let modelsRoot = downloadRoot.appendingPathComponent("models", isDirectory: true)
        guard let orgURLs = try? FileManager.default.contentsOfDirectory(
            at: modelsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var ids: Set<String> = []
        for orgURL in orgURLs {
            var orgIsDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: orgURL.path, isDirectory: &orgIsDir), orgIsDir.boolValue else {
                continue
            }
            let org = orgURL.lastPathComponent
            if org.hasPrefix(".") { continue }
            guard let repoURLs = try? FileManager.default.contentsOfDirectory(
                at: orgURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for repoURL in repoURLs {
                var repoIsDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: repoURL.path, isDirectory: &repoIsDir), repoIsDir.boolValue else {
                    continue
                }
                let repoName = repoURL.lastPathComponent
                if repoName.hasPrefix(".") { continue }
                let candidate = "\(org)/\(repoName)"
                if isValidRepoIdString(candidate) {
                    ids.insert(candidate)
                }
            }
        }
        return Array(ids)
    }

    /// Sorted unique repo ids under ``downloadRoot`` (Swift `models/…` and/or Python `hub/…`).
    public static func listRepoIds(downloadRoot: URL) -> [String] {
        var combined = Set<String>()
        combined.formUnion(listRepoIdsFromSwiftHubLayout(downloadRoot: downloadRoot))
        combined.formUnion(listRepoIdsFromPythonHubLayout(downloadRoot: downloadRoot))
        return combined.sorted()
    }
}
