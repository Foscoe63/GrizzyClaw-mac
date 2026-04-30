import Combine
import Foundation

/// Shared app state for the main window and auxiliary windows (e.g. Workspaces).
@MainActor
public final class GrizzyClawSession: ObservableObject {
    @Published public var selectedWorkspaceId: String?

    public let workspaceStore = WorkspaceStore()
    public let configStore = ConfigStore()

    private var cancellables = Set<AnyCancellable>()
    public let watcherStore = WatcherStore()
    public let chatSession = ChatSessionModel()
    public let statusBarStore = StatusBarStore()
    public let visualCanvas = VisualCanvasModel()
    /// When true, the Visual Canvas is shown in its dedicated window (`Window` id `visualCanvas`).
    @Published public var visualCanvasWindowOpen = false
    /// Model / Tools bar prefs (`~/.grizzyclaw/gui_chat_prefs.json`), same file as Python.
    public let guiChatPrefs = GuiChatPrefsStore()
    public let scheduledTasksStore = ScheduledTasksStore()
    /// Native Swift Telegram bot service (no Python daemon). Created lazily in `init` so it can
    /// share the same stores the chat UI uses (workspace + config + model picker preferences).
    public let telegramService: TelegramService
    /// Native scheduled-task executor (replaces Python `CronScheduler`). In-process, uses the
    /// same LLM path as the chat UI via `HeadlessLLMDispatcher`.
    public let scheduledTaskRunner: ScheduledTaskRunner

    public init() {
        self.telegramService = TelegramService(
            workspaceStore: workspaceStore,
            configStore: configStore,
            guiChatPrefs: guiChatPrefs
        )
        self.scheduledTaskRunner = ScheduledTaskRunner(
            scheduledTasksStore: scheduledTasksStore,
            workspaceStore: workspaceStore,
            configStore: configStore,
            guiChatPrefs: guiChatPrefs
        )
        // So `GrizzyClawRootScene` Window builders re-evaluate when Preferences saves `config.yaml`.
        configStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Keep status bar session stats in sync with chat session
        chatSession.$assistantCanvasObservationEpoch
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.statusBarStore.updateSessionStatus(
                    messages: self.chatSession.messages.count,
                    tokens: self.chatSession.approximateSessionTokens
                )
            }
            .store(in: &cancellables)
    }
}
