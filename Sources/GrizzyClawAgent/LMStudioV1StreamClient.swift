import Foundation

/// LM Studio native v1 REST (`POST /api/v1/chat`), matching `grizzyclaw/llm/lmstudio_v1.py` SSE (`message.delta`, `reasoning.delta`, `chat.end`).
public struct LMStudioV1StreamParameters: Sendable {
    public let providerId: String
    public let chatURL: URL
    public let modelsURL: URL
    public let apiKey: String?
    public let model: String
    public let temperature: Double
    public let maxOutputTokens: Int?
    public let repeatPenalty: Double?
    public let systemPrompt: String

    public init(
        providerId: String,
        chatURL: URL,
        modelsURL: URL,
        apiKey: String?,
        model: String,
        temperature: Double,
        maxOutputTokens: Int?,
        repeatPenalty: Double?,
        systemPrompt: String
    ) {
        self.providerId = providerId
        self.chatURL = chatURL
        self.modelsURL = modelsURL
        self.apiKey = apiKey
        self.model = model
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
        self.repeatPenalty = repeatPenalty
        self.systemPrompt = systemPrompt
    }
}

public enum LMStudioV1StreamClient {
    public static func stream(
        parameters: LMStudioV1StreamParameters,
        conversation: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let box = LLMStreamSessionBox()
            let task = Task {
                await run(parameters: parameters, conversation: conversation, sessionBox: box, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                box.invalidate()
                task.cancel()
            }
        }
    }

    private static func run(
        parameters: LMStudioV1StreamParameters,
        conversation: [ChatMessage],
        sessionBox: LLMStreamSessionBox,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        defer { sessionBox.invalidate() }
        do {
            let (inputStr, systemStr) = messagesToV1InputAndSystem(
                systemPrompt: parameters.systemPrompt,
                conversation: conversation
            )
            guard !inputStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continuation.finish(throwing: URLError(.cannotParseResponse))
                return
            }

            var payload: [String: Any] = [
                "model": parameters.model,
                "input": inputStr,
                "stream": true,
                "temperature": parameters.temperature,
                "store": false,
            ]
            if !systemStr.isEmpty {
                payload["system_prompt"] = systemStr
            }
            if let m = parameters.maxOutputTokens {
                payload["max_output_tokens"] = m
            }
            if let rp = parameters.repeatPenalty {
                payload["repeat_penalty"] = rp
            }

            let body = try JSONSerialization.data(withJSONObject: payload, options: [])

            var req = URLRequest(url: parameters.chatURL)
            req.httpMethod = "POST"
            req.httpBody = body
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            if let k = parameters.apiKey, !k.isEmpty {
                req.setValue("Bearer \(k)", forHTTPHeaderField: "Authorization")
            }

            let (bytes, response) = try await sessionBox.urlSession().bytes(for: req)
            guard let http = response as? HTTPURLResponse else {
                continuation.finish(throwing: URLError(.badServerResponse))
                return
            }
            guard (200...299).contains(http.statusCode) else {
                let errText = try await readErrorBody(bytes: bytes)
                continuation.finish(throwing: LLMStreamHTTPError.httpStatus(http.statusCode, errText))
                return
            }

            try await parseLMStudioV1SSE(bytes: bytes, continuation: continuation)
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    /// Mirrors `_messages_to_v1_input_and_system` in Python.
    private static func messagesToV1InputAndSystem(
        systemPrompt: String,
        conversation: [ChatMessage]
    ) -> (input: String, system: String) {
        var systemParts: [String] = []
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            systemParts.append(systemPrompt)
        }
        var lastUser: String?
        for m in conversation {
            switch m.role {
            case .system:
                if !m.content.isEmpty { systemParts.append(m.content) }
            case .user, .tool:
                lastUser = m.content
            case .assistant:
                break
            }
        }
        let sys = systemParts.joined(separator: "\n\n")
        return (lastUser ?? "", sys)
    }

    private static func readErrorBody(bytes: URLSession.AsyncBytes) async throws -> String {
        var d = Data()
        for try await b in bytes {
            d.append(b)
            if d.count > 32_000 { break }
        }
        return String(data: d, encoding: .utf8) ?? ""
    }

    private static func parseLMStudioV1SSE(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var buffer = Data()
        let nl = Data("\n".utf8)
        var currentEvent: String?
        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            while let range = buffer.range(of: nl) {
                var lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(..<range.upperBound)
                if lineData.last == 0x0D {
                    lineData.removeLast()
                }
                guard let line = String(data: lineData, encoding: .utf8) else { continue }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("event:") {
                    currentEvent = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    continue
                }
                guard trimmed.hasPrefix("data:") else { continue }
                let rest = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if rest.isEmpty { continue }
                guard let data = rest.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    continue
                }
                let eventType = ((obj["type"] as? String) ?? currentEvent ?? "").trimmingCharacters(in: .whitespaces)
                if eventType == "error" {
                    let err = obj["error"] as? [String: Any]
                    let msg = (err?["message"] as? String) ?? "Unknown error"
                    throw LLMStreamHTTPError.httpStatus(400, msg)
                }
                if eventType == "reasoning.delta" {
                    continue
                }
                if isLmStudioV1DeltaEvent(eventType) {
                    if let text = extractLmStudioV1DeltaText(from: obj), !text.isEmpty {
                        continuation.yield(text)
                    }
                } else if eventType == "chat.end" || eventType.hasSuffix(".end") {
                    yieldLmStudioV1ChatEndContent(from: obj, continuation: continuation)
                } else if eventType.isEmpty, let text = extractLmStudioV1DeltaText(from: obj), !text.isEmpty {
                    // Some builds omit `type` on data lines; still stream text when present.
                    continuation.yield(text)
                }
            }
        }
    }

    private static func isLmStudioV1DeltaEvent(_ eventType: String) -> Bool {
        if eventType == "message.delta" { return true }
        if eventType.hasSuffix(".delta") { return true }
        if eventType.contains("delta") { return true }
        return false
    }

    private static func extractLmStudioV1DeltaText(from obj: [String: Any]) -> String? {
        if let s = obj["content"] as? String, !s.isEmpty { return s }
        if let s = obj["text"] as? String, !s.isEmpty { return s }
        if let d = obj["delta"] as? String, !d.isEmpty { return d }
        if let d = obj["delta"] as? [String: Any] {
            if let s = d["content"] as? String, !s.isEmpty { return s }
            if let s = d["text"] as? String, !s.isEmpty { return s }
        }
        if let msg = obj["message"] as? [String: Any],
           let s = msg["content"] as? String, !s.isEmpty {
            return s
        }
        return nil
    }

    private static func yieldLmStudioV1ChatEndContent(
        from obj: [String: Any],
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) {
        guard let result = obj["result"] as? [String: Any] else { return }
        if let output = result["output"] as? [[String: Any]] {
            for item in output {
                if let s = item["content"] as? String, !s.isEmpty {
                    continuation.yield(s)
                }
            }
        }
        if let msg = result["message"] as? [String: Any],
           let s = msg["content"] as? String, !s.isEmpty {
            continuation.yield(s)
        }
        if let s = result["text"] as? String, !s.isEmpty {
            continuation.yield(s)
        }
        if let s = result["output_text"] as? String, !s.isEmpty {
            continuation.yield(s)
        }
    }
}
