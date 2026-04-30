import Combine
import Foundation
import GrizzyClawAgent
import GrizzyClawCore
import GrizzyClawMLX

/// Headless Telegram bot service that runs entirely in-process (no Python daemon).
/// Uses `getUpdates` long-polling and dispatches each incoming text message through
/// the same `ChatParameterResolver` + stream clients used by the main chat UI.
@MainActor
public final class TelegramService: ObservableObject {
    public enum Status: Equatable {
        case stopped
        case starting
        case running(botName: String)
        case stopping
        case error(String)

        public var displayText: String {
            switch self {
            case .stopped: return "Stopped"
            case .starting: return "Starting…"
            case .running(let name): return "Running as @\(name)"
            case .stopping: return "Stopping…"
            case .error(let m): return "Error: \(m)"
            }
        }

        public var isActive: Bool {
            switch self {
            case .running, .starting: return true
            default: return false
            }
        }
    }

    @Published public private(set) var status: Status = .stopped
    @Published public private(set) var lastActivity: String = ""

    private let workspaceStore: WorkspaceStore
    private let configStore: ConfigStore
    private let guiChatPrefs: GuiChatPrefsStore

    /// Per-chat rolling history so multi-turn conversations have context.
    private var histories: [Int64: [ChatMessage]] = [:]
    private let historyLimit = 40

    private var pollTask: Task<Void, Never>?

    public init(
        workspaceStore: WorkspaceStore,
        configStore: ConfigStore,
        guiChatPrefs: GuiChatPrefsStore
    ) {
        self.workspaceStore = workspaceStore
        self.configStore = configStore
        self.guiChatPrefs = guiChatPrefs
    }

    deinit {
        pollTask?.cancel()
    }

    public func selectedWorkspaceId() -> String? {
        workspaceStore.index?.activeWorkspaceId
    }

    public func start() {
        guard !status.isActive else {
            GrizzyClawLog.info("Telegram: start() ignored — already \(status.displayText)")
            return
        }
        GrizzyClawLog.info("Telegram: start() called — entering runLoop")
        status = .starting
        lastActivity = ""
        let ws = workspaceStore
        let cs = configStore
        let prefs = guiChatPrefs
        pollTask = Task { [weak self] in
            await self?.runLoop(workspaceStore: ws, configStore: cs, guiChatPrefs: prefs)
        }
    }

    public func stop() {
        guard status.isActive else { return }
        GrizzyClawLog.info("Telegram: stop() called")
        status = .stopping
        pollTask?.cancel()
        pollTask = nil
        status = .stopped
    }

    public func clearHistory() {
        histories.removeAll()
    }

    // MARK: - Loop

