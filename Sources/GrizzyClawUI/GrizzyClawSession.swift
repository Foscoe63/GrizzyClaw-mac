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

    public init() {
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
