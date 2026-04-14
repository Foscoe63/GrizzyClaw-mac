import Foundation

/// Shared HTTP failure payload for streaming LLM clients.
public enum LLMStreamHTTPError: LocalizedError, Sendable {
    case httpStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case .httpStatus(let code, let body):
            let tail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if tail.isEmpty { return "HTTP \(code)" }
            return "HTTP \(code): \(tail.prefix(500))"
        }
    }
}