    private func runLoop(
        workspaceStore: WorkspaceStore,
        configStore: ConfigStore,
        guiChatPrefs: GuiChatPrefsStore
    ) async {
        let tgConfig: TelegramConfig
        do {
            tgConfig = try UserConfigLoader.loadTelegramConfig()
        } catch {
            GrizzyClawLog.error("Telegram: loadTelegramConfig failed: \(error.localizedDescription)")
            await setStatus(.error("Config load failed: \(error.localizedDescription)"))
            return
        }
        guard let token = tgConfig.botToken, !token.isEmpty else {
            GrizzyClawLog.error("Telegram: telegram_bot_token is empty in \(GrizzyClawPaths.configYAML.path)")
            await setStatus(.error("telegram_bot_token is empty"))
            return
        }
        let tokenHint = String(token.prefix(6)) + "…(\(token.count) chars)"
        GrizzyClawLog.info("Telegram: loaded token \(tokenHint)")

        let session = Self.makeSession()

        let botName: String
        do {
            botName = try await TelegramBotAPI.getMe(token: token, session: session)
            GrizzyClawLog.info("Telegram: getMe ok — @\(botName)")
        } catch {
            GrizzyClawLog.error("Telegram: getMe failed: \(error.localizedDescription)")
            await setStatus(.error("getMe failed: \(error.localizedDescription)"))
            return
        }

        // Telegram blocks getUpdates when a webhook is set; clear it so polling works reliably.
        do {
            try await TelegramBotAPI.deleteWebhook(token: token, session: session)
            GrizzyClawLog.info("Telegram: deleteWebhook ok")
        } catch {
            GrizzyClawLog.info("Telegram: deleteWebhook non-fatal: \(error.localizedDescription)")
        }

        await setStatus(.running(botName: botName))
        GrizzyClawLog.info("Telegram: entering long-poll loop (timeout=25s)")

        var offset: Int64? = nil
        var pollIteration = 0
        while !Task.isCancelled {
            pollIteration += 1
            do {
                let (messages, nextOffset) = try await TelegramBotAPI.getUpdates(
                    token: token,
                    offset: offset,
                    timeoutSeconds: 25,
                    session: session
                )
                if !messages.isEmpty || offset != nextOffset {
                    GrizzyClawLog.debug(
                        "Telegram: poll#\(pollIteration) offset=\(offset.map(String.init) ?? "nil") → next=\(nextOffset) messages=\(messages.count)"
                    )
                }
                offset = nextOffset
                for msg in messages where !Task.isCancelled {
                    await handleMessage(
                        msg,
                        token: token,
                        session: session,
                        workspaceStore: workspaceStore,
                        configStore: configStore,
                        guiChatPrefs: guiChatPrefs
                    )
                }
            } catch is CancellationError {
                break
            } catch {
                GrizzyClawLog.error("Telegram poll error (iter=\(pollIteration)): \(error.localizedDescription)")
                await setActivity("poll error — retrying in 3s")
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }

        GrizzyClawLog.info("Telegram: runLoop exiting (cancelled=\(Task.isCancelled))")
        await setStatus(.stopped)
    }

    // MARK: - Message handling

    private func handleMessage(
        _ msg: TelegramBotAPI.Message,
        token: String,
        session: URLSession,
        workspaceStore: WorkspaceStore,
        configStore: ConfigStore,
        guiChatPrefs: GuiChatPrefsStore
    ) async {
        let who = msg.from ?? "chat\(msg.chatId)"
        GrizzyClawLog.info(
            "Telegram: handleMessage chat=\(msg.chatId) from=@\(who) updateId=\(msg.updateId) len=\(msg.text.count)"
        )
        await setActivity("← @\(who): \(truncate(msg.text, 80))")

        // Simple slash-command: /reset clears per-chat history.
        if msg.text.trimmingCharacters(in: .whitespaces).lowercased() == "/reset" {
            histories[msg.chatId] = []
            try? await TelegramBotAPI.sendMessage(
                token: token,
                chatId: msg.chatId,
                text: "Conversation reset.",
                replyToMessageId: msg.messageId,
                session: session
            )
            GrizzyClawLog.info("Telegram: chat=\(msg.chatId) history reset via /reset")
            return
        }

        let priorHistory = histories[msg.chatId] ?? []
        GrizzyClawLog.debug("Telegram: dispatching to LLM (history=\(priorHistory.count) msgs)")
        let reply: String
        do {
            reply = try await HeadlessLLMDispatcher.run(
                userMessage: msg.text,
                history: priorHistory,
                workspaceStore: workspaceStore,
                configStore: configStore,
                guiChatPrefs: guiChatPrefs,
                options: HeadlessLLMDispatcher.Options(
                    timeoutSeconds: 0,
                    historyLimit: historyLimit
                )
            )
            GrizzyClawLog.info("Telegram: LLM reply ready (len=\(reply.count)) for chat=\(msg.chatId)")
        } catch {
            GrizzyClawLog.error(
                "Telegram: HeadlessLLMDispatcher.run threw for chat=\(msg.chatId): \(error.localizedDescription)"
            )
            await replyError(
                token: token,
                chatId: msg.chatId,
                messageId: msg.messageId,
                session: session,
                text: error.localizedDescription
            )
            return
        }

        var history = priorHistory
        history.append(ChatMessage(role: .user, content: msg.text))
        history.append(ChatMessage(role: .assistant, content: reply))
        trimHistory(&history)
        histories[msg.chatId] = history

        do {
            try await TelegramBotAPI.sendMessage(
                token: token,
                chatId: msg.chatId,
                text: reply,
                replyToMessageId: msg.messageId,
                session: session
            )
            await setActivity("→ @\(who): \(truncate(reply, 80))")
        } catch {
            GrizzyClawLog.error("Telegram sendMessage failed: \(error.localizedDescription)")
            await setActivity("send failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func setStatus(_ s: Status) async {
        status = s
    }

    private func setActivity(_ s: String) async {
        lastActivity = s
    }

    private func trimHistory(_ history: inout [ChatMessage]) {
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }

    private func replyError(
        token: String,
        chatId: Int64,
        messageId: Int64?,
        session: URLSession,
        text: String
    ) async {
        GrizzyClawLog.error("Telegram: \(text)")
        try? await TelegramBotAPI.sendMessage(
            token: token,
            chatId: chatId,
            text: "⚠️ " + text,
            replyToMessageId: messageId,
            session: session
        )
    }

    private static func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 120
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }

    private func truncate(_ s: String, _ n: Int) -> String {
        if s.count <= n { return s }
        return String(s.prefix(n)) + "…"
    }
}
