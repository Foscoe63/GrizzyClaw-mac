import Foundation
import GrizzyClawAgent
import GrizzyClawCore
import GrizzyClawMLX

/// Shared non-streaming LLM dispatcher used by headless surfaces (Telegram bot, scheduler, webhooks).
/// Resolves the current workspace + config + secrets once, runs the LLM stream to completion, and
/// returns the concatenated text. Mirrors the path the chat UI uses so all surfaces stay consistent.
public enum HeadlessLLMDispatcher {
    public struct Options {
        public var timeoutSeconds: Int
        public var historyLimit: Int
        public init(timeoutSeconds: Int = 300, historyLimit: Int = 40) {
            self.timeoutSeconds = timeoutSeconds
            self.historyLimit = historyLimit
        }
    }

    public enum DispatchError: LocalizedError {
        case secretsFailed(String)
        case noActiveWorkspace
        case resolveFailed(String)
        case llmFailed(String)
        case timedOut(Int)

        public var errorDescription: String? {
            switch self {
            case .secretsFailed(let m): return "Secrets load failed: \(m)"
            case .noActiveWorkspace:
                return "No active workspace. Open GrizzyClawMac → Workspaces and select one."
            case .resolveFailed(let m): return "LLM config error: \(m)"
            case .llmFailed(let m): return "LLM error: \(m)"
            case .timedOut(let s): return "LLM timed out after \(s)s."
            }
        }
    }

    /// Runs a single message (plus optional prior history) through the active workspace's LLM
    /// and returns the full assistant reply. Must be called on the MainActor because it reads
    /// the published stores.
    @MainActor
    public static func run(
        userMessage: String,
        history: [ChatMessage] = [],
        workspaceStore: WorkspaceStore,
        configStore: ConfigStore,
        guiChatPrefs: GuiChatPrefsStore,
        options: Options = Options()
    ) async throws -> String {
        let secrets = UserConfigLoader.loadSecretsWithKeychainLenient()

        let userSnap = configStore.snapshot
        let routing = configStore.routingExtras
        guard let idx = workspaceStore.index,
            let wid = idx.activeWorkspaceId,
            let ws = idx.workspaces.first(where: { $0.id == wid })
        else {
            throw DispatchError.noActiveWorkspace
        }

        let resolved: ResolvedLLMStreamRequest
        do {
            resolved = try ChatParameterResolver.resolve(
                user: userSnap,
                routing: routing,
                secrets: secrets,
                workspace: ws,
                guiLlmOverride: guiChatPrefs.resolverLlmOverride()
            )
        } catch {
            throw DispatchError.resolveFailed(error.localizedDescription)
        }

        var conversation = history
        conversation.append(ChatMessage(role: .user, content: userMessage))
        if conversation.count > options.historyLimit {
            conversation.removeFirst(conversation.count - options.historyLimit)
        }

        return try await runResolved(
            resolved: resolved,
            conversation: conversation,
            timeoutSeconds: options.timeoutSeconds
        )
    }

    /// Runs an already-resolved request off the main actor, with optional timeout.
    /// Extracted so the main-actor `run(...)` path can hand off values cleanly.
    nonisolated public static func runResolved(
        resolved: ResolvedLLMStreamRequest,
        conversation: [ChatMessage],
        timeoutSeconds: Int
    ) async throws -> String {
        if timeoutSeconds <= 0 {
            return try await completeOnce(resolved: resolved, conversation: conversation)
        }
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await completeOnce(resolved: resolved, conversation: conversation)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                throw DispatchError.timedOut(timeoutSeconds)
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    /// Runs a resolved stream to completion and returns the full concatenated text.
    nonisolated private static func completeOnce(
        resolved: ResolvedLLMStreamRequest,
        conversation: [ChatMessage]
    ) async throws -> String {
        let stream: AsyncThrowingStream<String, Error>
        switch resolved {
        case .openAICompatible(let p):
            stream = OpenAICompatibleStreamClient.stream(parameters: p, conversation: conversation)
        case .anthropic(let p):
            stream = AnthropicStreamClient.stream(parameters: p, conversation: conversation)
        case .lmStudioV1(let p):
            stream = LMStudioV1StreamClient.stream(parameters: p, conversation: conversation)
        case .mlx(let p):
            stream = MLXStreamClient.stream(parameters: p, conversation: conversation)
        }
        var buf = ""
        do {
            for try await delta in stream {
                buf += delta
            }
        } catch {
            throw DispatchError.llmFailed(error.localizedDescription)
        }
        let trimmed = buf.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(empty response)" : trimmed
    }
}
