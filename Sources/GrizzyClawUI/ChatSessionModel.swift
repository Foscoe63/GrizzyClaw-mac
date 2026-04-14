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

    private var streamTask: Task<Void, Never>?
    private var coalesceAssistantCanvasEpochTask: Task<Void, Never>?

    public init() {}

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
        let secrets: UserConfigSecrets
        do {
            secrets = try UserConfigLoader.loadSecretsWithKeychain()
        } catch {
            GrizzyClawLog.error("secrets load failed (connection test): \(error.localizedDescription)")
            secrets = .empty
        }
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

        let secrets: UserConfigSecrets
        do {
            secrets = try UserConfigLoader.loadSecretsWithKeychain()
        } catch {
            GrizzyClawLog.error("secrets load failed (send): \(error.localizedDescription)")
            secrets = .empty
        }

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

        let mcpSuffix = MCPSystemPromptAugmentor.mcpSuffix(discovery: filtered) { srv, tool in
            guiChatPrefs.isToolOn(server: srv, tool: tool)
        }
        let skillSuffix = SkillPromptAugmentor.skillsSuffix(
            enabledSkillIDs: ws.config?.stringArray(forKey: "enabled_skills") ?? []
        )
        let canvasSuffix = CanvasPromptAugmentor.suffix()
        let combinedPromptSuffix = [mcpSuffix, skillSuffix, canvasSuffix]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let systemPromptSuffix: String? = combinedPromptSuffix.isEmpty ? nil : combinedPromptSuffix

        messages.append(ChatMessage(role: .user, content: text))

        var toolRound = 0
        let maxToolRounds = 5

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

            let trimmedSession = SessionTrim.trim(messages, maxMessages: maxMsgs)
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
            let jsonBodies = ToolCallCommandParsing.findToolCallJsonObjects(in: rawAssistant)
            if jsonBodies.isEmpty {
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

            var parts: [String] = []
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
                    let r = try await MCPToolCaller.call(
                        mcpServersFile: userSnap.mcpServersFile,
                        mcpServer: canonMcp,
                        tool: canonTool,
                        arguments: args
                    )
                    parts.append("[Tool result \(canonMcp).\(canonTool)]\n\(r)")
                } catch {
                    parts.append("[Tool error]\n\(error.localizedDescription)")
                }
            }

            if parts.isEmpty {
                break
            }

            var toolUserMsg = parts.joined(separator: "\n\n")
            toolUserMsg += McpToolTranscriptFormatting.llmFollowUpInstructionSuffix
            messages.append(ChatMessage(role: .tool, content: toolUserMsg))
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
        let secrets: UserConfigSecrets
        do {
            secrets = try UserConfigLoader.loadSecretsWithKeychain()
        } catch {
            return .failed(error.localizedDescription)
        }
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
