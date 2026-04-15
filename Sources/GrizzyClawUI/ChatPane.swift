import AppKit
import Foundation
import GrizzyClawAgent
import GrizzyClawCore
import SwiftUI

private enum ChatSubTab: Int {
    case chat
    case multiAgent
}

private enum ChatScrollAnchor {
    /// `ScrollViewReader` target at the end of the transcript.
    static let bottom = "chat_transcript_bottom"
}

/// Main chat UI: OpenAI-compatible SSE streaming via `ChatSessionModel`.
/// Layout aligned with Python `ChatWidget` (tabs, header, separators, rounded composer, canvas toggle).
public struct ChatPane: View {
    @ObservedObject var session: ChatSessionModel
    @ObservedObject var workspaceStore: WorkspaceStore
    @ObservedObject var configStore: ConfigStore
    @ObservedObject var guiChatPrefs: GuiChatPrefsStore
    @ObservedObject var canvasModel: VisualCanvasModel
    @ObservedObject var statusBarStore: StatusBarStore
    @Binding var canvasPanelVisible: Bool
    var selectedWorkspaceId: String?

    @State private var draft: String = ""
    @State private var showSlashPalette = false
    @State private var slashPaletteRows: [(cmd: String, label: String)] = []
    @State private var showMentionPalette = false
    @State private var mentionPaletteRows: [WorkspaceRecord] = []
    @State private var mentionReplaceRange: NSRange?
    @State private var subTab: ChatSubTab = .chat
    @State private var streamingScreenshotEmitted = false
    @State private var streamingA2UIEmitted = false
    @State private var streamingPixmapEmitted = false
    @State private var lastAssistantMessageId: UUID?

    @Environment(\.colorScheme) private var colorScheme

    private var snap: UserConfigSnapshot { configStore.snapshot }

    public init(
        session: ChatSessionModel,
        workspaceStore: WorkspaceStore,
        configStore: ConfigStore,
        guiChatPrefs: GuiChatPrefsStore,
        canvasModel: VisualCanvasModel,
        statusBarStore: StatusBarStore,
        canvasPanelVisible: Binding<Bool>,
        selectedWorkspaceId: String?
    ) {
        self.session = session
        self.workspaceStore = workspaceStore
        self.configStore = configStore
        self.guiChatPrefs = guiChatPrefs
        self.canvasModel = canvasModel
        self.statusBarStore = statusBarStore
        self._canvasPanelVisible = canvasPanelVisible
        self.selectedWorkspaceId = selectedWorkspaceId
    }

