import AppKit
import Foundation
import GrizzyClawCore
import UniformTypeIdentifiers

/// Open-panel import for chat JSON / Markdown exports.
public enum ChatImportPresenter {
    /// `url` is `nil` when the user cancels.
    @MainActor
    public static func presentOpenPanel(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json, .plainText]
        guard panel.runModal() == .OK, let url = panel.url else {
            completion(nil)
            return
        }
        completion(url)
    }
}
