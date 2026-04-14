import Foundation

/// Human-readable gateway/daemon errors for `Result` failure type (must conform to `Error`).
public struct GatewayClientFailure: Error, Sendable, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

/// One row in the gateway `sessions` list (`sessions_dialog.py`: `session_id`, `user_id`).
public struct GatewaySessionRow: Identifiable, Sendable, Equatable {
    public var id: String { sessionId }
    public let sessionId: String
    public let userId: String

    public init(sessionId: String, userId: String) {
        self.sessionId = sessionId
        self.userId = userId
    }

    /// Matches Python `QListWidgetItem(f"{sid} ({uid})")`.
    public var listLabel: String { "\(sessionId) (\(userId))" }
}

/// WebSocket client for the multi-session gateway (`GATEWAY_WS` in `sessions_dialog.py`: `ws://127.0.0.1:18789`).
public enum GatewaySessionsClient {
    nonisolated(unsafe) public static var gatewayWebSocketURL: URL = URL(string: "ws://127.0.0.1:18789")!

    /// List active sessions, or an error (daemon unreachable, timeout, etc.).
    public static func fetchSessions(url: URL = gatewayWebSocketURL) async -> Result<[GatewaySessionRow], GatewayClientFailure> {
        do {
            return try await withWebSocket(url: url) { task -> Result<[GatewaySessionRow], GatewayClientFailure> in
                try await sendJSON(task, ["type": "get_sessions"])
                for _ in 0 ..< 10 {
                    let data = try await recvJSON(task)
                    if data["type"] as? String == "error" {
                        return .failure(GatewayClientFailure(data["error"] as? String ?? "Gateway returned error"))
                    }
                    if data["type"] as? String == "sessions" {
                        let raw = data["sessions"] as? [[String: Any]] ?? []
                        let rows = raw.map { dict -> GatewaySessionRow in
                            let sid = dict["session_id"] as? String ?? "?"
                            let uid = dict["user_id"] as? String ?? "?"
                            return GatewaySessionRow(sessionId: sid, userId: uid)
                        }
                        return .success(rows)
                    }
                }
                return .failure(GatewayClientFailure("No sessions response from gateway"))
            }
        } catch {
            return .failure(GatewayClientFailure(friendlySocketError(error)))
        }
    }

    /// Gateway snapshot for `SubagentsDialog` parity (`subagents_state` in `grizzyclaw/gateway/server.py`).
    public struct SubagentsGatewayState: Sendable, Equatable {
        public let registryAvailable: Bool
        public let specialistAvailability: String
        public let activeLines: [String]
        public let completedLines: [String]
        public let activeRunIds: [String]
        public let debugLine: String

        public init(
            registryAvailable: Bool,
            specialistAvailability: String,
            activeLines: [String],
            completedLines: [String],
            activeRunIds: [String],
            debugLine: String
        ) {
            self.registryAvailable = registryAvailable
            self.specialistAvailability = specialistAvailability
            self.activeLines = activeLines
            self.completedLines = completedLines
            self.activeRunIds = activeRunIds
            self.debugLine = debugLine
        }
    }

    /// Sub-agent registry lists + debug (`get_subagents` / `subagents_state`).
    public static func fetchSubagentsState(url: URL = gatewayWebSocketURL) async -> Result<SubagentsGatewayState, GatewayClientFailure> {
        do {
            return try await withWebSocket(url: url) { task -> Result<SubagentsGatewayState, GatewayClientFailure> in
                try await sendJSON(task, ["type": "get_subagents"])
                for _ in 0 ..< 30 {
                    let data = try await recvJSON(task)
                    if data["type"] as? String == "error" {
                        return .failure(GatewayClientFailure(data["error"] as? String ?? "Gateway error"))
                    }
                    if data["type"] as? String == "subagents_state" {
                        let reg = data["registry_available"] as? Bool ?? false
                        let spec = data["specialist_availability"] as? String ?? "Specialist availability: —"
                        let active = data["active_lines"] as? [String] ?? []
                        let done = data["completed_lines"] as? [String] ?? []
                        let ids = data["active_run_ids"] as? [String] ?? []
                        let dbg = data["debug_line"] as? String ?? ""
                        let state = SubagentsGatewayState(
                            registryAvailable: reg,
                            specialistAvailability: spec,
                            activeLines: active,
                            completedLines: done,
                            activeRunIds: ids,
                            debugLine: dbg
                        )
                        return .success(state)
                    }
                }
                return .failure(GatewayClientFailure("No subagents_state response from gateway"))
            }
        } catch {
            return .failure(GatewayClientFailure(friendlySocketError(error)))
        }
    }

