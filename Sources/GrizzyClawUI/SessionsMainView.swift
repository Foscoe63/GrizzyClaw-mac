import GrizzyClawCore
import SwiftUI

/// Parity with Python `SessionsDialog` (`grizzyclaw/gui/sessions_dialog.py`): theme colors from `_get_dialog_theme_colors`, gateway `ws://127.0.0.1:18789`, `gateway_auth_token` on send when set in `config.yaml`.
public struct SessionsMainView: View {
    @ObservedObject public var configStore: ConfigStore

    @Environment(\.colorScheme) private var colorScheme

    @State private var sessions: [GatewaySessionRow] = []
    @State private var selectedSessionId: String?
    @State private var listNotice: String?
    @State private var historyText = ""
    @State private var messageDraft = ""
    @State private var busy = false

    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    /// Matches `_get_dialog_theme_colors(parent)` in `sessions_dialog.py`.
    private var dialogPalette: (bg: Color, fg: Color, accent: Color, border: Color, inputBg: Color) {
        let theme = configStore.snapshot.theme
        let isDark = AppearanceTheme.isEffectivelyDark(theme: theme, colorScheme: colorScheme)
        if isDark {
            return (
                Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255),
                Color.white,
                Color(red: 10 / 255, green: 132 / 255, blue: 1),
                Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255),
                Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255)
            )
        }
        return (
            Color.white,
            Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255),
            Color(red: 0, green: 122 / 255, blue: 1),
            Color(red: 229 / 255, green: 229 / 255, blue: 234 / 255),
            Color.white
        )
    }

    public init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    public var body: some View {
        let c = dialogPalette
        VStack(alignment: .leading, spacing: 15) {
            Text("Multi-Agent Sessions")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(c.fg)

            Text(
                "List sessions, view history, and send messages. Requires daemon running (Gateway on ws://127.0.0.1:18789)."
            )
            .font(.system(size: 12))
            .foregroundStyle(c.fg.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)

            HSplitView {
                sessionListColumn(c: c)
                    .frame(minWidth: 250, idealWidth: 250)
                historyColumn(c: c)
                    .frame(minWidth: 450, idealWidth: 450)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(c.bg)
        .onAppear {
            refreshSessions()
        }
        .onChange(of: selectedSessionId) {
            loadHistoryForSelection()
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    @ViewBuilder
    private func sessionListColumn(c: (bg: Color, fg: Color, accent: Color, border: Color, inputBg: Color)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sessions")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(c.fg)
            if let note = listNotice {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(c.fg.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            List(sessions, id: \.sessionId, selection: $selectedSessionId) { row in
                Text(row.listLabel)
                    .tag(row.sessionId)
            }
            .scrollContentBackground(.hidden)
            .disabled(busy)
            Button("Refresh") {
                refreshSessions()
            }
            .disabled(busy)
        }
    }

    @ViewBuilder
    private func historyColumn(c: (bg: Color, fg: Color, accent: Color, border: Color, inputBg: Color)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(c.fg)
            ZStack(alignment: .topLeading) {
                ScrollView {
                    Text(historyText)
                        .font(.system(size: 13))
                        .foregroundStyle(c.fg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                if historyText.isEmpty {
                    Text("Select a session to view history")
                        .font(.system(size: 13))
                        .foregroundStyle(c.fg.opacity(0.45))
                        .padding(6)
                }
            }
            .frame(minHeight: 200)
            .padding(8)
            .background(c.inputBg)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(c.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(alignment: .bottom, spacing: 8) {
                TextEditor(text: $messageDraft)
                    .font(.system(size: 13))
                    .frame(height: 80)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(c.inputBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(c.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .topLeading) {
                        if messageDraft.isEmpty {
                            Text("Message to send to selected session...")
                                .font(.system(size: 13))
                                .foregroundStyle(c.fg.opacity(0.45))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                    }
                    .disabled(busy)
                Button("Send") {
                    sendMessage()
                }
                .tint(c.accent)
                .disabled(busy || selectedSessionId == nil)
            }
        }
    }

    private func refreshSessions() {
        busy = true
        listNotice = nil
        Task {
            let result = await GatewaySessionsClient.fetchSessions()
            await MainActor.run {
                busy = false
                switch result {
                case .success(let rows):
                    sessions = rows
                case .failure(let err):
                    sessions = []
                    listNotice = "(Daemon not reachable: \(err.message))"
                }
            }
        }
    }

    private func loadHistoryForSelection() {
        guard let sid = selectedSessionId else {
            historyText = ""
            return
        }
        busy = true
        historyText = ""
        Task {
            let result = await GatewaySessionsClient.fetchHistory(sessionId: sid)
            await MainActor.run {
                busy = false
                switch result {
                case .success(let text):
                    historyText = text
                case .failure(let err):
                    historyText = err.message
                }
            }
        }
    }

    private func sendMessage() {
        guard let sid = selectedSessionId else {
            alertTitle = "No Session"
            alertMessage = "Select a session first."
            showAlert = true
            return
        }
        let msg = messageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { return }
        busy = true
        Task {
            let token = configStore.snapshot.gatewayAuthToken
            let result = await GatewaySessionsClient.sendMessage(
                sessionId: sid,
                message: msg,
                authToken: token
            )
            await MainActor.run {
                busy = false
                switch result {
                case .success:
                    messageDraft = ""
                    loadHistoryForSelection()
                case .failure(let err):
                    alertTitle = "Error"
                    alertMessage = err.message
                    showAlert = true
                }
            }
        }
    }
}
