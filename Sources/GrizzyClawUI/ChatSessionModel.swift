import Combine
import Foundation
import GrizzyClawAgent
import GrizzyClawCore
import GrizzyClawMLX

/// Result of `ChatSessionModel.runUsageBenchmark` (Swift `Result` requires `Failure: Error`).
public enum UsageBenchmarkOutcome: Sendable {
    case succeeded(elapsedMs: Double, approxTokens: Int)
    case failed(String)
}

/// Drives OpenAI-compatible streaming for the Chat tab (workspace + `config.yaml` merge).
@MainActor
public final class ChatSessionModel: ObservableObject {
    @Published public private(set) var messages: [ChatMessage] = []
    /// Bumps at most once per run-loop turn while streaming so views can use `onChange` without observing `[ChatMessage]` (avoids “updated multiple times per frame”).
    @Published public private(set) var assistantCanvasObservationEpoch: UInt64 = 0
    @Published public private(set) var statusLine: String?
    @Published public private(set) var infoLine: String?
    @Published public private(set) var isStreaming = false
    /// True after the last connection test failed (shows Retry in Chat).
    @Published public private(set) var connectionTestFailed = false

    // MARK: - Summary mode (prompt caching)

    /// When enabled, new sends include `rollingSummary` plus a small tail window of recent messages.
    @Published public var useSummaryMode = false
    /// Latest generated summary (stored locally in memory; not automatically persisted).
    @Published public private(set) var rollingSummary: String?
    /// The `messages.count` snapshot when `rollingSummary` was created. Used as an anchor to prefer recent context.
    @Published public private(set) var rollingSummaryAnchorMessageCount: Int = 0
    /// How many recent messages to include in summary mode (in addition to the summary).
    @Published public var summaryModeRecentMessageLimit: Int = 16

    private var streamTask: Task<Void, Never>?
    private var coalesceAssistantCanvasEpochTask: Task<Void, Never>?

    public init() {}

    private static func appendDeduped(_ messages: inout [ChatMessage], role: ChatMessage.Role, content: String) {
        if let last = messages.last, last.role == role, last.content == content {
            return
        }
        messages.append(ChatMessage(role: role, content: content))
    }

    private static func toolDedupeKey(server: String, tool: String, args: [String: Any]) -> String {
        if let q = args["query"] as? String {
            return server + "\u{1E}" + tool + "\u{1E}" + q
        }
        return server + "\u{1E}" + tool
    }

    private func bumpAssistantCanvasObservationImmediate() {
        assistantCanvasObservationEpoch &+= 1
    }

    /// Coalesces many streaming token updates into one epoch bump per main run-loop turn.
    private func scheduleCoalescedAssistantCanvasObservation() {
        guard coalesceAssistantCanvasEpochTask == nil else { return }
        coalesceAssistantCanvasEpochTask = Task { @MainActor in
            defer { coalesceAssistantCanvasEpochTask = nil }
            await Task.yield()
            assistantCanvasObservationEpoch &+= 1
        }
    }

    /// Rough token estimate for the Conversation history dialog (Python `get_session_summary` parity: ~bytes/4).
    public var approximateSessionTokens: Int {
        messages.reduce(0) { $0 + $1.content.utf8.count } / 4
    }

    private func conversationForLLM(maxMessages: Int) -> [ChatMessage] {
        // Default path: keep existing trimming behavior.
        guard useSummaryMode, let summary = rollingSummary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SessionTrim.trim(messages, maxMessages: maxMessages)
        }

        let tailCount = max(1, min(summaryModeRecentMessageLimit, maxMessages - 1))

        // Prefer messages after the summary was generated, but fall back to full tail if that window is empty.
        let anchor = max(0, min(rollingSummaryAnchorMessageCount, messages.count))
        let candidate = Array(messages.dropFirst(anchor))
        let tailSource = candidate.isEmpty ? messages : candidate
        let tail = Array(tailSource.suffix(tailCount))

