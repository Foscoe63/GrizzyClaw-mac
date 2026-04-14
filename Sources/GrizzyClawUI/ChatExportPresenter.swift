import AppKit
import Foundation
import GrizzyClawAgent
import UniformTypeIdentifiers

/// Save-panel export for the Chat tab (Markdown or JSON).
public enum ChatExportPresenter {
    @MainActor
    public static func presentSavePanel(
        messages: [ChatMessage],
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText, .json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "grizzyclaw-chat-export.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let path = url.path.lowercased()
            let data: Data
            let note: String
            if path.hasSuffix(".json") {
                data = try ChatExportFormatting.jsonData(from: messages)
                note = "Exported JSON (\(messages.count) messages)."
            } else {
                let md = ChatExportFormatting.markdown(from: messages)
                data = Data(md.utf8)
                note = "Exported Markdown (\(messages.count) messages)."
            }
            try data.write(to: url, options: .atomic)
            completion(.success(note))
        } catch {
            completion(.failure(error))
        }
    }
}

private enum ChatExportFormatting {
    static func markdown(from messages: [ChatMessage]) -> String {
        var lines: [String] = ["# GrizzyClaw chat export", ""]
        for m in messages {
            let title = m.role.rawValue.capitalized
            lines.append("## \(title)")
            lines.append(m.content)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func jsonData(from messages: [ChatMessage]) throws -> Data {
        let arr: [[String: String]] = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        return try JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted, .sortedKeys])
    }
}