    public var body: some View {
        VStack(spacing: 0) {
            if workspaceStore.isReloading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            if let err = session.statusLine, !err.isEmpty {
                GrizzyClawStatusBanner(text: err)
            }
            if let info = session.infoLine, !info.isEmpty {
                GrizzyClawInfoBanner(text: info)
            }
            if !workspaceReady {
                GrizzyClawInfoBanner(
                    text: "Choose a workspace in the left sidebar (Workspaces in the menu, or a workspace chip below). Send stays off until a workspace is selected and loaded."
                )
            }

            headerRow
                .padding(.horizontal, comfortableMargins ? 40 : 30)
                .padding(.top, comfortableMargins ? 28 : 20)
                .padding(.bottom, 0)

            Rectangle()
                .fill(separatorColor)
                .frame(height: 1)
                .padding(.top, 16)

            Group {
                if subTab == .chat {
                    chatScroll
                } else {
                    multiAgentPlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(separatorColor)
                .frame(height: 1)
                .padding(.vertical, 16)

            ChatComposerToolbar(
                guiPrefs: guiChatPrefs,
                configStore: configStore,
                workspaceStore: workspaceStore,
                selectedWorkspaceId: selectedWorkspaceId
            )
            .padding(.horizontal, comfortableMargins ? 40 : 30)
            .padding(.bottom, 8)

            inputArea
                .padding(.horizontal, comfortableMargins ? 40 : 30)
                .padding(.bottom, 12)

            Text(
                "Visual Canvas shows screenshots, A2UI blocks, and inline images from replies. "
                    + "MCP tools use the same JSON and Python helpers as the desktop app (TOOL_CALL loop); skills, shell approval, and browser automation beyond that still use the Python agent."
            )
            .font(AppearanceTheme.swiftUIFont(snap, delta: -3))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, comfortableMargins ? 40 : 30)
            .padding(.bottom, 10)
        }
        .background(AppearanceTheme.chatBackground(theme: snap.theme))
        .onChange(of: session.assistantCanvasObservationEpoch) {
            applyCanvasSyncAfterAssistantObservation()
        }
        .onChange(of: session.isStreaming) {
            if !session.isStreaming {
                syncCanvasFromAssistantStream(forceFinal: true)
            }
        }
    }

    /// Wider margins when not in compact mode (Python `layout_comfortable` vs compact).
    private var comfortableMargins: Bool {
        !configStore.snapshot.compactMode
    }

    private var separatorColor: Color {
        colorScheme == .dark ? Color(red: 0.22, green: 0.22, blue: 0.24) : Color(red: 0.90, green: 0.90, blue: 0.92)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 0) {
            tabPill(title: "Chat", selected: subTab == .chat) { subTab = .chat }
            tabPill(title: "Multi-Agent", selected: subTab == .multiAgent) { subTab = .multiAgent }

            Spacer(minLength: 16)

            Text("Chat")
                .font(AppearanceTheme.swiftUIFont(snap, delta: 11, weight: .bold))
                .foregroundStyle(primaryLabel)

            Spacer(minLength: 16)

            Button("New Chat") {
                session.newChatArchivingPrevious(
                    selectedWorkspaceId: selectedWorkspaceId,
                    config: configStore.snapshot
                )
            }
            .buttonStyle(.link)
            .font(AppearanceTheme.swiftUIFont(snap, delta: 0))
            .disabled(session.isStreaming)
            .keyboardShortcut("n", modifiers: [.command])

            Text("|")
                .font(AppearanceTheme.swiftUIFont(snap, delta: 0))
                .foregroundStyle(Color(red: 0.82, green: 0.82, blue: 0.84))
                .padding(.horizontal, 4)

            Button("Export") {
                session.exportConversationViaPanel()
            }
            .buttonStyle(.link)
            .font(AppearanceTheme.swiftUIFont(snap, delta: 0))
            .disabled(session.isStreaming || session.messages.isEmpty)
        }
    }

