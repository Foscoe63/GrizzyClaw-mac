import Foundation

/// Streams SSE from Anthropic Messages API (`POST /v1/messages`, `stream: true`), aligned with `grizzyclaw/llm/anthropic.py` text output.
public struct AnthropicStreamParameters: Sendable {
    public let providerId: String
    public let messagesURL: URL
    public let apiKey: String
    public let model: String
    public let temperature: Double
    public let maxTokens: Int
    public let systemPrompt: String

    public init(
        providerId: String,
        messagesURL: URL,
        apiKey: String,
        model: String,
        temperature: Double,
        maxTokens: Int,
        systemPrompt: String
    ) {
        self.providerId = providerId
        self.messagesURL = messagesURL
        self.apiKey = apiKey
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.systemPrompt = systemPrompt
    }
}

public enum AnthropicStreamClient {
    public static func stream(
        parameters: AnthropicStreamParameters,
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
        parameters: AnthropicStreamParameters,
        conversation: [ChatMessage],
        sessionBox: LLMStreamSessionBox,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        defer { sessionBox.invalidate() }
        do {
            let (systemStr, anthropicMessages) = buildAnthropicPayload(
                systemPrompt: parameters.systemPrompt,
                conversation: conversation
            )
            guard !anthropicMessages.isEmpty else {
                continuation.finish(throwing: URLError(.cannotParseResponse))
                return
            }

            var payload: [String: Any] = [
                "model": parameters.model,
                "max_tokens": parameters.maxTokens,
                "messages": anthropicMessages,
                "temperature": parameters.temperature,
                "stream": true,
            ]
            if let s = systemStr, !s.isEmpty {
                payload["system"] = s
            }

            let body = try JSONSerialization.data(withJSONObject: payload, options: [])

            var req = URLRequest(url: parameters.messagesURL)
            req.httpMethod = "POST"
            req.httpBody = body
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.setValue(parameters.apiKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

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

            try await parseAnthropicSSE(bytes: bytes, continuation: continuation)
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    /// Mirrors `_convert_messages` in Python: merged system string + user/assistant only.
    private static func buildAnthropicPayload(
        systemPrompt: String,
        conversation: [ChatMessage]
    ) -> (system: String?, messages: [[String: Any]]) {
        var systemParts: [String] = []
        if !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            systemParts.append(systemPrompt)
        }
        var out: [[String: Any]] = []
        for m in conversation {
            switch m.role {
            case .system:
                if !m.content.isEmpty {
                    systemParts.append(m.content)
                }
            case .user, .tool:
                out.append(["role": "user", "content": m.content])
            case .assistant:
                out.append(["role": "assistant", "content": m.content])
            }
        }
        let sys = systemParts.isEmpty ? nil : systemParts.joined(separator: "\n\n")
        return (sys, out)
    }

    private static func readErrorBody(bytes: URLSession.AsyncBytes) async throws -> String {
        var d = Data()
        for try await b in bytes {
            d.append(b)
            if d.count > 32_000 { break }
        }
        return String(data: d, encoding: .utf8) ?? ""
    }

    private static func parseAnthropicSSE(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var buffer = Data()
        let nl = Data("\n".utf8)
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
                guard trimmed.hasPrefix("data: ") else { continue }
                let rest = String(trimmed.dropFirst(6))
                if rest == "[DONE]" { return }
                guard let data = rest.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    continue
                }
                if let err = obj["error"] as? [String: Any],
                   let msg = err["message"] as? String {
                    throw LLMStreamHTTPError.httpStatus(400, msg)
                }
                guard let type = obj["type"] as? String else { continue }
                if type == "content_block_delta" {
                    if let delta = obj["delta"] as? [String: Any],
                       let dType = delta["type"] as? String,
                       dType == "text_delta",
                       let text = delta["text"] as? String,
                       !text.isEmpty {
                        continuation.yield(text)
                    }
                }
            }
        }
    }
}
