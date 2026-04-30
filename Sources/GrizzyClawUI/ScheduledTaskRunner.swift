import Combine
import Foundation
import GrizzyClawAgent
import GrizzyClawCore

/// Native in-process scheduler executor — replaces the Python agent's `CronScheduler`.
///
/// Ticks roughly every `tickInterval` seconds, computes the next fire time for every enabled task
/// using `CronNextRun` (`SwifCron`), and when a task is due runs its message through
/// `HeadlessLLMDispatcher` and (optionally) posts the result to an MCP tool via `MCPToolCaller`.
///
/// Status is in-memory only (not persisted); re-enabling a task resets its "last fired at" to now
/// so disabled periods don't accumulate a catch-up backlog.
@MainActor
public final class ScheduledTaskRunner: ObservableObject {
    public struct TaskRunState: Equatable, Sendable {
        public enum Status: String, Sendable, Equatable {
            case idle
            case running
            case success
            case failed
        }
        public var status: Status = .idle
        public var lastFiredAt: Date?
        public var lastCompletedAt: Date?
        public var lastError: String?
        public var lastReplyPreview: String?
        public var runCount: Int = 0
    }

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var lastTickAt: Date?
    @Published public private(set) var runStates: [String: TaskRunState] = [:]

    /// Per-task "last scheduled fire we already honored" — used to compute the *next* fire.
    /// Separate from `runStates` so a long-running task doesn't delay subsequent fires.
    private var lastScheduledFire: [String: Date] = [:]

    /// Background tick loop handle.
    private var tickTask: Task<Void, Never>?

    /// Granularity of the tick loop. 20s is fine for 1-minute cron resolution.
    private let tickInterval: TimeInterval = 20

    private let scheduledTasksStore: ScheduledTasksStore
    private let workspaceStore: WorkspaceStore
    private let configStore: ConfigStore
    private let guiChatPrefs: GuiChatPrefsStore

    private var cancellables = Set<AnyCancellable>()

    public init(
        scheduledTasksStore: ScheduledTasksStore,
        workspaceStore: WorkspaceStore,
        configStore: ConfigStore,
        guiChatPrefs: GuiChatPrefsStore
    ) {
        self.scheduledTasksStore = scheduledTasksStore
        self.workspaceStore = workspaceStore
        self.configStore = configStore
        self.guiChatPrefs = guiChatPrefs

        // When the enabled set flips, reset scheduling anchors for tasks that just came online so
        // they don't "catch up" on missed fires accumulated while disabled/stopped.
        scheduledTasksStore.$disabledTaskIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resyncAnchorsAfterEnabledChange()
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    /// Start the tick loop. Safe to call multiple times.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        anchorAllEnabledTasksToNow()
        GrizzyClawLog.info("ScheduledTaskRunner: started (tick=\(Int(tickInterval))s)")
        tickTask = Task { [weak self] in
            await self?.tickLoop()
        }
    }

