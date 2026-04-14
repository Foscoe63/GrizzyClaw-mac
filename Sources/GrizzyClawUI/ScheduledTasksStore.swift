import Combine
import Foundation
import GrizzyClawCore
import SwiftUI

/// Loads and mutates `~/.grizzyclaw/scheduled_tasks.json` (Python `AgentCore.scheduled_tasks_db` + `_save_scheduled_tasks`).
/// `enabled` / `disabled` state matches Python: in-memory only (not persisted; reload enables all tasks).
@MainActor
public final class ScheduledTasksStore: ObservableObject {
    @Published public private(set) var tasks: [ScheduledTaskRecord] = []
    /// Task IDs that are disabled for schedule (Python `CronScheduler.disable_task` — not written to JSON).
    @Published public private(set) var disabledTaskIds: Set<String> = []
    @Published public private(set) var loadError: String?
    @Published public private(set) var saveError: String?

    public init() {}

    public func reload() {
        loadError = nil
        saveError = nil
        do {
            try GrizzyClawPaths.ensureUserDataDirectoryExists()
            tasks = try ScheduledTasksPersistence.load()
            disabledTaskIds = disabledTaskIds.intersection(Set(tasks.map(\.taskId)))
        } catch {
            loadError = error.localizedDescription
            tasks = []
            GrizzyClawLog.error("scheduled_tasks load failed: \(error.localizedDescription)")
        }
    }

    private func persist() throws {
        saveError = nil
        try ScheduledTasksPersistence.save(tasks)
    }

    public func createTask(
        name: String,
        cron: String,
        message: String,
        mcpPostAction: MCPPostActionRecord?
    ) throws {
        let suffix = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()
        let taskId = "task_\(suffix)"
        let rec = ScheduledTaskRecord(
            taskId: taskId,
            userId: "gui_user",
            name: name,
            cron: cron,
            message: message,
            mcpPostAction: mcpPostAction
        )
        tasks.append(rec)
        try persist()
    }

    public func updateTask(
        taskId: String,
        name: String,
        cron: String,
        message: String,
        mcpPostAction: MCPPostActionRecord?
    ) throws {
        guard let i = tasks.firstIndex(where: { $0.taskId == taskId }) else { return }
        tasks[i].name = name
        tasks[i].cron = cron
        tasks[i].message = message
        tasks[i].mcpPostAction = mcpPostAction
        try persist()
    }

    public func deleteTask(taskId: String) throws {
        tasks.removeAll { $0.taskId == taskId }
        disabledTaskIds.remove(taskId)
        try persist()
    }

    public func setScheduleEnabled(taskId: String, enabled: Bool) {
        if enabled {
            disabledTaskIds.remove(taskId)
        } else {
            disabledTaskIds.insert(taskId)
        }
    }

    public func isEnabled(taskId: String) -> Bool {
        !disabledTaskIds.contains(taskId)
    }
}