        let sys = ChatMessage(
            role: .system,
            content: """
            Conversation summary (authoritative; may omit details):
            \(summary)
            """
        )
        return [sys] + tail
    }

    public func clearRollingSummary() {
        rollingSummary = nil
        rollingSummaryAnchorMessageCount = 0
        useSummaryMode = false
    }

    public func generateRollingSummary(
        workspaceStore: WorkspaceStore,
        configStore: ConfigStore,
        guiChatPrefs: GuiChatPrefsStore,
        selectedWorkspaceId: String
    ) {
        guard !isStreaming else { return }

        infoLine = "Summarizing chat…"
        statusLine = nil

        streamTask?.cancel()
        streamTask = Task { @MainActor in
            defer { streamTask = nil }

            let userSnap = configStore.snapshot
            let secrets = UserConfigLoader.loadSecretsWithKeychainLenient()
            let routing = configStore.routingExtras
            let guiLlmOverride = guiChatPrefs.resolverLlmOverride()
            guard let idx = workspaceStore.index else {
                infoLine = nil
                statusLine = "No workspaces file found."
                return
            }
            guard let ws = idx.workspaces.first(where: { $0.id == selectedWorkspaceId }) else {
                infoLine = nil
                statusLine = "Workspace not found."
                return
            }

            let maxMsgs = ws.config?.int(forKey: "max_session_messages") ?? userSnap.maxSessionMessages

            // Summaries should be deterministic-ish and never call tools.
            let summarizerSuffix = """
            You are summarizing a chat transcript for future continuation.
            - Do NOT call tools or emit TOOL_CALL JSON.
            - Write a compact, factual summary with enough detail to continue the work.
            - Include: user intent, current state, what has been tried, current errors, key file paths, and next steps.
            - Prefer bullets. Keep under ~500-900 tokens.
            """

            let resolved: ResolvedLLMStreamRequest
            do {
                resolved = try ChatParameterResolver.resolve(
                    user: userSnap,
                    routing: routing,
                    secrets: secrets,
                    workspace: ws,
                    guiLlmOverride: guiLlmOverride,
                    systemPromptSuffix: summarizerSuffix
                )
            } catch {
                infoLine = nil
                statusLine = Self.formatError(error)
                return
            }

            // Give the model enough to build a solid summary; one-time cost is fine.
            let convo = SessionTrim.trim(messages, maxMessages: max(maxMsgs, 120))

            var out = ""
            do {
                for try await piece in Self.stream(for: resolved, conversation: convo) {
                    if Task.isCancelled { break }
                    out += piece
                }
            } catch is CancellationError {
                infoLine = "Cancelled."
                statusLine = nil
                return
            } catch {
                infoLine = nil
                statusLine = Self.formatError(error)
                return
            }

            let cleaned = out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else {
                infoLine = nil
                statusLine = "Summary generation returned empty output."
                return
            }

            rollingSummary = cleaned
            rollingSummaryAnchorMessageCount = messages.count
            useSummaryMode = true
            infoLine = "Summary updated. Using summary mode for next prompts."
            statusLine = nil
        }
    }

    /// One line: `Current session: N messages, ~Xk tokens` (matches `conversation_history_dialog.py`).
    public var sessionSummaryLine: String {
        let n = messages.count
        let k = approximateSessionTokens / 1000
        return "Current session: \(n) messages, ~\(k)k tokens"
    }

    /// Composer actions (e.g. Run) can surface short feedback in the info banner.
    public func setChatBannerInfo(_ text: String?) {
        infoLine = text
    }

    public func cancel() {
        streamTask?.cancel()
    }

    /// Re-runs the same connection test as **Test connection** (after a failure), with a short delay for flaky localhost stacks.
    public func retryConnectionTest(
        workspaceStore: WorkspaceStore,
        configStore: ConfigStore,
        selectedWorkspaceId: String?,
        guiLlmOverride: GuiChatPreferences.LLM? = nil
    ) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            await self?.runConnectionTest(
                workspaceStore: workspaceStore,
                configStore: configStore,
                selectedWorkspaceId: selectedWorkspaceId,
                guiLlmOverride: guiLlmOverride
            )
        }
    }

    /// Reload messages from `~/.grizzyclaw/sessions/{ws}_gui_user.json` when the workspace changes.
    public func syncWorkspace(selectedWorkspaceId: String?, config: UserConfigSnapshot) {
        streamTask?.cancel()
        statusLine = nil
        infoLine = nil
        guard config.sessionPersistence else {
            messages = []
            bumpAssistantCanvasObservationImmediate()
            return
        }
        guard let wid = selectedWorkspaceId else {
            messages = []
            bumpAssistantCanvasObservationImmediate()
            return
        }
        do {
            let external = SessionPersistence.hasSessionFileChangedSinceRecorded(workspaceId: wid)
            let turns = try SessionPersistence.loadTurns(workspaceId: wid)
            messages = Self.mapTurns(turns)
            bumpAssistantCanvasObservationImmediate()
            SessionPersistence.recordSessionFileModificationDate(workspaceId: wid)
            if !messages.isEmpty {
                infoLine = external
                    ? "Session file was updated on disk. Loaded \(messages.count) message(s)."
                    : "Restored \(messages.count) message(s) from disk for this workspace."
            } else if external {
                infoLine = "Session file changed on disk; it is currently empty."
            }
        } catch {
            statusLine = error.localizedDescription
            GrizzyClawLog.error("session sync failed: \(error.localizedDescription)")
            messages = []
            bumpAssistantCanvasObservationImmediate()
        }
    }

    public func clearChat(selectedWorkspaceId: String?, config: UserConfigSnapshot) {
        streamTask?.cancel()
        messages = []
        bumpAssistantCanvasObservationImmediate()
        statusLine = nil
        infoLine = nil
        guard config.sessionPersistence, let wid = selectedWorkspaceId else { return }
        try? SessionPersistence.clearFile(workspaceId: wid)
    }

    /// Starts a fresh thread: archives the current session file (if it had messages), then saves an empty session (A2).
    public func newChatArchivingPrevious(selectedWorkspaceId: String?, config: UserConfigSnapshot) {
        streamTask?.cancel()
        statusLine = nil
        infoLine = nil
        guard config.sessionPersistence else {
            messages = []
            bumpAssistantCanvasObservationImmediate()
            infoLine = "Turn on session_persistence in config to archive chats on disk."
            return
        }
        guard let wid = selectedWorkspaceId else {
            statusLine = "Select a workspace first."
            return
        }
        do {
            if let archived = try SessionPersistence.archiveCurrentSessionIfNonEmpty(workspaceId: wid) {
                infoLine = "Previous chat archived to \(archived.lastPathComponent). New chat started."
            } else {
                infoLine = "New chat started."
            }
            messages = []
            bumpAssistantCanvasObservationImmediate()
            try SessionPersistence.saveTurns([], workspaceId: wid)
            SessionPersistence.recordSessionFileModificationDate(workspaceId: wid)
        } catch {
            statusLine = error.localizedDescription
        }
    }

    /// Re-reads the session file from disk (same as switching workspace away and back).
    public func reloadSessionFromDisk(selectedWorkspaceId: String?, config: UserConfigSnapshot) {
        _ = reloadSessionFromDiskReturningCount(selectedWorkspaceId: selectedWorkspaceId, config: config)
    }

    /// Reloads from disk and returns how many messages are now in memory (for Conversation history alerts).
    @discardableResult
    public func reloadSessionFromDiskReturningCount(
        selectedWorkspaceId: String?,
        config: UserConfigSnapshot
    ) -> Int {
        syncWorkspace(selectedWorkspaceId: selectedWorkspaceId, config: config)
        return messages.count
    }

    /// Imports JSON or Markdown (export format) into the current workspace and saves (A6).
    public func importConversationViaPanel(selectedWorkspaceId: String?, config: UserConfigSnapshot) {
        guard config.sessionPersistence else {
            statusLine = "Turn on session_persistence to import into the session file."
            return
        }
        guard let wid = selectedWorkspaceId else {
            statusLine = "Select a workspace first."
            return
        }
        ChatImportPresenter.presentOpenPanel { [weak self] url in
            guard let self, let url else { return }
            do {
                let data = try Data(contentsOf: url)
                let turns = try ChatImportParser.parse(data: data, filenameHint: url.lastPathComponent)
                self.streamTask?.cancel()
                self.messages = Self.mapTurns(turns)
                self.bumpAssistantCanvasObservationImmediate()
                try SessionPersistence.saveTurns(turns, workspaceId: wid)
                SessionPersistence.recordSessionFileModificationDate(workspaceId: wid)
                self.statusLine = nil
                self.infoLine = "Imported \(turns.count) message(s) from \(url.lastPathComponent)."
            } catch {
                self.statusLine = error.localizedDescription
                GrizzyClawLog.error("session import failed: \(error.localizedDescription)")
            }
        }
    }

    public func testConnection(
        workspaceStore: WorkspaceStore,
        configStore: ConfigStore,
        selectedWorkspaceId: String?,
        guiLlmOverride: GuiChatPreferences.LLM? = nil
    ) {
        Task { [weak self] in
            await self?.runConnectionTest(
                workspaceStore: workspaceStore,
                configStore: configStore,
                selectedWorkspaceId: selectedWorkspaceId,
                guiLlmOverride: guiLlmOverride
            )
        }
    }

    private func runConnectionTest(
        workspaceStore: WorkspaceStore,
        configStore: ConfigStore,
        selectedWorkspaceId: String?,
        guiLlmOverride: GuiChatPreferences.LLM? = nil
    ) async {
        connectionTestFailed = false
        statusLine = nil
        infoLine = nil
        let secrets = UserConfigLoader.loadSecretsWithKeychainLenient()
        let userSnap = configStore.snapshot
        let routing = configStore.routingExtras
        guard let idx = workspaceStore.index else {
            statusLine = "No workspaces file found. Create a workspace on the Workspaces tab."
            return
        }
        let wid = selectedWorkspaceId ?? idx.activeWorkspaceId
        guard let wid else {
            statusLine = "Select a workspace in the Workspaces tab."
            return
        }
        guard let ws = idx.workspaces.first(where: { $0.id == wid }) else {
            statusLine = "Workspace not found."
            return
        }
        let resolved: ResolvedLLMStreamRequest
        do {
            resolved = try ChatParameterResolver.resolve(
                user: userSnap,
                routing: routing,
                secrets: secrets,
                workspace: ws,
                guiLlmOverride: guiLlmOverride
            )
        } catch {
            statusLine = Self.formatError(error)
            return
        }
        let result = await ChatConnectionTest.ping(resolved: resolved)
        if result.ok {
            connectionTestFailed = false
            infoLine = result.message
            statusLine = nil
        } else {
            connectionTestFailed = true
            infoLine = nil
            statusLine = LLMErrorHints.formattedPingFailureMessage(result.message)
        }
    }

    public func send(
        text: String,
        workspaceStore: WorkspaceStore,
        configStore: ConfigStore,
        guiChatPrefs: GuiChatPrefsStore,
        selectedWorkspaceId: String?,
        guiLlmOverride: GuiChatPreferences.LLM? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            await self.performSend(
                text: trimmed,
                workspaceStore: workspaceStore,
                configStore: configStore,
                guiChatPrefs: guiChatPrefs,
                selectedWorkspaceId: selectedWorkspaceId,
                guiLlmOverride: guiLlmOverride
            )
        }
    }

    private func performSend(
        text: String,
        workspaceStore: WorkspaceStore,
        configStore: ConfigStore,
        guiChatPrefs: GuiChatPrefsStore,
        selectedWorkspaceId: String?,
        guiLlmOverride: GuiChatPreferences.LLM? = nil
    ) async {
        statusLine = nil
        infoLine = nil
        isStreaming = true
        defer {
            isStreaming = false
            persistSession(workspaceId: selectedWorkspaceId ?? workspaceStore.index?.activeWorkspaceId, config: configStore.snapshot)
        }

        let secrets = UserConfigLoader.loadSecretsWithKeychainLenient()

        let userSnap = configStore.snapshot
        let routing = configStore.routingExtras

        guard let idx = workspaceStore.index else {
            statusLine = "No workspaces file found."
            return
        }
        let wid = selectedWorkspaceId ?? idx.activeWorkspaceId
        guard let wid else {
            statusLine = "Select a workspace in the Workspaces tab."
            return
        }
        guard let ws = idx.workspaces.first(where: { $0.id == wid }) else {
            statusLine = "Workspace not found."
            return
        }

        let maxMsgs = ws.config?.int(forKey: "max_session_messages") ?? userSnap.maxSessionMessages

        var disc = guiChatPrefs.lastDiscovery?.mergingPythonInternalTools()
        if disc == nil {
            if let d = try? await MCPToolsDiscovery.discover(mcpServersFile: userSnap.mcpServersFile) {
                disc = d.mergingPythonInternalTools()
                guiChatPrefs.applyDiscovery(d)
            }
        }

        let allowPairs = ws.config?.mcpToolAllowlistPairs(forKey: "mcp_tool_allowlist") ?? []
        let filtered = (disc ?? MCPToolsDiscoveryResult(servers: [:], errorMessage: nil))
            .mergingPythonInternalTools()
            .filteredByWorkspaceAllowlist(allowPairs)

        let mcpSuffix = MCPSystemPromptAugmentor.mcpSuffix(
            discovery: filtered,
            includeSchemas: userSnap.mcpPromptSchemasEnabled
        ) { srv, tool in
            guiChatPrefs.isToolOn(server: srv, tool: tool)
        }
        let skillSuffix = SkillPromptAugmentor.skillsSuffix(
            enabledSkillIDs: ClawHubSkillResolver.resolvedSkillIDs(user: userSnap, workspace: ws)
        )
        let canvasSuffix = CanvasPromptAugmentor.suffix()
        let combinedPromptSuffix = [mcpSuffix, skillSuffix, canvasSuffix]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let systemPromptSuffix: String? = combinedPromptSuffix.isEmpty ? nil : combinedPromptSuffix

        messages.append(ChatMessage(role: .user, content: text))

        if let request = Self.directLowContextTodayCalendarEventsRequest(text, discovery: filtered) {
            do {
                let toolText = try await Self.runDirectLowContextTodayCalendarEvents(
                    mcpServersFile: userSnap.mcpServersFile,
                    server: request.server,
                    calendarHint: request.calendarHint,
                    discovery: filtered,
                    autoFollowActions: guiChatPrefs.mcpAutoFollowActions
                )
                messages.append(
                    ChatMessage(
                        role: .assistant,
                        content: toolText
                    )
                )
                bumpAssistantCanvasObservationImmediate()
                statusLine = nil
            } catch {
                statusLine = Self.formatError(error)
                GrizzyClawLog.error("direct low-context calendar event search failed: \(error.localizedDescription)")
            }
            return
        }

        if let request = Self.directLowContextSafeDefaultRequest(text, discovery: filtered) {
            do {
                let toolText = try await Self.runDirectLowContextSafeDefault(
                    mcpServersFile: userSnap.mcpServersFile,
                    server: request.server,
                    domain: request.domain,
                    userText: text
                )
                messages.append(ChatMessage(role: .assistant, content: toolText))
                bumpAssistantCanvasObservationImmediate()
                statusLine = nil
            } catch {
                statusLine = Self.formatError(error)
                GrizzyClawLog.error("direct low-context safe-default failed (\(request.domain.rawValue)): \(error.localizedDescription)")
            }
            return
        }

        if let request = Self.directLowContextNewEmailRequest(text, discovery: filtered) {
            do {
                let toolText = try await Self.runDirectLowContextNewEmail(
                    mcpServersFile: userSnap.mcpServersFile,
                    server: request,
                    discovery: filtered,
                    autoFollowActions: guiChatPrefs.mcpAutoFollowActions
                )
                messages.append(
                    ChatMessage(
                        role: .assistant,
                        content: toolText
                    )
                )
                bumpAssistantCanvasObservationImmediate()
                statusLine = nil
            } catch {
                statusLine = Self.formatError(error)
                GrizzyClawLog.error("direct low-context email check failed: \(error.localizedDescription)")
            }
            return
        }

        if let request = Self.directLowContextNotesRequest(text, discovery: filtered) {
            do {
                let toolText = try await Self.runDirectLowContextNotes(
                    mcpServersFile: userSnap.mcpServersFile,
                    server: request
                )
                messages.append(ChatMessage(role: .assistant, content: toolText))
                bumpAssistantCanvasObservationImmediate()
                statusLine = nil
            } catch {
                statusLine = Self.formatError(error)
                GrizzyClawLog.error("direct low-context notes check failed: \(error.localizedDescription)")
            }
            return
        }

        if let request = Self.directLowContextTodayRemindersRequest(text, discovery: filtered) {
            do {
                let toolText = try await Self.runDirectLowContextTodayReminders(
                    mcpServersFile: userSnap.mcpServersFile,
                    server: request
                )
                messages.append(ChatMessage(role: .assistant, content: toolText))
                bumpAssistantCanvasObservationImmediate()
                statusLine = nil
            } catch {
                statusLine = Self.formatError(error)
                GrizzyClawLog.error("direct low-context reminders check failed: \(error.localizedDescription)")
            }
            return
        }

        if Self.isDirectMacuseListCalendarsIntent(text) {
            do {
                let toolText = try await Self.runDirectMacuseListCalendars(
                    mcpServersFile: userSnap.mcpServersFile,
                    discovery: filtered,
                    autoFollowActions: guiChatPrefs.mcpAutoFollowActions
                )
                messages.append(
                    ChatMessage(
                        role: .assistant,
                        content: McpToolTranscriptFormatting.compactToolResultBody(toolText)
                    )
                )
                bumpAssistantCanvasObservationImmediate()
                statusLine = nil
            } catch {
                statusLine = Self.formatError(error)
                GrizzyClawLog.error("direct macuse calendar list failed: \(error.localizedDescription)")
            }
            return
        }

        var toolRound = 0
        let maxToolRounds = 5
        var executedToolKeys = Set<String>()

        while toolRound < maxToolRounds {
            toolRound += 1

            let resolved: ResolvedLLMStreamRequest
            do {
                resolved = try ChatParameterResolver.resolve(
                    user: userSnap,
                    routing: routing,
                    secrets: secrets,
                    workspace: ws,
                    guiLlmOverride: guiLlmOverride,
                    systemPromptSuffix: systemPromptSuffix
                )
            } catch {
                statusLine = Self.formatError(error)
                return
            }

            switch resolved {
            case .openAICompatible:
                GrizzyClawLog.debug("chat send: OpenAI-compatible stream")
            case .anthropic:
                GrizzyClawLog.debug("chat send: Anthropic stream")
            case .lmStudioV1:
                GrizzyClawLog.debug("chat send: LM Studio v1 stream")
            case .mlx:
                GrizzyClawLog.debug("chat send: MLX local stream")
            }

            let trimmedSession = conversationForLLM(maxMessages: maxMsgs)
            messages.append(ChatMessage(role: .assistant, content: ""))
            bumpAssistantCanvasObservationImmediate()
            guard let assistantIndex = messages.indices.last else { return }

            let stream = Self.stream(for: resolved, conversation: trimmedSession)

            do {
                for try await piece in stream {
                    if Task.isCancelled { break }
                    var copy = messages
                    copy[assistantIndex].content += piece
                    messages = copy
                    scheduleCoalescedAssistantCanvasObservation()
                }
                if Task.isCancelled {
                    infoLine = "Cancelled."
                    statusLine = nil
                    return
                }
            } catch is CancellationError {
                infoLine = "Cancelled."
                statusLine = nil
                return
            } catch {
                if Task.isCancelled || Self.isCancellationLikeError(error) {
                    infoLine = "Cancelled."
                    statusLine = nil
                    return
                }
                statusLine = Self.formatError(error)
                GrizzyClawLog.error("chat stream error: \(error.localizedDescription)")
                return
            }

            let rawAssistant = messages[assistantIndex].content
            var jsonBodies = ToolCallCommandParsing.findToolCallJsonObjects(in: rawAssistant)
            if jsonBodies.isEmpty {
                let merged = guiChatPrefs.lastDiscovery?.mergingPythonInternalTools()
                if let synthetic = ToolCallValidation.lowContextFallbackToolCallJSON(
                    assistantText: rawAssistant,
                    messages: messages,
                    discovery: merged
                ) {
                    messages[assistantIndex].content = ""
                    jsonBodies = [synthetic]
                    GrizzyClawLog.debug("chat fallback: synthesized low-context get_tool_definitions TOOL_CALL")
                } else if let retryMsg = ToolCallValidation.lowContextMissingToolCallMessage(
                    assistantText: rawAssistant,
                    messages: messages,
                    discovery: merged
                ) {
                    messages[assistantIndex].content = ""
                    messages.append(
                        ChatMessage(
                            role: .tool,
                            content: retryMsg + McpToolTranscriptFormatting.llmFollowUpInstructionSuffix
                        )
                    )
                    GrizzyClawLog.debug("chat retry: suppressed low-context narration without TOOL_CALL")
                    bumpAssistantCanvasObservationImmediate()
                    continue
                } else if let (server, tool, args) = Self.directDdgSearchToolCallIfRequested(
                    assistantText: rawAssistant,
                    messages: messages,
                    discovery: merged
                ) {
                    // Deterministic fallback: if the user explicitly asked to use ddg-search but the model
                    // failed to emit a TOOL_CALL, run the tool anyway so the user sees results.
                    //
                    // This avoids "nothing happened" UX for small/local models that don't reliably follow
                    // tool-calling format.
                    messages[assistantIndex].content = ""
                    if guiChatPrefs.isToolOn(server: server, tool: tool) {
                        do {
                            let k = Self.toolDedupeKey(server: server, tool: tool, args: args)
                            if executedToolKeys.contains(k) {
                                bumpAssistantCanvasObservationImmediate()
                                continue
                            }
                            executedToolKeys.insert(k)
                            let r = try await MCPToolCaller.call(
                                mcpServersFile: userSnap.mcpServersFile,
                                mcpServer: server,
                                tool: tool,
                                arguments: args
                            )
                            var toolUserMsg = "[Tool result \(server).\(tool)]\n\(r)"
                            toolUserMsg += McpToolTranscriptFormatting.llmFollowUpInstructionSuffix
                            Self.appendDeduped(&messages, role: .tool, content: toolUserMsg)
                        } catch {
                            Self.appendDeduped(&messages, role: .tool, content: "[Tool error]\n\(error.localizedDescription)")
                        }
                    } else {
                        Self.appendDeduped(
                            &messages,
                            role: .tool,
                            content: "[Tool result \(server).\(tool)]\n**⏸ Tool disabled in the Tools menu for this chat session.**"
                                + McpToolTranscriptFormatting.llmFollowUpInstructionSuffix
                        )
                    }
                    bumpAssistantCanvasObservationImmediate()
                    continue
                }
                messages[assistantIndex].content = CanvasExtraction.stripMLXChannelFormat(
                    ToolCallCommandParsing.stripToolCallBlocks(rawAssistant)
                )
                bumpAssistantCanvasObservationImmediate()
                break
            }

            messages[assistantIndex].content = CanvasExtraction.stripMLXChannelFormat(
                ToolCallCommandParsing.stripToolCallBlocks(rawAssistant)
            )
            bumpAssistantCanvasObservationImmediate()

            let shouldAutoListLowContextCalendars =
                jsonBodies.count == 1 && Self.shouldAutoListCalendarsAfterLowContextDiscovery(messages)
            var parts: [String] = []
            var suppressedDuplicateToolCall = false
            for body in jsonBodies {
                guard let data = body.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }
                let mcpName = ToolCallCommandParsing.normalizeMcpIdentifier(
                    ((obj["mcp"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                )
                var toolName = ToolCallCommandParsing.normalizeMcpIdentifier(
                    ((obj["tool"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                )
                if toolName.isEmpty, !mcpName.isEmpty {
                    let merged = guiChatPrefs.lastDiscovery?.mergingPythonInternalTools()
                    let toolList = merged?.servers[mcpName] ?? []
                    if toolList.count == 1 {
                        toolName = toolList[0].name
                    }
                }
                var args = obj["arguments"] as? [String: Any] ?? [:]
                if args.isEmpty, toolName.lowercased().contains("search") {
                    if let q = Self.heuristicSearchQueryFromSession(messages) {
                        args = ["query": q]
                    }
                }
                if mcpName.isEmpty || toolName.isEmpty { continue }

                let (canonMcp, canonTool) = guiChatPrefs.resolvedMcpToolPair(modelMcp: mcpName, modelTool: toolName)
                let merged = guiChatPrefs.lastDiscovery?.mergingPythonInternalTools()
                let dedupeKey = Self.toolDedupeKey(server: canonMcp, tool: canonTool, args: args)
                if executedToolKeys.contains(dedupeKey) {
                    suppressedDuplicateToolCall = true
                    continue
                }

                if !ToolCallValidation.isKnownTool(server: canonMcp, tool: canonTool, discovery: merged) {
                    parts.append(
                        "[Tool result \(canonMcp).\(canonTool)]\n"
                            + ToolCallValidation.invalidToolMessage(
                                requestedServer: canonMcp,
                                requestedTool: canonTool,
                                discovery: merged
                            )
                    )
                    continue
                }

                if !guiChatPrefs.isToolOn(server: mcpName, tool: toolName) {
                    parts.append(
                        "[Tool result \(canonMcp).\(canonTool)]\n**⏸ Tool disabled in the Tools menu for this chat session.**"
                    )
                    continue
                }

                if canonMcp == "grizzyclaw" {
                    let r = GrizzyClawInternalToolStubs.result(
                        tool: canonTool,
                        arguments: args,
                        workspaceId: wid,
                        config: userSnap
                    )
                    parts.append("[Tool result \(canonMcp).\(canonTool)]\n\(r)")
                    continue
                }

                do {
                    executedToolKeys.insert(dedupeKey)
                    let r = try await MCPToolCaller.call(
                        mcpServersFile: userSnap.mcpServersFile,
                        mcpServer: canonMcp,
                        tool: canonTool,
                        arguments: args
                    )
                    parts.append("[Tool result \(canonMcp).\(canonTool)]\n\(r)")
                    if guiChatPrefs.mcpAutoFollowActions {
                        let actionBlocks = try await Self.followReturnedToolActions(
                            from: r,
                            server: canonMcp,
                            mcpServersFile: userSnap.mcpServersFile,
                            discovery: merged
                        ) { server, tool in
                            guiChatPrefs.isToolOn(server: server, tool: tool)
                        }
                        parts.append(contentsOf: actionBlocks)
                    }
                    if shouldAutoListLowContextCalendars,
                       let followupArgs = Self.lowContextCalendarListFollowupArguments(
                        server: canonMcp,
                        tool: canonTool
                       ) {
                        let followupResult = try await MCPToolCaller.call(
                            mcpServersFile: userSnap.mcpServersFile,
                            mcpServer: canonMcp,
                            tool: "call_tool_by_name",
                            arguments: followupArgs
                        )
                        parts.append("[Tool result \(canonMcp).call_tool_by_name]\n\(followupResult)")
                        if guiChatPrefs.mcpAutoFollowActions {
                            let actionBlocks = try await Self.followReturnedToolActions(
                                from: followupResult,
                                server: canonMcp,
                                mcpServersFile: userSnap.mcpServersFile,
                                discovery: merged
                            ) { server, tool in
                                guiChatPrefs.isToolOn(server: server, tool: tool)
                            }
                            parts.append(contentsOf: actionBlocks)
                        }
                    }
                } catch {
                    parts.append("[Tool error]\n\(error.localizedDescription)")
                }
            }

            if parts.isEmpty {
                // If the model re-requested tools we already ran, don't silently produce "nothing".
                // Provide a tiny tool transcript hint so the model continues with the existing results.
                if suppressedDuplicateToolCall {
                    var toolUserMsg =
                        "[Tool result]\n(duplicate TOOL_CALL suppressed; use the previous tool results above and continue your answer)"
                    toolUserMsg += McpToolTranscriptFormatting.llmFollowUpInstructionSuffix
                    Self.appendDeduped(&messages, role: .tool, content: toolUserMsg)
                    bumpAssistantCanvasObservationImmediate()
                    continue
                }
                break
            }

            var toolUserMsg = parts.joined(separator: "\n\n")
            toolUserMsg += McpToolTranscriptFormatting.llmFollowUpInstructionSuffix
            Self.appendDeduped(&messages, role: .tool, content: toolUserMsg)
            bumpAssistantCanvasObservationImmediate()
        }
    }

    /// Small local models often emit `search` with `{}`; map the user’s actual question into a `query` argument when empty.
    private static func heuristicSearchQueryFromSession(_ messages: [ChatMessage]) -> String? {
        let users = messages.filter { $0.role == .user }
        let pick = users.reversed().first(where: { !$0.content.hasPrefix("[Tool output]") }) ?? users.last
        let t = pick?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    private static func directDdgSearchToolCallIfRequested(
        assistantText: String,
        messages: [ChatMessage],
        discovery: MCPToolsDiscoveryResult?
    ) -> (server: String, tool: String, arguments: [String: Any])? {
        let userText = heuristicSearchQueryFromSession(messages)?.lowercased() ?? ""
        // User explicitly asked for ddg-search.
        guard userText.contains("ddg-search") else { return nil }
        // Avoid triggering on tool result echoes.
        if userText.hasPrefix("[tool output]") { return nil }
        // Require that ddg-search.search exists in discovery (or we should not guess).
        guard let tools = discovery?.servers["ddg-search"], tools.contains(where: { $0.name == "search" }) else { return nil }
        // Prefer using the latest user prompt as the query, stripped of the "use ddg-search" preface.
        let rawQuery = heuristicSearchQueryFromSession(messages) ?? ""
        let cleaned = rawQuery
            .replacingOccurrences(of: "use ddg-search", with: "", options: [.caseInsensitive], range: nil)
            .replacingOccurrences(of: "ddg-search", with: "", options: [.caseInsensitive], range: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let query = cleaned.isEmpty ? rawQuery : cleaned
        return (server: "ddg-search", tool: "search", arguments: ["query": query, "max_results": 10])
    }

    private static func directLowContextTodayCalendarEventsRequest(
        _ text: String,
        discovery: MCPToolsDiscoveryResult?
    ) -> (server: String, calendarHint: String?)? {
        guard let server = preferredLowContextServer(discovery) else { return nil }
        guard matchesTodayCalendarEventsQuery(text) else { return nil }
        let rawHint = extractCalendarHint(from: text)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hint = (rawHint?.isEmpty == false) ? rawHint : nil
        return (server, hint)
    }

    /// Deterministic path for “events today” without relying on the model for low-context MCP servers.
    private static func matchesTodayCalendarEventsQuery(_ text: String) -> Bool {
        let q = text.lowercased()
        guard q.contains("today") else { return false }
        let cal = q.contains("calendar") || q.contains("calender") || q.contains("schedule")
        guard cal else { return false }
        if q.contains("event") || q.contains("meeting") || q.contains("appointment") { return true }
        if q.contains("do i have") || q.contains("did i have") { return true }
        if q.contains("anything ") || q.contains("something ") { return true }
        if q.contains("on my ") { return true }
        if q.contains("what") && q.contains(" on ") { return true }
        return false
    }

    private static func preferredLowContextServer(_ discovery: MCPToolsDiscoveryResult?) -> String? {
        guard let merged = discovery?.mergingPythonInternalTools() else { return nil }
        let lowContextServers = merged.servers.compactMap { server, tools -> String? in
            let names = Set(tools.map(\.name))
            return names.contains("get_tool_definitions") && names.contains("call_tool_by_name") ? server : nil
        }.sorted()
        if lowContextServers.contains("macuse") { return "macuse" }
        return lowContextServers.count == 1 ? lowContextServers[0] : nil
    }

    private static func extractCalendarHint(from text: String) -> String? {
        if let range = text.range(
            of: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let email = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !email.isEmpty { return email }
        }
        if let range = text.range(
            of: #"(?i)(?:in|on)\s+(?:my\s+)?(.+?)\s+calend(?:a|e)r"#,
            options: [.regularExpression]
        ) {
            let matched = String(text[range])
            if let inner = matched.range(
                of: #"(?i)(?:in|on)\s+(?:my\s+)?"#,
                options: [.regularExpression]
            ) {
                let stripped = matched[inner.upperBound...]
                let suffix = stripped.replacingOccurrences(
                    of: #"(?i)\s+calend(?:a|e)r$"#,
                    with: "",
                    options: .regularExpression
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                if !suffix.isEmpty { return suffix }
            }
        }
        return nil
    }

    private enum LowContextDomain: String, Sendable {
        case mail
        case notes
        case reminders
        case contacts
        case messages
        case map
        case location
        case shortcuts
        case calendar

        var toolNameGlobs: [String] {
            switch self {
            case .mail:
                return ["email_*", "mail_*", "gmail_*"]
            case .notes:
                return ["notes_*"]
            case .reminders:
                return ["reminders_*"]
            case .contacts:
                return ["contacts_*"]
            case .messages:
                return ["messages_*"]
            case .map:
                return ["map_*"]
            case .location:
                return ["location_*"]
            case .shortcuts:
                return ["shortcuts_*"]
            case .calendar:
                return ["calendar_*"]
            }
        }
    }

    private static func directLowContextSafeDefaultRequest(
        _ text: String,
        discovery: MCPToolsDiscoveryResult?
    ) -> (server: String, domain: LowContextDomain)? {
        guard let server = preferredLowContextServer(discovery) else { return nil }
        let q = text.lowercased()

        // Safety: do not auto-route potentially destructive intents.
        let destructive =
            q.contains("delete")
                || q.contains("remove")
                || q.contains("trash")
                || q.contains("move ")
                || q.contains("archive")
                || q.contains("send")
                || q.contains("reply")
                || q.contains("forward")
                || q.contains("update")
                || q.contains("edit ")
        if destructive { return nil }

        // Safe defaults: “do I have / list / show / search / any” style queries.
        let wantsBrowse =
            q.contains("do i have")
                || q.contains("any ")
                || q.contains("list")
                || q.contains("show")
                || q.contains("search")
                || q.contains("find")
                || q.contains("where")
        guard wantsBrowse else { return nil }

        if q.contains("note") { return (server, .notes) }
        if q.contains("reminder") { return (server, .reminders) }
        if q.contains("email") || q.contains("mail") || q.contains("inbox") { return (server, .mail) }
        if q.contains("contact") { return (server, .contacts) }
        if q.contains("message") || q.contains("texts") || q.contains("imessage") { return (server, .messages) }
        if q.contains("map") || q.contains("near ") || q.contains("nearby") || q.contains("place") { return (server, .map) }
        if q.contains("where am i") || q.contains("my location") || q.contains("current location") { return (server, .location) }
        if q.contains("shortcut") || q.contains("shortcuts") { return (server, .shortcuts) }
        if q.contains("calendar") || q.contains("schedule") { return (server, .calendar) }
        return nil
    }

    private static func directLowContextNewEmailRequest(
        _ text: String,
        discovery: MCPToolsDiscoveryResult?
    ) -> String? {
        guard let server = preferredLowContextServer(discovery) else { return nil }
        let q = text.lowercased()
        guard q.contains("email") || q.contains("mail") || q.contains("inbox") else { return nil }
        // Route only “check inbox / new mail / unread” intents to avoid hijacking generic questions.
        let wantsCheckOrNew =
            q.contains("check")
                || q.contains("inbox")
                || q.contains("new")
                || q.contains("unread")
                || q.contains("latest")
                || q.contains("recent")
                || q.contains("any new")
        guard wantsCheckOrNew else { return nil }
        return server
    }

    private static func directLowContextNotesRequest(
        _ text: String,
        discovery: MCPToolsDiscoveryResult?
    ) -> String? {
        guard let server = preferredLowContextServer(discovery) else { return nil }
        let q = text.lowercased()
        guard q.contains("notes") || q.contains("note") else { return nil }
        // Route only “do I have notes / list notes / search notes” intents.
        let wantsListOrSearch =
            q.contains("do i have")
                || q.contains("any notes")
                || q.contains("list")
                || q.contains("show")
                || q.contains("search")
                || q.contains("find")
        guard wantsListOrSearch else { return nil }
        return server
    }

    private static func directLowContextTodayRemindersRequest(
        _ text: String,
        discovery: MCPToolsDiscoveryResult?
    ) -> String? {
        guard let server = preferredLowContextServer(discovery) else { return nil }
        let q = text.lowercased()
        guard q.contains("reminder") || q.contains("reminders") else { return nil }
        // Route only “today reminders / reminders for today” intents.
        let wantsToday =
            q.contains("today")
                || q.contains("due today")
                || q.contains("for today")
                || q.contains("this morning")
                || q.contains("this afternoon")
                || q.contains("tonight")
        guard wantsToday else { return nil }
        return server
    }

    private static func isDirectMacuseListCalendarsIntent(_ text: String) -> Bool {
        let query = text.lowercased()
        guard query.contains("macuse") else { return false }
        guard query.contains("calendar") else { return false }
        return query.contains("list calendar")
            || query.contains("list the calendar")
            || query.contains("list calendars")
            || query.contains("list the calendars")
            || query.contains("show calendars")
            || query.contains("show the calendars")
    }

    private static func runDirectMacuseListCalendars(
        mcpServersFile: String,
        discovery: MCPToolsDiscoveryResult?,
        autoFollowActions: Bool
    ) async throws -> String {
        _ = try await MCPToolCaller.call(
            mcpServersFile: mcpServersFile,
            mcpServer: "macuse",
            tool: "get_tool_definitions",
            arguments: ["names": ["calendar_*"]]
        )
        let result = try await MCPToolCaller.call(
            mcpServersFile: mcpServersFile,
            mcpServer: "macuse",
            tool: "call_tool_by_name",
            arguments: [
                "name": "calendar_list_calendars",
                "arguments": [:],
            ]
        )
        var blocks = ["[Tool result macuse.call_tool_by_name]\n\(result)"]
        if autoFollowActions {
            let followups = try await followReturnedToolActions(
                from: result,
                server: "macuse",
                mcpServersFile: mcpServersFile,
                discovery: discovery,
                toolEnabled: { _, _ in true }
            )
            blocks.append(contentsOf: followups)
        }
        return McpToolTranscriptFormatting.toolMessageDisplayString(rawContent: blocks.joined(separator: "\n\n"))
    }

    private static func runDirectLowContextTodayCalendarEvents(
        mcpServersFile: String,
        server: String,
        calendarHint: String?,
        discovery: MCPToolsDiscoveryResult?,
        autoFollowActions: Bool
    ) async throws -> String {
        _ = try await MCPToolCaller.call(
            mcpServersFile: mcpServersFile,
            mcpServer: server,
            tool: "get_tool_definitions",
            arguments: ["names": ["calendar_*"]]
        )

        let (startISO, endISO) = todayISO8601Range()
        let searchResult = try await MCPToolCaller.call(
            mcpServersFile: mcpServersFile,
            mcpServer: server,
            tool: "call_tool_by_name",
            arguments: [
                "name": "calendar_search_events",
                "arguments": [
                    "start_date": startISO,
                    "end_date": endISO,
                ],
            ]
        )

        if let hint = calendarHint, !hint.isEmpty {
            let calendarsResult = try await MCPToolCaller.call(
                mcpServersFile: mcpServersFile,
                mcpServer: server,
                tool: "call_tool_by_name",
                arguments: [
                    "name": "calendar_list_calendars",
                    "arguments": [:],
                ]
            )
            guard let calendar = bestMatchingCalendar(from: calendarsResult, hint: hint) else {
                throw GrizzyMCPNativeError.toolExecutionFailed("No calendar found matching `\(hint)`.")
            }
            let body = filteredEventSummary(from: searchResult, calendar: calendar)
            return wrapDirectCalendarToolOutput(server: server, body: body)
        }

        var blocks = ["[Tool result \(server).call_tool_by_name]\n\(searchResult)"]
        if autoFollowActions {
            let followups = try await followReturnedToolActions(
                from: searchResult,
                server: server,
                mcpServersFile: mcpServersFile,
                discovery: discovery,
                toolEnabled: { _, _ in true }
            )
            blocks.append(contentsOf: followups)
        }
        return McpToolTranscriptFormatting.toolMessageDisplayString(rawContent: blocks.joined(separator: "\n\n"))
    }

    /// Returns (startOfToday, startOfTomorrow) in ISO-8601 (local timezone).
    /// Some MCP calendar tools require concrete ISO strings, not relative tokens like "today" or "+1d".
    private static func todayISO8601Range() -> (String, String) {
        let cal = Calendar.current
        let now = Date()
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)
        let fmt = ISO8601DateFormatter()
        fmt.timeZone = TimeZone.current
        fmt.formatOptions = [.withInternetDateTime]
        return (fmt.string(from: start), fmt.string(from: end))
    }

    private static func runDirectLowContextNewEmail(
        mcpServersFile: String,
        server: String,
        discovery: MCPToolsDiscoveryResult?,
        autoFollowActions: Bool
    ) async throws -> String {
        // Step 1: discover only email-ish tools first (faster, less noise).
        let defsResult = try await MCPToolCaller.call(
            mcpServersFile: mcpServersFile,
            mcpServer: server,
            tool: "get_tool_definitions",
            arguments: ["names": ["email_*", "mail_*", "gmail_*"]]
        )

        var chosen = bestMatchingEmailTool(fromGetToolDefinitionsResult: defsResult)
        if chosen == nil {
            // Fall back to full definitions if the server doesn’t use these prefixes.
            let allDefs = try await MCPToolCaller.call(
                mcpServersFile: mcpServersFile,
                mcpServer: server,
                tool: "get_tool_definitions",
                arguments: ["names": ["*"]]
            )
            chosen = bestMatchingEmailTool(fromGetToolDefinitionsResult: allDefs)
        }

        guard let chosen else {
            throw GrizzyMCPNativeError.toolExecutionFailed("No email tools discovered for server `\(server)`.")
        }

        // Step 2: run the chosen tool with best-effort safe defaults.
        let toolResult = try await MCPToolCaller.call(
            mcpServersFile: mcpServersFile,
            mcpServer: server,
            tool: "call_tool_by_name",
            arguments: [
                "name": chosen.name,
                "arguments": chosen.arguments,
            ]
        )

        var blocks = ["[Tool result \(server).call_tool_by_name]\n\(toolResult)"]
        if autoFollowActions {
            let followups = try await followReturnedToolActions(
                from: toolResult,
                server: server,
                mcpServersFile: mcpServersFile,
                discovery: discovery,
                toolEnabled: { _, _ in true }
            )
            blocks.append(contentsOf: followups)
        }
        return McpToolTranscriptFormatting.toolMessageDisplayString(rawContent: blocks.joined(separator: "\n\n"))
    }

    private static func runDirectLowContextSafeDefault(
        mcpServersFile: String,
        server: String,
        domain: LowContextDomain,
        userText: String
    ) async throws -> String {
        // Cursor-like: always retrieve schemas for the relevant domain first.
        let defsResult = try await MCPToolCaller.call(
            mcpServersFile: mcpServersFile,
            mcpServer: server,
            tool: "get_tool_definitions",
            arguments: ["names": domain.toolNameGlobs]
        )

        let descriptors = toolDescriptorsFromGetToolDefinitionsResult(defsResult)
        guard let toolCall = bestMatchingSafeToolForDomain(domain: domain, userText: userText, descriptors: descriptors) else {
            throw GrizzyMCPNativeError.toolExecutionFailed("No safe \(domain.rawValue) tool discovered for server `\(server)`.")
        }

        let toolResult = try await MCPToolCaller.call(
            mcpServersFile: mcpServersFile,
            mcpServer: server,
            tool: "call_tool_by_name",
            arguments: [
                "name": toolCall.name,
                "arguments": toolCall.arguments,
            ]
        )

        return McpToolTranscriptFormatting.toolMessageDisplayString(rawContent: "[Tool result \(server).call_tool_by_name]\n\(toolResult)")
    }

    private struct LowContextSafeToolChoice {
        let name: String
        let requiredKeys: Set<String>
        let arguments: [String: Any]
    }

    private static func bestMatchingSafeToolForDomain(
        domain: LowContextDomain,
        userText: String,
        descriptors: [LowContextToolDescriptor]
    ) -> LowContextSafeToolChoice? {
        guard !descriptors.isEmpty else { return nil }
        let q = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = userText.lowercased()

        func isPotentiallyDestructive(_ name: String) -> Bool {
            let n = name.lowercased()
            return n.contains("delete")
                || n.contains("move")
                || n.contains("update")
                || n.contains("cancel")
                || n.contains("reschedule")
                || n.contains("send")
                || n.contains("reply")
                || n.contains("forward")
                || n.contains("compose")
                || n.contains("write")
                || n.contains("create")
        }

        func requiresIdentifiers(_ requiredKeys: Set<String>) -> Bool {
            // Anything that needs references/ids is not a safe “browse” default.
            return requiredKeys.contains("reference")
                || requiredKeys.contains("references")
                || requiredKeys.contains("reminder")
                || requiredKeys.contains("note_id")
                || requiredKeys.contains("deep_link")
                || requiredKeys.contains("attachment_index")
        }

        func allowedKeys(for domain: LowContextDomain) -> Set<String> {
            switch domain {
            case .mail:
                return Set(["account", "mailbox", "is_read", "has_attachments", "is_replied", "start_date", "end_date", "sender", "query", "search_in", "limit", "offset"])
            case .notes:
                return Set(["account", "folder", "query", "tags", "has_checklist", "is_locked", "is_pinned", "limit", "offset"])
            case .reminders:
                return Set(["query", "lists", "completed", "start_date", "end_date", "limit", "offset"])
            case .contacts:
                // contacts_search has "query"; contacts_get_all has none.
                return Set(["query"])
            case .messages:
                return Set(["query", "limit", "offset"])
            case .map:
                return Set(["query", "limit"])
            case .location:
                return Set([])
            case .shortcuts:
                return Set([])
            case .calendar:
                return Set(["start_date", "end_date", "query", "calendar", "limit", "offset"])
            }
        }

        func canSatisfy(_ desc: LowContextToolDescriptor) -> Bool {
            if isPotentiallyDestructive(desc.name) { return false }
            if requiresIdentifiers(desc.requiredKeys) { return false }
            if desc.requiredKeys.isEmpty {
                // If schema doesn't specify required keys, still avoid obviously unsafe names.
                return !isPotentiallyDestructive(desc.name)
            }
            return desc.requiredKeys.isSubset(of: allowedKeys(for: domain))
        }

        func score(_ tool: LowContextToolDescriptor) -> Int {
            let n = tool.name.lowercased()
            var s = 0
            // Prefer list/search primitives.
            if n.contains("search") { s += 10 }
            if n.contains("list") { s += 8 }
            if n.contains("get_all") { s += 6 }
            if n.contains("get") { s += 1 }
            // Domain-specific favorites.
            switch domain {
            case .mail:
                if n.contains("mail_search_messages") { s += 30 }
                if n.contains("get_messages") { s -= 20 }
            case .notes:
                if n.contains("notes_search_notes") { s += 30 }
                if n.contains("read") || n.contains("open") { s -= 20 }
            case .reminders:
                if n.contains("reminders_search_reminders") { s += 30 }
                if n.contains("list_lists") { s += 10 }
            case .contacts:
                if n.contains("contacts_search") { s += 20 }
                if n.contains("contacts_get_all") { s += 15 }
            case .messages:
                if n.contains("messages_search_messages") { s += 25 }
                if n.contains("messages_search_chats") { s += 18 }
            case .map:
                if n.contains("map_search_places") { s += 25 }
                if n.contains("directions") || n.contains("eta") { s -= 5 }
            case .location:
                if n.contains("location_get_current") { s += 25 }
            case .shortcuts:
                if n.contains("shortcuts_list") { s += 25 }
            case .calendar:
                if n.contains("calendar_search_events") { s += 25 }
                if n.contains("list_calendars") { s += 8 }
            }

            // If user explicitly said "list", prefer list tools.
            if lower.contains("list") || lower.contains("show") {
                if n.contains("list") { s += 3 }
            }
            // If user said "search/find", prefer search tools.
            if lower.contains("search") || lower.contains("find") {
                if n.contains("search") { s += 3 }
            }
            return s
        }

        func defaultArguments(for tool: LowContextToolDescriptor) -> [String: Any] {
            let name = tool.name.lowercased()
            var args: [String: Any] = [:]

            // Generic pagination
            if tool.requiredKeys.contains("limit") { args["limit"] = 25 }
            if tool.requiredKeys.contains("offset") { args["offset"] = 0 }
            if tool.requiredKeys.contains("query") {
                // Avoid sending the entire prompt when it is essentially “list ...”.
                if lower.contains("search") || lower.contains("find") {
                    args["query"] = q
                }
            }

            // Domain/tool specifics
            if name.contains("mail_search_messages") {
                args["mailbox"] = "Inbox"
                args["is_read"] = false
                args["limit"] = args["limit"] ?? 25
                args["offset"] = args["offset"] ?? 0
                args["start_date"] = "-30d"
            } else if name.contains("notes_search_notes") {
                args["limit"] = args["limit"] ?? 20
                args["offset"] = args["offset"] ?? 0
            } else if name.contains("reminders_search_reminders") {
                let wantsToday = lower.contains("today") || lower.contains("due today") || lower.contains("for today")
                args["completed"] = false
                args["limit"] = args["limit"] ?? 50
                args["offset"] = args["offset"] ?? 0
                if wantsToday {
                    args["start_date"] = "today"
                    args["end_date"] = "+1d"
                } else {
                    args["start_date"] = "-7d"
                    args["end_date"] = "+30d"
                }
            } else if name.contains("messages_search_messages") {
                args["query"] = q
                args["limit"] = args["limit"] ?? 25
                args["offset"] = args["offset"] ?? 0
            } else if name.contains("map_search_places") {
                args["query"] = q
                args["limit"] = args["limit"] ?? 10
            } else if name.contains("calendar_search_events") {
                // Prefer concrete ISO-8601 dates for calendar tools (many reject relative tokens).
                let wantsToday = lower.contains("today")
                let (startISO, endISO) = todayISO8601Range()
                args["start_date"] = startISO
                if wantsToday {
                    args["end_date"] = endISO
                } else {
                    // 7-day window from start-of-today.
                    let cal = Calendar.current
                    let startDate = cal.startOfDay(for: Date())
                    let end = cal.date(byAdding: .day, value: 7, to: startDate)
                        ?? startDate.addingTimeInterval(7 * 24 * 60 * 60)
                    let fmt = ISO8601DateFormatter()
                    fmt.timeZone = TimeZone.current
                    fmt.formatOptions = [.withInternetDateTime]
                    args["end_date"] = fmt.string(from: end)
                }
            }

            return args
        }

        let candidates: [(LowContextToolDescriptor, Int)] = descriptors.compactMap { d in
            guard canSatisfy(d) else { return nil }
            return (d, score(d))
        }.sorted { $0.1 > $1.1 }

        guard let best = candidates.first, best.1 > 0 else { return nil }
        return LowContextSafeToolChoice(
            name: best.0.name,
            requiredKeys: best.0.requiredKeys,
            arguments: defaultArguments(for: best.0)
        )
    }

    // MARK: - Testing hooks
    // We keep the production selector private, but expose a narrow seam for unit tests
    // so we can lock in the “Cursor-like” behavior (prefer safe search/list tools).
    internal static func __testing_pickSafeToolName(
        domain: String,
        userText: String,
        getToolDefinitionsResult: String
    ) -> String? {
        let d: LowContextDomain?
        switch domain.lowercased() {
        case "mail": d = .mail
        case "notes": d = .notes
        case "reminders": d = .reminders
        case "contacts": d = .contacts
        case "messages": d = .messages
        case "map": d = .map
        case "location": d = .location
        case "shortcuts": d = .shortcuts
        case "calendar": d = .calendar
        default: d = nil
        }
        guard let d else { return nil }
        let descriptors = toolDescriptorsFromGetToolDefinitionsResult(getToolDefinitionsResult)
        return bestMatchingSafeToolForDomain(domain: d, userText: userText, descriptors: descriptors)?.name
    }

    private static func runDirectLowContextNotes(
        mcpServersFile: String,
        server: String
    ) async throws -> String {
        // Cursor-like: discover Notes tools, then call the safest “search/list” primitive.
        _ = try await MCPToolCaller.call(
            mcpServersFile: mcpServersFile,
            mcpServer: server,
            tool: "get_tool_definitions",
            arguments: ["names": ["notes_*"]]
        )
        let toolResult = try await MCPToolCaller.call(
            mcpServersFile: mcpServersFile,
            mcpServer: server,
            tool: "call_tool_by_name",
            arguments: [
                "name": "notes_search_notes",
                "arguments": [
                    "limit": 20,
                    "offset": 0,
                ],
            ]
        )
        return McpToolTranscriptFormatting.toolMessageDisplayString(rawContent: "[Tool result \(server).call_tool_by_name]\n\(toolResult)")
    }

    private static func runDirectLowContextTodayReminders(
        mcpServersFile: String,
        server: String
    ) async throws -> String {
        _ = try await MCPToolCaller.call(
            mcpServersFile: mcpServersFile,
            mcpServer: server,
            tool: "get_tool_definitions",
            arguments: ["names": ["reminders_*"]]
        )
        let toolResult = try await MCPToolCaller.call(
            mcpServersFile: mcpServersFile,
            mcpServer: server,
            tool: "call_tool_by_name",
            arguments: [
                "name": "reminders_search_reminders",
                "arguments": [
                    "start_date": "today",
                    "end_date": "+1d",
                    "completed": false,
                    "limit": 50,
                    "offset": 0,
                ],
            ]
        )
        return McpToolTranscriptFormatting.toolMessageDisplayString(rawContent: "[Tool result \(server).call_tool_by_name]\n\(toolResult)")
    }

    private struct LowContextEmailToolChoice {
        let name: String
        let requiredKeys: Set<String>
        let arguments: [String: Any]
    }

    private static func bestMatchingEmailTool(fromGetToolDefinitionsResult raw: String) -> LowContextEmailToolChoice? {
        let descriptors = toolDescriptorsFromGetToolDefinitionsResult(raw)
        guard !descriptors.isEmpty else { return nil }

        func isUnsafeWithoutSchema(_ toolName: String) -> Bool {
            // Cursor-style safety: if we don't know required args, avoid tools that likely require IDs/references
            // or have side effects. Prefer search/list style tools.
            let n = toolName.lowercased()
            if n.contains("get_attachment") || n.contains("attachment") { return true }
            if n.contains("get_thread") || n.contains("thread") { return true }
            if n.contains("open_message") || n.contains("open") { return true }
            if n.contains("get_messages") || n.contains("get_message") { return true }
            if n.contains("reply") || n.contains("forward") || n.contains("compose") { return true }
            if n.contains("delete") || n.contains("move") || n.contains("update") { return true }
            return false
        }

        // Only accept tools whose required keys are fully satisfiable by our safe defaults.
        func canSatisfy(_ req: Set<String>, toolName: String) -> Bool {
            // Hard reject “attachment” style tools unless explicitly requested.
            if req.contains("reference") || req.contains("references") || req.contains("attachment_index") { return false }
            // Common optional-only tools.
            if req.isEmpty {
                // If schema didn't tell us required args, treat risky tools as unsatisfiable.
                return !isUnsafeWithoutSchema(toolName)
            }
            // We can fill these.
            let allowed = Set([
                "query",
                "limit",
                "offset",
                "mailbox",
                "account",
                "unread",
                "since",
                "after",
                "before",
                "folder",
                "label",
                "is_read",
                "is_replied",
                "has_attachments",
                "start_date",
                "end_date",
                "sender",
                "search_in",
            ])
            return req.isSubset(of: allowed)
        }

        func score(_ name: String) -> Int {
            let n = name.lowercased()
            var s = 0
            if n.contains("email") || n.contains("mail") || n.contains("gmail") { s += 10 }
            if n.contains("unread") || n.contains("new") { s += 8 }
            if n.contains("inbox") { s += 6 }
            if n.contains("list") { s += 5 }
            if n.contains("search") || n.contains("query") { s += 5 }
            if n.contains("get") || n.contains("fetch") { s += 2 }
            if n.contains("messages") || n.contains("message") { s += 3 }
            // Strongly prefer the Cursor-like primitive for “check my email”.
            if n.contains("mail_search_messages") { s += 25 }
            // Strongly avoid attachment/content extraction unless asked.
            if n.contains("attachment") { s -= 100 }
            // Avoid tools that likely need a message id / reference.
            if n.contains("get_messages") || n.contains("open_message") || n.contains("get_thread") { s -= 40 }
            // Avoid destructive actions unless explicitly asked.
            if n.contains("delete") || n.contains("trash") || n.contains("archive") || n.contains("send") { s -= 50 }
            return s
        }

        let candidates: [(LowContextToolDescriptor, Int)] = descriptors.compactMap { desc in
            guard canSatisfy(desc.requiredKeys, toolName: desc.name) else { return nil }
            return (desc, score(desc.name))
        }.sorted { $0.1 > $1.1 }

        guard let best = candidates.first, best.1 > 0 else { return nil }

        let args = emailDefaultArguments(requiredKeys: best.0.requiredKeys, toolName: best.0.name)
        return LowContextEmailToolChoice(
            name: best.0.name,
            requiredKeys: best.0.requiredKeys,
            arguments: args
        )
    }

    private static func emailDefaultArguments(requiredKeys: Set<String>, toolName: String) -> [String: Any] {
        var args: [String: Any] = [:]
        let name = toolName.lowercased()

        // Provider/tool-specific “check inbox for unread” defaults.
        // Even when keys are optional, it’s better UX to supply a consistent unread search.
        if name == "mail_search_messages" || name.hasSuffix(".mail_search_messages") || name.contains("mail_search_messages") {
            args["mailbox"] = "Inbox"
            args["is_read"] = false
            args["limit"] = 25
            args["offset"] = 0
            // macuse defaults to last 7 days; a slightly wider window is usually what users mean by “check my inbox”.
            args["start_date"] = "-30d"
            return args
        }

        // Inbox-ish defaults (these are optional on many servers; only set when required).
        if requiredKeys.contains("mailbox") || requiredKeys.contains("folder") || requiredKeys.contains("label") {
            // Don’t guess provider-specific labels unless forced.
            args["mailbox"] = "INBOX"
            args["folder"] = "INBOX"
            args["label"] = "INBOX"
        }
        if requiredKeys.contains("limit") {
            args["limit"] = 20
        }
        if requiredKeys.contains("offset") {
            args["offset"] = 0
        }
        if requiredKeys.contains("unread") {
            args["unread"] = true
        }
        if requiredKeys.contains("query") {
            // Provider-agnostic-ish: if the tool name implies unread/new, request that.
            if name.contains("unread") || name.contains("new") {
                args["query"] = "unread"
            } else {
                args["query"] = "inbox"
            }
        }
        // account left unset unless required (rare); better to let server default.
        return args
    }

    /// Best-effort extraction of tool names from the low-context `get_tool_definitions` response.
    private static func toolNamesFromGetToolDefinitionsResult(_ raw: String) -> [String] {
        let normalized = GrizzyMCPValueConversion.normalize(rawToolResult: raw)
        let candidates = normalized.structuredItems

        func extract(from value: JSONValue) -> [String] {
            switch value {
            case .object(let obj):
                // Common shapes:
                // - { data: { tools: [ { name: "..." } ] } }
                // - { tools: [ { name: "..." } ] }
                if case .object(let data)? = obj["data"] {
                    if let names = extractToolNames(from: data["tools"]) { return names }
                }
                if let names = extractToolNames(from: obj["tools"]) { return names }
                // Sometimes tool defs are keyed objects: { tools: { "toolName": {...}, ... } }
                if case .object(let toolsObj)? = obj["tools"] {
                    return toolsObj.keys.sorted()
                }
                return []
            case .array(let arr):
                return arr.flatMap(extract)
            default:
                return []
            }
        }

        func extractToolNames(from value: JSONValue?) -> [String]? {
            guard let value else { return nil }
            switch value {
            case .array(let arr):
                let names = arr.compactMap { item -> String? in
                    guard case .object(let toolObj) = item else { return nil }
                    if case .string(let name)? = toolObj["name"] { return name }
                    if case .string(let name)? = toolObj["tool"] { return name }
                    return nil
                }
                return names.isEmpty ? nil : names
            default:
                return nil
            }
        }

        let names = candidates.flatMap(extract)
        // De-dupe, stable-ish.
        var seen = Set<String>()
        var out: [String] = []
        for n in names {
            let t = n.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !seen.contains(t) else { continue }
            seen.insert(t)
            out.append(t)
        }
        return out
    }

    private struct LowContextToolDescriptor: Sendable, Equatable {
        let name: String
        let requiredKeys: Set<String>
    }

    private static func toolDescriptorsFromGetToolDefinitionsResult(_ raw: String) -> [LowContextToolDescriptor] {
        let normalized = GrizzyMCPValueConversion.normalize(rawToolResult: raw)
        let candidates = normalized.structuredItems

        func requiredKeys(from schema: JSONValue?) -> Set<String> {
            guard let schema else { return [] }
            switch schema {
            case .object(let obj):
                if case .array(let req)? = obj["required"] {
                    let keys = req.compactMap { item -> String? in
                        guard case .string(let s) = item else { return nil }
                        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        return t.isEmpty ? nil : t
                    }
                    return Set(keys)
                }
                return []
            default:
                return []
            }
        }

        func extract(from value: JSONValue) -> [LowContextToolDescriptor] {
            switch value {
            case .object(let obj):
                // Common shapes:
                // - { data: { tools: [ { name, inputSchema|input_schema } ] } }
                // - { tools: [ { name, inputSchema|input_schema } ] }
                // - { tools: { "toolName": { inputSchema... }, ... } }
                if case .object(let data)? = obj["data"] {
                    if let arr = extractToolDescriptors(from: data["tools"]) { return arr }
                }
                if let arr = extractToolDescriptors(from: obj["tools"]) { return arr }
                if case .object(let toolsObj)? = obj["tools"] {
                    return toolsObj.keys.sorted().map { LowContextToolDescriptor(name: $0, requiredKeys: []) }
                }
                return []
            case .array(let arr):
                return arr.flatMap(extract)
            default:
                return []
            }
        }

        func extractToolDescriptors(from value: JSONValue?) -> [LowContextToolDescriptor]? {
            guard let value else { return nil }
            switch value {
            case .array(let arr):
                let out = arr.compactMap { item -> LowContextToolDescriptor? in
                    guard case .object(let toolObj) = item else { return nil }
                    let name: String?
                    if case .string(let s)? = toolObj["name"] { name = s }
                    else if case .string(let s)? = toolObj["tool"] { name = s }
                    else { name = nil }
                    guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    let schema = toolObj["inputSchema"] ?? toolObj["input_schema"] ?? toolObj["input_schema_json"] ?? toolObj["schema"]
                    let req = requiredKeys(from: schema)
                    return LowContextToolDescriptor(name: name, requiredKeys: req)
                }
                return out.isEmpty ? nil : out
            default:
                return nil
            }
        }

        var seen = Set<String>()
        var out: [LowContextToolDescriptor] = []
        for c in candidates.flatMap(extract) {
            let n = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !n.isEmpty, !seen.contains(n) else { continue }
            seen.insert(n)
            out.append(LowContextToolDescriptor(name: n, requiredKeys: c.requiredKeys))
        }
        return out
    }

    private static func wrapDirectCalendarToolOutput(server: String, body: String) -> String {
        McpToolTranscriptFormatting.toolMessageDisplayString(
            rawContent: "[Tool result \(server).call_tool_by_name]\n\(body)"
        )
    }

    private static func bestMatchingCalendar(from raw: String, hint: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["data"] as? [String: Any],
              let calendars = payload["calendars"] as? [[String: Any]]
        else {
            return nil
        }
        let normalizedHint = hint.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = calendars.first(where: {
            stringValue($0["title"])?.lowercased() == normalizedHint
                || stringValue($0["id"])?.lowercased() == normalizedHint
        }) {
            return exact
        }
        return calendars.first(where: {
            stringValue($0["title"])?.lowercased().contains(normalizedHint) == true
                || stringValue($0["source"])?.lowercased().contains(normalizedHint) == true
                || stringValue($0["id"])?.lowercased().contains(normalizedHint) == true
        })
    }

    private static func filteredEventSummary(from raw: String, calendar: [String: Any]) -> String {
        let calendarTitle = stringValue(calendar["title"]) ?? "selected calendar"
        let calendarID = stringValue(calendar["id"])?.lowercased()
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["data"] as? [String: Any],
              let events = payload["events"] as? [[String: Any]]
        else {
            return raw
        }

        let filtered = events.filter { event in
            if let calendarText = stringValue(event["calendar"])?.lowercased() {
                return calendarText.contains(calendarTitle.lowercased())
                    || (calendarID.map { calendarText.contains($0) } ?? false)
            }
            if let calendarObject = event["calendar"] as? [String: Any] {
                let eventTitle = stringValue(calendarObject["title"])?.lowercased()
                let eventID = stringValue(calendarObject["id"])?.lowercased()
                return eventTitle == calendarTitle.lowercased() || eventID == calendarID
            }
            return false
        }

        if filtered.isEmpty {
            return "No events found today in \(calendarTitle)."
        }

        var lines = ["\(filtered.count) event(s) today in \(calendarTitle):"]
        for event in filtered.prefix(20) {
            let title = stringValue(event["title"]) ?? stringValue(event["name"]) ?? "Untitled"
            let start = stringValue(event["start_date"]) ?? stringValue(event["start"]) ?? "Unknown time"
            lines.append("- \(title) — \(start)")
        }
        return lines.joined(separator: "\n")
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text == "nil" ? nil : text
    }

    private static func followReturnedToolActions(
        from rawResult: String,
        server: String,
        mcpServersFile: String,
        discovery: MCPToolsDiscoveryResult?,
        toolEnabled: (String, String) -> Bool
    ) async throws -> [String] {
        let actions = GrizzyMCPValueConversion.returnedActionCalls(from: rawResult)
        guard !actions.isEmpty else { return [] }
        let merged = discovery?.mergingPythonInternalTools()
        let hasLowContextMetaTools =
            ToolCallValidation.isKnownTool(server: server, tool: "get_tool_definitions", discovery: merged)
            && ToolCallValidation.isKnownTool(server: server, tool: "call_tool_by_name", discovery: merged)
        var blocks: [String] = []
        for action in actions.prefix(2) {
            if action.hasPlaceholderArguments() {
                GrizzyClawLog.info("MCP follow-up skipped: placeholder arguments in returned action \(action.tool)")
                continue
            }
            let rawTool = action.tool.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawTool.isEmpty else { continue }
            let execTool: String
            let execArgs: [String: Any]
            let label: String
            if ToolCallValidation.isKnownTool(server: server, tool: rawTool, discovery: merged) {
                execTool = rawTool
                execArgs = action.jsonObjectArguments()
                label = rawTool
            } else if hasLowContextMetaTools, rawTool != "get_tool_definitions", rawTool != "call_tool_by_name" {
                execTool = "call_tool_by_name"
                execArgs = ["name": rawTool, "arguments": action.jsonObjectArguments()]
                label = "call_tool_by_name"
            } else {
                continue
            }
            guard toolEnabled(server, execTool) else { continue }
            let result = try await MCPToolCaller.call(
                mcpServersFile: mcpServersFile,
                mcpServer: server,
                tool: execTool,
                arguments: execArgs
            )
            blocks.append("[Tool result \(server).\(label)]\n\(result)")
        }
        return blocks
    }

    private static func shouldAutoListCalendarsAfterLowContextDiscovery(_ messages: [ChatMessage]) -> Bool {
        let query = heuristicSearchQueryFromSession(messages)?.lowercased() ?? ""
        guard query.contains("calendar") else { return false }
        return query.contains("list calendar")
            || query.contains("list the calendar")
            || query.contains("list calendars")
            || query.contains("list the calendars")
            || query.contains("show calendars")
            || query.contains("show the calendars")
    }

    private static func lowContextCalendarListFollowupArguments(
        server: String,
        tool: String
    ) -> [String: Any]? {
        guard tool == "get_tool_definitions" else { return nil }
        guard server.lowercased().contains("macuse") else { return nil }
        return [
            "name": "calendar_list_calendars",
            "arguments": [:],
        ]
    }

    private static func isCancellationLikeError(_ error: Error) -> Bool {
        if let u = error as? URLError, u.code == .cancelled { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled { return true }
        return false
    }

    private func persistSession(workspaceId: String?, config: UserConfigSnapshot) {
        guard config.sessionPersistence, let wid = workspaceId else { return }
        let turns = messages.map { PersistedChatTurn(role: $0.role.rawValue, content: $0.content) }
        try? SessionPersistence.saveTurns(turns, workspaceId: wid)
        SessionPersistence.recordSessionFileModificationDate(workspaceId: wid)
    }

    private static func mapTurns(_ turns: [PersistedChatTurn]) -> [ChatMessage] {
        turns.compactMap { t in
            let role = ChatMessage.Role(rawValue: t.role) ?? .user
            return ChatMessage(role: role, content: t.content)
        }
    }

    private static func stream(
        for resolved: ResolvedLLMStreamRequest,
        conversation: [ChatMessage]
    ) -> AsyncThrowingStream<String, Error> {
        switch resolved {
        case .openAICompatible(let p):
            return OpenAICompatibleStreamClient.stream(parameters: p, conversation: conversation)
        case .anthropic(let p):
            return AnthropicStreamClient.stream(parameters: p, conversation: conversation)
        case .lmStudioV1(let p):
            return LMStudioV1StreamClient.stream(parameters: p, conversation: conversation)
        case .mlx(let p):
            return MLXStreamClient.stream(parameters: p, conversation: conversation)
        }
    }

    private static func formatError(_ error: Error) -> String {
        LLMErrorHints.formattedMessage(for: error)
    }

    /// One completion for `UsageDashboardDialog` benchmark — does not modify `messages` (parity with Python `process_message` stream).
    public func runUsageBenchmark(
        workspaceStore: WorkspaceStore,
        configStore: ConfigStore,
        selectedWorkspaceId: String?,
        guiLlmOverride: GuiChatPreferences.LLM? = nil
    ) async -> UsageBenchmarkOutcome {
        let secrets = UserConfigLoader.loadSecretsWithKeychainLenient()
        guard let idx = workspaceStore.index else {
            return .failed("No workspaces file found.")
        }
        let wid = selectedWorkspaceId ?? idx.activeWorkspaceId
        guard let wid else {
            return .failed("No active workspace.")
        }
        guard let ws = idx.workspaces.first(where: { $0.id == wid }) else {
            return .failed("Workspace not found.")
        }
        let maxMsgs = ws.config?.int(forKey: "max_session_messages") ?? configStore.snapshot.maxSessionMessages
        let resolved: ResolvedLLMStreamRequest
        do {
            resolved = try ChatParameterResolver.resolve(
                user: configStore.snapshot,
                routing: configStore.routingExtras,
                secrets: secrets,
                workspace: ws,
                guiLlmOverride: guiLlmOverride,
                systemPromptSuffix: nil
            )
        } catch {
            return .failed(Self.formatError(error))
        }
        let convo: [ChatMessage] = [ChatMessage(role: .user, content: "Reply with exactly: OK")]
        let trimmed = SessionTrim.trim(convo, maxMessages: maxMsgs)
        let t0 = CFAbsoluteTimeGetCurrent()
        var out = ""
        do {
            for try await piece in Self.stream(for: resolved, conversation: trimmed) {
                out += piece
            }
        } catch {
            return .failed(Self.formatError(error))
        }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        let approx = out.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }.count
        return .succeeded(elapsedMs: elapsedMs, approxTokens: max(approx, 0))
    }

    /// Writes the current transcript via a save panel (Markdown or JSON).
    public func exportConversationViaPanel() {
        guard !messages.isEmpty else {
            statusLine = "Nothing to export."
            return
        }
        ChatExportPresenter.presentSavePanel(messages: messages) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.infoLine = message
                self.statusLine = nil
            case .failure(let err):
                self.statusLine = err.localizedDescription
                GrizzyClawLog.error("export failed: \(err.localizedDescription)")
            }
        }
    }
}
