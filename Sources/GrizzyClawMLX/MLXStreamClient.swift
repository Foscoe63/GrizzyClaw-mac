import Foundation
import Hub
import MLXLMCommon
import MLXLLM
import GrizzyClawAgent
import GrizzyClawCore

/// Streams text from a local MLX model (Hugging Face id) using mlx-swift-lm. Apple silicon only at resolve time; this type assumes the caller selected the `mlx` provider.
public enum MLXStreamClient {
    public static func stream(
        parameters: MLXStreamParameters,
        conversation: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await run(parameters: parameters, conversation: conversation, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private static func run(
        parameters: MLXStreamParameters,
        conversation: [ChatMessage],
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        do {
            let hub = HubApi(downloadBase: parameters.downloadBaseDirectory)
            let container = try await MLXModelCache.shared.container(
                hub: hub,
                modelId: parameters.modelId,
                revision: parameters.revision,
                progressHandler: { _ in }
            )

            // Tokenizer chat templates (Jinja) usually only define user/assistant/system — not `tool`, which throws TemplateException.
            let folded = Self.mergeToolMessagesIntoFollowingUser(conversation)
            let mlxMessages = folded.map { Self.toMLXMessage($0) }
            guard let last = mlxMessages.last else {
                continuation.finish(throwing: MLXStreamError.emptyConversation)
                return
            }

            let history = Array(mlxMessages.dropLast())
            // Tool/JSON/Markdown bodies may contain `{{` or `{%`; Jinja treats those as syntax unless broken up.
            let instructions = Self.sanitizeForHFChatTemplate(parameters.systemPrompt)
            let session = ChatSession(
                container,
                instructions: instructions,
                history: history,
                generateParameters: GenerateParameters(
                    maxTokens: parameters.maxOutputTokens,
                    temperature: Float(parameters.temperature)
                )
            )

            let stream = session.streamResponse(
                to: last.content,
                role: last.role,
                images: [],
                videos: []
            )

            for try await piece in stream {
                if Task.isCancelled { break }
                if case .terminated = continuation.yield(piece) { break }
            }
            continuation.finish()
        } catch {
            if Task.isCancelled || error is CancellationError {
                continuation.finish()
            } else {
                continuation.finish(throwing: error)
            }
        }
    }

    /// HF chat templates are Jinja. Message bodies (especially MCP tool results) may contain `{{` / `{%`, which the template engine can parse as directives and throw ``TemplateException``.
    private static func sanitizeForHFChatTemplate(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: "{{", with: "{ {")
        s = s.replacingOccurrences(of: "{%", with: "{ %")
        return s
    }

    /// Fold MCP tool transcripts into the next user message so Jinja chat templates never see `role: tool` (avoids ``TemplateException``).
    private static func mergeToolMessagesIntoFollowingUser(_ messages: [ChatMessage]) -> [ChatMessage] {
        guard !messages.isEmpty else { return messages }
        var out: [ChatMessage] = []
        var i = messages.startIndex
        while i < messages.endIndex {
            let m = messages[i]
            if m.role != .tool {
                out.append(m)
                i = messages.index(after: i)
                continue
            }
            var combined = ""
            while i < messages.endIndex, messages[i].role == .tool {
                if !combined.isEmpty { combined += "\n\n" }
                combined += messages[i].content
                i = messages.index(after: i)
            }
            guard i < messages.endIndex, messages[i].role == .user else {
                out.append(ChatMessage(role: .user, content: "[Tool output]\n" + combined))
                continue
            }
            let u = messages[i]
            out.append(ChatMessage(role: .user, content: combined + "\n\n" + u.content))
            i = messages.index(after: i)
        }
        return out
    }

    private static func toMLXMessage(_ m: ChatMessage) -> Chat.Message {
        switch m.role {
        case .user:
            return Chat.Message(role: .user, content: sanitizeForHFChatTemplate(m.content))
        case .assistant:
            return Chat.Message(role: .assistant, content: sanitizeForHFChatTemplate(m.content))
        case .system:
            return Chat.Message(role: .system, content: sanitizeForHFChatTemplate(m.content))
        case .tool:
            // Should not reach here after ``mergeToolMessagesIntoFollowingUser``; map defensively for Jinja.
            return Chat.Message(role: .user, content: sanitizeForHFChatTemplate("[Tool output]\n" + m.content))
        }
    }
}

private enum MLXStreamError: LocalizedError {
    case emptyConversation

    var errorDescription: String? {
        switch self {
        case .emptyConversation:
            return "MLX: empty conversation."
        }
    }
}