    private func tabPill(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppearanceTheme.swiftUIFont(snap, delta: 0, weight: selected ? .bold : .regular))
                .foregroundStyle(selected ? Color(red: 0, green: 0.48, blue: 1) : Color(red: 0.56, green: 0.56, blue: 0.58))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? Color.clear : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .padding(.trailing, 4)
        .help(title)
    }

    private var primaryLabel: Color {
        colorScheme == .dark ? Color(red: 0.95, green: 0.95, blue: 0.97) : Color(red: 0.11, green: 0.11, blue: 0.12)
    }

    private var chatScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: comfortableMargins ? 12 : 8) {
                    HStack {
                        Spacer(minLength: 0)
                        Button("Clear chat") {
                            session.clearChat(
                                selectedWorkspaceId: selectedWorkspaceId,
                                config: configStore.snapshot
                            )
                        }
                        .buttonStyle(.link)
                        .font(AppearanceTheme.swiftUIFont(snap, delta: 0))
                        .disabled(session.isStreaming)
                    }
                    .padding(.bottom, 4)

                    let visible = ChatTranscriptFilter.visibleMessages(
                        session.messages,
                        mode: guiChatPrefs.mcpTranscriptMode,
                        isStreaming: session.isStreaming
                    )
                    if visible.isEmpty {
                        Text(emptyStateWelcome)
                            .font(AppearanceTheme.swiftUIFont(snap, delta: 2))
                            .foregroundStyle(Color(red: 0.56, green: 0.56, blue: 0.58))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(40)
                    }
                    ForEach(visible) { msg in
                        MessageBubbleView(
                            message: msg,
                            workspaceTitle: workspaceDisplayName,
                            displayText: displayText(for: msg),
                            isStreamingPlaceholder: streamingPlaceholder(for: msg),
                            colorScheme: colorScheme,
                            fontSnapshot: snap,
                            assistantAvatarPath: msg.role == .assistant ? workspaceAvatarResolvedPath : nil,
                            onSpeak: msg.role == .assistant ? { speakAssistantReply($0) } : nil,
                            onFeedbackUp: msg.role == .assistant ? { recordChatFeedback(up: true) } : nil,
                            onFeedbackDown: msg.role == .assistant ? { recordChatFeedback(up: false) } : nil
                        )
                        .frame(maxWidth: .infinity, alignment: msg.role == .user ? .trailing : .leading)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(ChatScrollAnchor.bottom)
                }
                .padding(.horizontal, comfortableMargins ? 40 : 30)
                .padding(.top, 16)
                .padding(.trailing, 12)
            }
            .onChange(of: session.assistantCanvasObservationEpoch) {
                scrollChatToBottom(proxy: proxy)
            }
            .onChange(of: session.messages.count) {
                scrollChatToBottom(proxy: proxy)
            }
            .onChange(of: guiChatPrefs.mcpTranscriptMode) {
                scrollChatToBottom(proxy: proxy)
            }
        }
    }

    private func scrollChatToBottom(proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(ChatScrollAnchor.bottom, anchor: .bottom)
            }
        }
    }

    private func streamingPlaceholder(for msg: ChatMessage) -> Bool {
        guard msg.role == .assistant, session.isStreaming else { return false }
        return displayText(for: msg) == "…"
    }

    private var multiAgentPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.branch")
                .font(AppearanceTheme.swiftUIFont(snap, delta: 23))
                .foregroundStyle(.secondary)
            Text("Multi-Agent")
                .font(AppearanceTheme.swiftUIFont(snap, delta: 9, weight: .semibold))
            Text("Delegate to specialists and swarm workflows run in the Python desktop app. Chat streaming here uses the workspace LLM only.")
                .font(AppearanceTheme.swiftUIFont(snap, delta: 3))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showSlashPalette, !slashPaletteRows.isEmpty {
                composerPaletteScroll {
                    ForEach(slashPaletteRows, id: \.cmd) { row in
                        Button {
                            executeSlashCommand(row.cmd)
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.cmd)
                                    .font(AppearanceTheme.swiftUIFont(snap, delta: 0, weight: .semibold))
                                    .foregroundStyle(Color(red: 0, green: 0.48, blue: 1))
                                Text(row.label)
                                    .font(AppearanceTheme.swiftUIFont(snap, delta: 0))
                                    .foregroundStyle(primaryLabel)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if showMentionPalette, !mentionPaletteRows.isEmpty {
                composerPaletteScroll {
                    ForEach(mentionPaletteRows) { ws in
                        Button {
                            insertWorkspaceMention(ws)
                        } label: {
                            HStack(alignment: .center, spacing: 8) {
                                Text(ws.icon ?? "🤖")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ws.name)
                                        .font(AppearanceTheme.swiftUIFont(snap, delta: 0, weight: .medium))
                                        .foregroundStyle(primaryLabel)
                                    Text("@\(ws.mentionSlug)")
                                        .font(AppearanceTheme.swiftUIFont(snap, delta: -1))
                                        .foregroundStyle(Color(red: 0.56, green: 0.56, blue: 0.58))
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 12) {
            canvasToggleButton
            attachButton
            micButton

            ZStack(alignment: .topLeading) {
                if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Type your message… Type / for commands. @workspace to delegate. Shift+Enter for new line.")
                        .font(AppearanceTheme.swiftUIFont(snap, delta: 1))
                        .foregroundStyle(Color(red: 0.56, green: 0.56, blue: 0.58))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                ChatComposerNSTextView(
                    text: $draft,
                    fontSize: AppearanceTheme.baseFontSize(snap),
                    fontFamily: snap.fontFamily,
                    onSend: {
                        hideComposerPalettes()
                        send()
                    },
                    onEscape: { hideComposerPalettes() },
                    onTextOrSelectionChange: { full, range in
                        updateComposerPalettes(text: full, selectedRange: range)
                    }
                )
                .frame(minHeight: 44, maxHeight: 120)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(focusBorderColor, lineWidth: 1)
                        .background(RoundedRectangle(cornerRadius: 22).fill(Color(nsColor: .textBackgroundColor)))
                )
            }

            Button("Run") {
                runLastCodeBlockFromAssistant()
            }
            .font(AppearanceTheme.swiftUIFont(snap, delta: 1, weight: .medium))
            .frame(width: 56, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(focusBorderColor, lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            )
            .foregroundStyle(primaryLabel)
            .buttonStyle(.plain)
            .disabled(!runButtonEnabled)
            .help("Run last code block from assistant message")

            if session.isStreaming {
                Button("Stop") { session.cancel() }
                    .font(AppearanceTheme.swiftUIFont(snap, delta: 1, weight: .medium))
            }

            Button("Send") { send() }
                .font(AppearanceTheme.swiftUIFont(snap, delta: 1, weight: .medium))
                .frame(width: 80, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(sendEnabled ? Color(red: 0, green: 0.48, blue: 1) : Color(red: 0.7, green: 0.85, blue: 1))
                )
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .disabled(!sendEnabled)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }

    private func composerPaletteScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 200)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark ? Color(red: 0.2, green: 0.2, blue: 0.22) : Color(red: 0.97, green: 0.97, blue: 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(focusBorderColor, lineWidth: 1)
        )
    }

    private func hideComposerPalettes() {
        showSlashPalette = false
        showMentionPalette = false
        mentionReplaceRange = nil
    }

    private func updateComposerPalettes(text: String, selectedRange: NSRange) {
        let ns = text as NSString
        let len = ns.length
        let cursor = min(selectedRange.location, max(0, len))
        let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
        let line = ns.substring(with: lineRange)
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("/") {
            showMentionPalette = false
            mentionReplaceRange = nil
            let afterSlash = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces).lowercased()
            let filtered = Self.allSlashCommands.filter { row in
                let tail = String(row.cmd.dropFirst()).lowercased()
                return afterSlash.isEmpty || tail.hasPrefix(afterSlash)
            }
            slashPaletteRows = filtered
            showSlashPalette = !filtered.isEmpty
            return
        }

        showSlashPalette = false
        slashPaletteRows = []

        if let ctx = mentionContext(in: text, cursor: cursor) {
            mentionReplaceRange = ctx.replaceRange
            let currentId = selectedWorkspaceId
            let candidates = (workspaceStore.index?.workspaces ?? []).filter { ws in
                guard ws.interAgentEnabled else { return false }
                if ws.id == currentId { return false }
                let slug = ws.mentionSlug
                return ctx.filter.isEmpty
                    || slug.lowercased().contains(ctx.filter)
                    || ws.name.lowercased().contains(ctx.filter)
            }
            mentionPaletteRows = candidates
            showMentionPalette = !candidates.isEmpty
        } else {
            showMentionPalette = false
            mentionReplaceRange = nil
            mentionPaletteRows = []
        }
    }

    private struct MentionContext {
        let replaceRange: NSRange
        let filter: String
    }

    /// Active `@token` before cursor on the current line (no whitespace inside token); matches Python inter-agent slugs.
    private func mentionContext(in fullText: String, cursor: Int) -> MentionContext? {
        let ns = fullText as NSString
        let len = ns.length
        guard cursor >= 0, cursor <= len else { return nil }
        let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
        let lineStart = lineRange.location
        let line = ns.substring(with: lineRange) as NSString
        let posInLine = cursor - lineStart
        guard posInLine > 0 else { return nil }
        let before = line.substring(to: posInLine)
        guard let atIdx = before.lastIndex(of: "@") else { return nil }
        let atByte = before.distance(from: before.startIndex, to: atIdx)
        let afterAt = before.index(after: atIdx)
        let frag = String(before[afterAt...])
        if frag.contains(where: { $0.isWhitespace || $0.isNewline }) { return nil }
        let filter = frag.lowercased()
        let absAt = lineStart + atByte
        let replaceLen = cursor - absAt
        guard replaceLen >= 1 else { return nil }
        return MentionContext(
            replaceRange: NSRange(location: absAt, length: replaceLen),
            filter: filter
        )
    }

    private func insertWorkspaceMention(_ ws: WorkspaceRecord) {
        guard let r = mentionReplaceRange else { return }
        let ins = "@\(ws.mentionSlug) "
        let n = draft as NSString
        draft = n.replacingCharacters(in: r, with: ins)
        hideComposerPalettes()
    }

    private func executeSlashCommand(_ cmd: String) {
        let key = cmd.lowercased()
        draft = ""
        hideComposerPalettes()

        switch key {
        case "/new":
            session.newChatArchivingPrevious(
                selectedWorkspaceId: selectedWorkspaceId,
                config: configStore.snapshot
            )
        case "/export":
            session.exportConversationViaPanel()
        case "/clear":
            session.newChatArchivingPrevious(
                selectedWorkspaceId: selectedWorkspaceId,
                config: configStore.snapshot
            )
        case "/simple":
            session.setChatBannerInfo(
                "Compact mode is stored as `compact_mode` in ~/.grizzyclaw/config.yaml. Reload config after editing (or restart the app)."
            )
        case "/strict":
            session.setChatBannerInfo(
                "Strict execution mode (`exec_strict_mode`) is applied when using the Python agent runtime; edit config.yaml for parity."
            )
        default:
            if let msg = Self.slashMessagePayload[key] {
                session.send(
                    text: msg,
                    workspaceStore: workspaceStore,
                    configStore: configStore,
                    guiChatPrefs: guiChatPrefs,
                    selectedWorkspaceId: selectedWorkspaceId,
                    guiLlmOverride: guiChatPrefs.resolverLlmOverride()
                )
            }
        }
    }

    /// Python `ChatWidget._slash_commands` (cmd, label).
    private static let allSlashCommands: [(cmd: String, label: String)] = [
        ("/new", "New chat"),
        ("/export", "Export conversation"),
        ("/clear", "Clear conversation"),
        ("/help", "What can you do?"),
        ("/capabilities", "What can you do? (capabilities)"),
        ("/tasks", "List scheduled tasks"),
        ("/summary", "Summary of this chat"),
        ("/remember", "Remember that…"),
        ("/save", "Save to memory"),
        ("/remind", "Remind me"),
        ("/memory", "Show my memories"),
        ("/forget", "Forget that"),
        ("/schedule", "Schedule a task"),
        ("/simple", "Toggle simple mode (minimal UI)"),
        ("/strict", "Toggle strict mode (approve every command)"),
    ]

    private static let slashMessagePayload: [String: String] = [
        "/help": "What can you do?",
        "/capabilities": "What can you do?",
        "/tasks": "List my scheduled tasks",
        "/summary": "Please provide a brief summary of our conversation so far. Keep it to a short paragraph.",
        "/remember": "Remember that ",
        "/save": "Save the last assistant message to memory.",
        "/remind": "Remind me ",
        "/memory": "What did I tell you about?",
        "/forget": "Forget that ",
        "/schedule": "I want to schedule a task or reminder. ",
    ]

    private var focusBorderColor: Color {
        Color(red: 0.82, green: 0.82, blue: 0.84)
    }

    private var sendEnabled: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !session.isStreaming
            && workspaceReady
    }

    /// Python `ChatWidget._on_run_last_code_block`: enabled when we can send; tap shows info if no fence.
    private var runButtonEnabled: Bool {
        workspaceReady && !session.isStreaming
    }

    /// First ```…``` block in the last assistant message (raw content), matching Python `re.search` on that bubble.
    private func firstCodeFenceInLastAssistantMessage() -> String? {
        guard let msg = session.messages.reversed().first(where: { $0.role == .assistant }) else { return nil }
        let text = msg.content
        guard let regex = try? NSRegularExpression(
            pattern: "```(\\w*)\\s*\\n([\\s\\S]*?)```",
            options: []
        ) else { return nil }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: text, options: [], range: full) else { return nil }
        let langRange = m.range(at: 1)
        let codeRange = m.range(at: 2)
        let lang = langRange.location != NSNotFound
            ? ns.substring(with: langRange).trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        guard codeRange.location != NSNotFound else { return nil }
        let code = ns.substring(with: codeRange).trimmingCharacters(in: .whitespacesAndNewlines)
        if lang.isEmpty {
            return "```\n\(code)\n```"
        }
        return "```\(lang)\n\(code)\n```"
    }

    private func runLastCodeBlockFromAssistant() {
        guard let block = firstCodeFenceInLastAssistantMessage() else {
            session.setChatBannerInfo("No code block found in the last assistant message.")
            return
        }
        session.setChatBannerInfo(nil)
        let msg = "Please run this code and show the output:\n\n\(block)"
        session.send(
            text: msg,
            workspaceStore: workspaceStore,
            configStore: configStore,
            guiChatPrefs: guiChatPrefs,
            selectedWorkspaceId: selectedWorkspaceId,
            guiLlmOverride: guiChatPrefs.resolverLlmOverride()
        )
    }

    private var canvasToggleButton: some View {
        Button {
            canvasPanelVisible.toggle()
        } label: {
            Text("🖼")
                .font(AppearanceTheme.swiftUIFont(snap, delta: 1))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(canvasPanelVisible ? Color(red: 0.91, green: 0.95, blue: 1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(canvasPanelVisible ? Color(red: 0, green: 0.48, blue: 1) : Color(red: 0.56, green: 0.56, blue: 0.58))
        .help("Show or hide the Visual Canvas panel")
    }

    private var attachButton: some View {
        Button {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
            panel.allowsMultipleSelection = false
            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                if canvasModel.appendImageFile(at: url.path), !canvasPanelVisible {
                    canvasPanelVisible = true
                }
            }
        } label: {
            Text("📎")
                .font(AppearanceTheme.swiftUIFont(snap, delta: 1))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(red: 0.56, green: 0.56, blue: 0.58))
        .help("Attach image (shown on Visual Canvas)")
    }

    private var micButton: some View {
        Button {
            // Voice capture matches Python app; native build focuses on text + canvas.
        } label: {
            Text("🎤")
                .font(AppearanceTheme.swiftUIFont(snap, delta: 1))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(red: 0.56, green: 0.56, blue: 0.58))
        .help("Record voice or attach audio (full pipeline in Python app)")
        .disabled(true)
    }

    private var workspaceReady: Bool {
        guard let wid = selectedWorkspaceId, let idx = workspaceStore.index else { return false }
        return idx.workspaces.contains(where: { $0.id == wid })
    }

    private var emptyStateWelcome: String {
        if !workspaceReady {
            return "Welcome! Start a conversation by typing a message below.\n\nSelect a workspace in the sidebar first."
        }
        return "Welcome! Start a conversation by typing a message below.\n\n"
            + "I can help with questions, remember things for you, schedule tasks, and browse the web."
    }

    /// Python `_workspace_display_name`: `f"{icon} {name}"` for assistant sender label.
    private var workspaceDisplayName: String {
        guard let id = selectedWorkspaceId,
              let ws = workspaceStore.index?.workspaces.first(where: { $0.id == id })
        else {
            return "Assistant"
        }
        let icon = (ws.icon ?? "🤖").trimmingCharacters(in: .whitespacesAndNewlines)
        return icon.isEmpty ? ws.name : "\(icon) \(ws.name)"
    }

    /// Expanded path; only when file exists (Python `MessageBubble` avatar).
    private var workspaceAvatarResolvedPath: String? {
        guard let id = selectedWorkspaceId,
              let ws = workspaceStore.index?.workspaces.first(where: { $0.id == id }),
              let raw = ws.avatarPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        let expanded = (raw as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: expanded) ? expanded : nil
    }

    /// Python `_on_speak_requested` on macOS: `say -r 200`.
    private func speakAssistantReply(_ raw: String) {
        let t = Self.stripForSayCommand(raw)
        guard !t.isEmpty else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        task.arguments = ["-r", "200", t]
        do {
            try task.run()
        } catch {
            GrizzyClawLog.error("say failed: \(error.localizedDescription)")
        }
    }

    /// Python `_connect_feedback` → `WorkspaceManager.record_feedback`.
    private func recordChatFeedback(up: Bool) {
        guard let wid = selectedWorkspaceId else { return }
        do {
            try workspaceStore.recordFeedback(workspaceId: wid, up: up)
            session.setChatBannerInfo(up ? "Thanks for your feedback!" : "Thanks for your feedback.")
        } catch {
            GrizzyClawLog.error("recordFeedback: \(error.localizedDescription)")
        }
    }

    private static func stripForSayCommand(_ s: String) -> String {
        var t = s
        if let re = try? NSRegularExpression(pattern: #"\*\*([^*]+)\*\*"#, options: []) {
            let r = NSRange(t.startIndex..., in: t)
            t = re.stringByReplacingMatches(in: t, options: [], range: r, withTemplate: "$1")
        }
        if let re = try? NSRegularExpression(pattern: #"`([^`]+)`"#, options: []) {
            let r = NSRange(t.startIndex..., in: t)
            t = re.stringByReplacingMatches(in: t, options: [], range: r, withTemplate: "$1")
        }
        t = t.replacingOccurrences(of: "\n", with: " ")
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count > 5000 {
            t = String(t.prefix(5000))
        }
        return t
    }

    private func displayText(for msg: ChatMessage) -> String {
        let raw = msg.content
        if msg.role == .assistant {
            let stripped = CanvasExtraction.stripDisplayControls(raw)
            return stripped.isEmpty && session.isStreaming ? "…" : stripped
        }
        if msg.role == .tool {
            return McpToolTranscriptFormatting.toolMessageDisplayString(rawContent: raw)
        }
        return raw
    }

    private func send() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        hideComposerPalettes()
        draft = ""
        statusBarStore.showMessage("Sending to \(snap.defaultLlmProvider)...")
        session.send(
            text: t,
            workspaceStore: workspaceStore,
            configStore: configStore,
            guiChatPrefs: guiChatPrefs,
            selectedWorkspaceId: selectedWorkspaceId,
            guiLlmOverride: guiChatPrefs.resolverLlmOverride()
        )
    }

    /// Uses `session.assistantCanvasObservationEpoch` (coalesced in `ChatSessionModel`) instead of `onChange(of: messages)` to avoid SwiftUI updating multiple times per frame.
    private func applyCanvasSyncAfterAssistantObservation() {
        let aid = session.messages.last(where: { $0.role == .assistant })?.id
        if aid != lastAssistantMessageId {
            lastAssistantMessageId = aid
            streamingScreenshotEmitted = false
            streamingA2UIEmitted = false
            streamingPixmapEmitted = false
        }
        syncCanvasFromAssistantStream()
    }

    private func syncCanvasFromAssistantStream(forceFinal: Bool = false) {
        guard let last = session.messages.last, last.role == .assistant else { return }
        let text = last.content
        guard !text.isEmpty || forceFinal else { return }

        if !streamingScreenshotEmitted {
            if let path = CanvasExtraction.extractScreenshotPath(text) {
                canvasModel.setAgentScreenshot(path: path)
                streamingScreenshotEmitted = true
                if !canvasPanelVisible { canvasPanelVisible = true }
            }
        }

        if !streamingA2UIEmitted, let json = CanvasExtraction.extractA2UIPayloadString(text), !json.isEmpty {
            canvasModel.appendA2UIPreview(json)
            streamingA2UIEmitted = true
            if !canvasPanelVisible { canvasPanelVisible = true }
        }

        if !streamingPixmapEmitted, let pair = CanvasExtraction.extractBase64Image(text),
           let img = NSImage(data: pair.data)
        {
            canvasModel.appendPixmap(img)
            streamingPixmapEmitted = true
            if !canvasPanelVisible { canvasPanelVisible = true }
        }
    }
}
