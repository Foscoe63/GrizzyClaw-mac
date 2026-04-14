import GrizzyClawCore
import SwiftUI

/// Parity with Python `ConversationHistoryDialog` (`grizzyclaw/gui/conversation_history_dialog.py`):
/// session summary, hint, **Clear (new chat)** and **Load from disk**, with informational alerts.
public struct ConversationHistoryMainView: View {
    @ObservedObject public var chatSession: ChatSessionModel
    @ObservedObject public var configStore: ConfigStore
    @Binding public var selectedWorkspaceId: String?

    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    public init(
        chatSession: ChatSessionModel,
        configStore: ConfigStore,
        selectedWorkspaceId: Binding<String?>
    ) {
        self.chatSession = chatSession
        self.configStore = configStore
        self._selectedWorkspaceId = selectedWorkspaceId
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(chatSession.sessionSummaryLine)
                .font(.system(size: 14))
                .foregroundStyle(Color(nsColor: .labelColor))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Clear starts a new conversation. Load restores the last saved session from disk.")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("Clear (new chat)") {
                    clearNewChat()
                }

                Button("Load from disk") {
                    loadFromDisk()
                }

                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .frame(minWidth: 360, maxWidth: 480, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func clearNewChat() {
        chatSession.newChatArchivingPrevious(
            selectedWorkspaceId: selectedWorkspaceId,
            config: configStore.snapshot
        )
        alertTitle = "Cleared"
        alertMessage = "Conversation cleared. You can start a new chat."
        showAlert = true
    }

    private func loadFromDisk() {
        let loaded = chatSession.reloadSessionFromDiskReturningCount(
            selectedWorkspaceId: selectedWorkspaceId,
            config: configStore.snapshot
        )
        if loaded > 0 {
            alertTitle = "Loaded"
            alertMessage = "Restored \(loaded) message(s) from disk."
        } else {
            alertTitle = "No saved session"
            alertMessage =
                "No saved session was found for this workspace/user yet.\n"
                + "Sessions are auto-saved after each assistant reply."
        }
        showAlert = true
    }
}
