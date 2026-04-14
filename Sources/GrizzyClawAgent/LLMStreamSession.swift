import Foundation

/// Owns a dedicated `URLSession` for one streaming request so `invalidateAndCancel()` tears down in-flight loads promptly when the user stops generation.
public final class LLMStreamSessionBox: @unchecked Sendable {
    private var session: URLSession?

    public init() {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 300
        c.timeoutIntervalForResource = 600
        session = URLSession(configuration: c)
    }

    public func urlSession() -> URLSession {
        session!
    }

    /// Idempotent: safe to call from stream termination and from `defer` after the load completes.
    public func invalidate() {
        session?.invalidateAndCancel()
        session = nil
    }
}
