import Combine
import GrizzyClawCore
import SwiftUI

/// Loads read-only `workspaces.json` (Python `WorkspaceManager` format).
@MainActor
public final class WorkspaceStore: ObservableObject {
    @Published public private(set) var index: WorkspaceIndex?
    @Published public private(set) var loadError: String?

    public init() {}

    public func reload() {
        let url = GrizzyClawPaths.workspacesJSON
        guard FileManager.default.fileExists(atPath: url.path) else {
            index = nil
            loadError = nil
            return
        }
        do {
            index = try WorkspaceIndexLoader.load(from: url)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
            index = nil
        }
    }
}
