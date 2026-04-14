import Foundation

public enum ChatImportError: LocalizedError, Sendable {
    case empty
    case invalidJSON
    case invalidMarkdown

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "The file contained no messages to import."
        case .invalidJSON:
            return "Expected a JSON array of objects with \"role\" and \"content\"."
        case .invalidMarkdown:
            return "Could not parse Markdown headings (use ## User / ## Assistant / ## System as in exports)."
        }
    }
}

/// Parses GrizzyClaw chat **export** JSON or Markdown into persisted turns.
public enum ChatImportParser {
    public static func parse(data: Data, filenameHint: String?) throws -> [PersistedChatTurn] {
        let name = filenameHint?.lowercased() ?? ""
        if name.hasSuffix(".json") {
            return try parseJSON(data)
        }
        if name.hasSuffix(".md") || name.hasSuffix(".markdown") || name.hasSuffix(".txt") {
            return try parseMarkdown(String(decoding: data, as: UTF8.self))
        }
        if let turns = try? parseJSON(data), !turns.isEmpty {
            return turns
        }
        return try parseMarkdown(String(decoding: data, as: UTF8.self))
    }

    private static func parseJSON(_ data: Data) throws -> [PersistedChatTurn] {
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let arr = obj as? [[String: Any]] else {
            throw ChatImportError.invalidJSON
        }
        let turns: [PersistedChatTurn] = arr.compactMap { dict in
            let r = dict["role"] as? String ?? "user"
            let c = dict["content"] as? String ?? ""
            return PersistedChatTurn(role: r, content: c)
        }
        guard !turns.isEmpty else { throw ChatImportError.empty }
        return turns
    }

    private static func parseMarkdown(_ text: String) throws -> [PersistedChatTurn] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var turns: [PersistedChatTurn] = []
        var currentRole: String?
        var currentLines: [String] = []

        func flush() {
            guard let role = currentRole else { return }
            let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                turns.append(PersistedChatTurn(role: role, content: body))
            }
            currentLines = []
        }

        let heading = try NSRegularExpression(pattern: "^##\\s+(System|User|Assistant)\\s*$", options: [.anchorsMatchLines])

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let m = heading.firstMatch(in: line, options: [], range: range),
               let r = Range(m.range(at: 1), in: line) {
                flush()
                currentRole = String(line[r]).lowercased()
                continue
            }
            if currentRole != nil {
                currentLines.append(line)
            }
        }
        flush()

        guard !turns.isEmpty else { throw ChatImportError.invalidMarkdown }
        return turns
    }
}