    /// Cancel a sub-agent run (`subagents_kill`); requires `gateway_auth_token` when the daemon enforces it.
    public static func killSubagentRun(
        runId: String,
        authToken: String? = nil,
        url: URL = gatewayWebSocketURL
    ) async -> Result<Void, GatewayClientFailure> {
        let trimmedId = runId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            return .failure(GatewayClientFailure("run_id required"))
        }
        do {
            return try await withWebSocket(url: url) { task -> Result<Void, GatewayClientFailure> in
                var payload: [String: Any] = [
                    "type": "subagents_kill",
                    "run_id": trimmedId,
                ]
                if let t = authToken?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                    payload["token"] = t
                }
                try await sendJSON(task, payload)
                for _ in 0 ..< 20 {
                    let data = try await recvJSON(task)
                    if data["type"] as? String == "error" {
                        return .failure(GatewayClientFailure(data["error"] as? String ?? "Gateway error"))
                    }
                    if data["type"] as? String == "subagents_kill_result" {
                        return .success(())
                    }
                }
                return .failure(GatewayClientFailure("No subagents_kill_result from gateway"))
            }
        } catch {
            return .failure(GatewayClientFailure(friendlySocketError(error)))
        }
    }

    /// Swarm activity lines (`swarm_activity_dialog.py` + gateway `swarm_history`), newest-last like the Python list.
    public static func fetchSwarmHistory(limit: Int = 50, url: URL = gatewayWebSocketURL) async -> Result<[String], GatewayClientFailure> {
        do {
            return try await withWebSocket(url: url) { task -> Result<[String], GatewayClientFailure> in
                try await sendJSON(task, ["type": "swarm_history", "limit": limit])
                for _ in 0 ..< 20 {
                    let data = try await recvJSON(task)
                    if data["type"] as? String == "error" {
                        return .failure(GatewayClientFailure(data["error"] as? String ?? "Gateway error"))
                    }
                    if data["type"] as? String == "swarm_history" {
                        let lines = data["lines"] as? [String] ?? []
                        return .success(lines)
                    }
                }
                return .failure(GatewayClientFailure("No swarm_history response from gateway"))
            }
        } catch {
            return .failure(GatewayClientFailure(friendlySocketError(error)))
        }
    }

    /// Formatted history text (role: content lines), or error.
    public static func fetchHistory(sessionId: String, url: URL = gatewayWebSocketURL) async -> Result<String, GatewayClientFailure> {
        do {
            return try await withWebSocket(url: url) { task -> Result<String, GatewayClientFailure> in
                try await sendJSON(task, ["type": "sessions_history", "session_id": sessionId])
                for _ in 0 ..< 5 {
                    let data = try await recvJSON(task)
                    if data["type"] as? String == "error" {
                        return .failure(GatewayClientFailure(data["error"] as? String ?? "Error"))
                    }
                    if data["type"] as? String == "session_history" {
                        let history = data["history"] as? [[String: Any]] ?? []
                        if history.isEmpty {
                            return .success("No history")
                        }
                        let lines: [String] = history.map { h in
                            let role = h["role"] as? String ?? "?"
                            let content = String((h["content"] as? String ?? "").prefix(500))
                            return "\(role): \(content)"
                        }
                        return .success(lines.joined(separator: "\n\n"))
                    }
                }
                return .failure(GatewayClientFailure("No response"))
            }
        } catch {
            return .failure(GatewayClientFailure("Error: Could not connect to daemon"))
        }
    }

    /// Send a user message into the selected session (`user_id` matches Python GUI default).
    /// When `authToken` is set, it is sent as `token` (Python gateway `gateway_auth_token` / `Settings.gateway_auth_token`).
    public static func sendMessage(
        sessionId: String,
        userId: String = "gui_user",
        message: String,
        authToken: String? = nil,
        url: URL = gatewayWebSocketURL
    ) async -> Result<Void, GatewayClientFailure> {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .success(()) }
        do {
            return try await withWebSocket(url: url) { task -> Result<Void, GatewayClientFailure> in
                var payload: [String: Any] = [
                    "type": "sessions_send",
                    "session_id": sessionId,
                    "user_id": userId,
                    "message": trimmed,
                ]
                if let t = authToken?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                    payload["token"] = t
                }
                try await sendJSON(task, payload)
                for _ in 0 ..< 30 {
                    let data = try await recvJSON(task)
                    if data["type"] as? String == "sessions_send_result" {
                        return .success(())
                    }
                    if data["type"] as? String == "error" {
                        return .failure(GatewayClientFailure(data["error"] as? String ?? "Gateway error"))
                    }
                }
                return .failure(GatewayClientFailure("No response"))
            }
        } catch {
            return .failure(GatewayClientFailure(friendlySocketError(error)))
        }
    }

    // MARK: - WebSocket helpers

    private static func withWebSocket<T>(
        url: URL,
        _ body: (URLSessionWebSocketTask) async throws -> T
    ) async throws -> T {
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }
        return try await body(task)
    }

    private static func sendJSON(_ task: URLSessionWebSocketTask, _ obj: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: obj)
        guard let s = String(data: data, encoding: .utf8) else {
            throw GatewaySessionsClientError.encodingFailed
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            task.send(.string(s)) { err in
                if let err {
                    cont.resume(throwing: err)
                } else {
                    cont.resume()
                }
            }
        }
    }

    private static func recvJSON(_ task: URLSessionWebSocketTask, timeout: TimeInterval = 5) async throws -> [String: Any] {
        let s = try await receiveString(task, timeout: timeout)
        guard let d = s.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: d) as? [String: Any]
        else {
            throw GatewaySessionsClientError.invalidMessage
        }
        return obj
    }

    private static func receiveString(_ task: URLSessionWebSocketTask, timeout: TimeInterval) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await receiveStringUnbounded(task)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw GatewaySessionsClientError.timeout
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    private static func receiveStringUnbounded(_ task: URLSessionWebSocketTask) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            task.receive { result in
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let s):
                        cont.resume(returning: s)
                    case .data(let d):
                        cont.resume(returning: String(data: d, encoding: .utf8) ?? "")
                    @unknown default:
                        cont.resume(throwing: GatewaySessionsClientError.invalidMessage)
                    }
                case .failure(let err):
                    cont.resume(throwing: err)
                }
            }
        }
    }

    private static func friendlySocketError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain, ns.code == 61 { // ECONNREFUSED
            return "Connection refused (is daemon running?)"
        }
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                return urlErr.localizedDescription
            default:
                break
            }
        }
        let msg = error.localizedDescription
        if msg.localizedCaseInsensitiveContains("refused") {
            return "Connection refused (is daemon running?)"
        }
        return msg
    }
}

private enum GatewaySessionsClientError: Error {
    case encodingFailed
    case invalidMessage
    case timeout
}
