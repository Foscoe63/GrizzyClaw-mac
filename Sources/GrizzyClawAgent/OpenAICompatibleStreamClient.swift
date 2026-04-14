import Foundation

/// Streams SSE from an OpenAI-compatible `POST .../chat/completions` endpoint (matches `grizzyclaw/llm/openai.py` delta extraction).
public enum OpenAICompatibleStreamClient {
    public static func stream(
        parameters: ResolvedChatParameters,
        conversation: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let box = LLMStreamSessionBox()
            let task = Task {
                await run(
                    parameters: parameters,
                    conversation: conversation,
                    sessionBox: box,
                    continuation: continuation
                )
            }
            continuation.onTermination = { @Sendable _ in
                box.invalidate()
                task.cancel()
            }
        }
    }

    private static func run(
        parameters: ResolvedChatParameters,
        conversation: [ChatMessage],
        sessionBox: LLMStreamSessionBox,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        defer { sessionBox.invalidate() }
        do {
            var apiMessages: [[String: String]] = [
                ["role": "system", "content": parameters.systemPrompt],
            ]
            for m in conversation where m.role != .system {
                // APIs expect tool-round results as a normal user message.
                let apiRole = m.role == .tool ? "user" : m.role.rawValue
                apiMessages.append(["role": apiRole, "content": m.content])
            }

            var payload: [String: Any] = [
                "model": parameters.model,
                "messages": apiMessages,
                "temperature": parameters.temperature,
                "stream": true,
            ]
            if let m = parameters.maxTokens {
                payload["max_tokens"] = m
            }
            if let fp = parameters.frequencyPenalty {
                payload["frequency_penalty"] = fp
            }

            let body = try JSONSerialization.data(withJSONObject: payload, options: [])

            var req = URLRequest(url: parameters.chatCompletionsURL)
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

            try await parseSSE(bytes: bytes, continuation: continuation)
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private static func readErrorBody(bytes: URLSession.AsyncBytes) async throws -> String {
        var d = Data()
        for try await b in bytes {
            d.append(b)
            if d.count > 32_000 { break }
        }
        return String(data: d, encoding: .utf8) ?? ""
    }

    private static func parseSSE(
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
                let rest: String
                if trimmed.hasPrefix("data: ") {
                    rest = String(trimmed.dropFirst(6))
                } else if trimmed.hasPrefix("data:") {
                    rest = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                } else {
                    continue
                }
                if rest == "[DONE]" {
                    return
                }
                guard let data = rest.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let piece = extractStreamText(from: obj),
                      !piece.isEmpty
                else {
                    continue
                }
                continuation.yield(piece)
            }
        }
    }

    /// Aggregates assistant text from OpenAI-style streaming chunks (LM Studio, OpenAI, proxies).
    private static func extractStreamText(from data: [String: Any]) -> String? {
        guard let choices = data["choices"] as? [[String: Any]], let first = choices.first else { return nil }

        if let msg = first["message"] as? [String: Any] {
            if let s = stringFromContentValue(msg["content"]), !s.isEmpty { return s }
        }

        if let delta = first["delta"] as? [String: Any] {
            var parts: [String] = []
            if let s = stringFromContentValue(delta["content"]), !s.isEmpty { parts.append(s) }
            if let s = delta["refusal"] as? String, !s.isEmpty { parts.append(s) }
            if let s = delta["text"] as? String, !s.isEmpty { parts.append(s) }
            if !parts.isEmpty { return parts.joined() }
        }

        if let text = first["text"] as? String, !text.isEmpty {
            return text
        }
        return nil
    }

    /// `content` may be a string or a list of structured parts (multimodal / newer APIs).
    private static func stringFromContentValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let s = value as? String { return s.isEmpty ? nil : s }
        guard let arr = value as? [[String: Any]] else { return nil }
        var acc = ""
        for item in arr {
            if let t = item["text"] as? String { acc += t }
            else if let t = item["content"] as? String { acc += t }
        }
        return acc.isEmpty ? nil : acc
    }
}