    /// Stop the tick loop; in-flight task runs are allowed to finish.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        tickTask?.cancel()
        tickTask = nil
        GrizzyClawLog.info("ScheduledTaskRunner: stopped")
    }

    // MARK: - Manual execution

    /// Run a task immediately, off-schedule. Safe to call while the loop is running.
    public func runNow(taskId: String) {
        guard let task = scheduledTasksStore.tasks.first(where: { $0.taskId == taskId }) else {
            GrizzyClawLog.info("ScheduledTaskRunner.runNow: task \(taskId) not found")
            return
        }
        Task { [weak self] in
            await self?.execute(task: task, firedAt: Date(), isManual: true)
        }
    }

    // MARK: - Tick loop

    private func tickLoop() async {
        while !Task.isCancelled && isRunning {
            let now = Date()
            lastTickAt = now
            let tasks = scheduledTasksStore.tasks
            let disabled = scheduledTasksStore.disabledTaskIds

            for task in tasks {
                if disabled.contains(task.taskId) { continue }
                guard let anchor = lastScheduledFire[task.taskId] ?? firstAnchor(for: task) else {
                    continue
                }
                guard let next = CronNextRun.nextDate(cron: task.cron, from: anchor) else {
                    continue
                }
                if next <= now {
                    lastScheduledFire[task.taskId] = next
                    let captured = task
                    let fire = next
                    Task { [weak self] in
                        await self?.execute(task: captured, firedAt: fire, isManual: false)
                    }
                }
            }

            do {
                try await Task.sleep(nanoseconds: UInt64(tickInterval * 1_000_000_000))
            } catch {
                break
            }
        }
    }

    private func firstAnchor(for task: ScheduledTaskRecord) -> Date? {
        // Only seed on-demand for tasks that somehow missed `anchorAllEnabledTasksToNow()`.
        let now = Date()
        lastScheduledFire[task.taskId] = now
        return now
    }

    private func anchorAllEnabledTasksToNow() {
        let now = Date()
        let enabled = scheduledTasksStore.tasks.filter { !scheduledTasksStore.disabledTaskIds.contains($0.taskId) }
        for task in enabled {
            lastScheduledFire[task.taskId] = now
        }
    }

    private func resyncAnchorsAfterEnabledChange() {
        guard isRunning else { return }
        let now = Date()
        for task in scheduledTasksStore.tasks {
            if scheduledTasksStore.disabledTaskIds.contains(task.taskId) {
                lastScheduledFire.removeValue(forKey: task.taskId)
            } else if lastScheduledFire[task.taskId] == nil {
                lastScheduledFire[task.taskId] = now
            }
        }
    }

    // MARK: - Execution

    private func execute(task: ScheduledTaskRecord, firedAt: Date, isManual: Bool) async {
        var state = runStates[task.taskId] ?? TaskRunState()
        state.status = .running
        state.lastFiredAt = firedAt
        state.lastError = nil
        runStates[task.taskId] = state

        let timeout = max(0, configStore.snapshot.scheduledTaskRunTimeoutSeconds)
        let tag = isManual ? "runNow" : "cron"
        GrizzyClawLog.info("ScheduledTaskRunner[\(tag)]: running '\(task.name)' (id=\(task.taskId))")

        let reply: String
        do {
            reply = try await HeadlessLLMDispatcher.run(
                userMessage: task.message,
                history: [],
                workspaceStore: workspaceStore,
                configStore: configStore,
                guiChatPrefs: guiChatPrefs,
                options: HeadlessLLMDispatcher.Options(timeoutSeconds: timeout, historyLimit: 40)
            )
        } catch {
            var updated = runStates[task.taskId] ?? state
            updated.status = .failed
            updated.lastError = error.localizedDescription
            updated.lastCompletedAt = Date()
            updated.runCount += 1
            runStates[task.taskId] = updated
            GrizzyClawLog.error(
                "ScheduledTaskRunner[\(tag)]: task '\(task.name)' failed — \(error.localizedDescription)"
            )
            return
        }

        // Optional MCP post-action, mirroring Python `_run_scheduled_task_action`.
        var postActionError: String?
        if let post = task.mcpPostAction {
            do {
                try await runPostAction(post, for: task, reply: reply, firedAt: firedAt)
            } catch {
                postActionError = error.localizedDescription
                GrizzyClawLog.error(
                    "ScheduledTaskRunner[\(tag)]: MCP post-action failed for '\(task.name)' — \(error.localizedDescription)"
                )
            }
        }

        var updated = runStates[task.taskId] ?? state
        updated.status = postActionError == nil ? .success : .failed
        updated.lastError = postActionError
        updated.lastCompletedAt = Date()
        updated.lastReplyPreview = Self.previewOf(reply)
        updated.runCount += 1
        runStates[task.taskId] = updated

        GrizzyClawLog.info(
            "ScheduledTaskRunner[\(tag)]: task '\(task.name)' completed "
                + (postActionError == nil ? "ok" : "with post-action error")
        )
    }

    private func runPostAction(
        _ post: MCPPostActionRecord,
        for task: ScheduledTaskRecord,
        reply: String,
        firedAt: Date
    ) async throws {
        let substituted = substitutePlaceholders(
            in: post.arguments ?? [:],
            result: reply,
            taskName: task.name,
            message: task.message,
            firedAt: firedAt
        )
        let argsAny = try substituted.jsonSerializationValue() as? [String: Any] ?? [:]
        let mcpFile = configStore.snapshot.mcpServersFile
        _ = try await MCPToolCaller.call(
            mcpServersFile: mcpFile,
            mcpServer: post.mcp,
            tool: post.tool,
            arguments: argsAny
        )
    }

    // MARK: - Placeholder substitution ({{result}}, {{task_name}}, {{message}}, {{date}})

    private func substitutePlaceholders(
        in args: [String: JSONValue],
        result: String,
        taskName: String,
        message: String,
        firedAt: Date
    ) -> JSONValue {
        let iso = Self.isoFormatter.string(from: firedAt)
        let replacements: [String: String] = [
            "{{result}}": result,
            "{{task_name}}": taskName,
            "{{message}}": message,
            "{{date}}": iso,
        ]
        return substituteDeep(.object(args), replacements: replacements)
    }

    private func substituteDeep(_ value: JSONValue, replacements: [String: String]) -> JSONValue {
        switch value {
        case .object(let dict):
            var out: [String: JSONValue] = [:]
            for (k, v) in dict {
                out[k] = substituteDeep(v, replacements: replacements)
            }
            return .object(out)
        case .array(let arr):
            return .array(arr.map { substituteDeep($0, replacements: replacements) })
        case .string(let s):
            var replaced = s
            for (placeholder, value) in replacements {
                replaced = replaced.replacingOccurrences(of: placeholder, with: value)
            }
            return .string(replaced)
        case .int, .double, .bool, .null:
            return value
        }
    }

    // MARK: - Helpers

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func previewOf(_ reply: String) -> String {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 140 { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: 140)
        return String(trimmed[..<idx]) + "…"
    }
}
