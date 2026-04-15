import GrizzyClawCore
import SwiftUI

/// Parity with Python `SchedulerDialog` (`grizzyclaw/gui/scheduler_dialog.py`): `scheduled_tasks.json`, cron presets, MCP post-action, timeout in config.yaml.
public struct SchedulerMainView: View {
    @ObservedObject var scheduledTasksStore: ScheduledTasksStore
    @ObservedObject var configStore: ConfigStore
    var theme: String

    @Environment(\.colorScheme) private var colorScheme

    @State private var statusText = "Loading..."
    @State private var runTimeoutSeconds: Int = 300
    @State private var selectedTaskId: String?
    @State private var lastSelectedTaskId: String?

    @State private var nameField = ""
    @State private var cronField = ""
    @State private var messageField = ""
    @State private var cronPresetIndex = 0
    @State private var mcpServerField = ""
    @State private var mcpToolField = ""
    @State private var mcpArgsText = ""

    @State private var mcpServers: [String] = []
    @State private var mcpToolsForServer: [String] = []
    @State private var mcpDiscoveryMap: [String: [MCPToolDescriptor]] = [:]

    @State private var infoAlertTitle = ""
    @State private var infoAlertMessage = ""
    @State private var showInfoAlert = false
    @State private var confirmDeleteTaskId: String?

    private static let cronPresets: [(label: String, cron: String)] = [
        ("Custom", ""),
        ("Every minute (*/1 * * * *)", "*/1 * * * *"),
        ("Every 5 minutes (*/5 * * * *)", "*/5 * * * *"),
        ("Every 30 minutes (*/30 * * * *)", "*/30 * * * *"),
        ("Every hour (0 * * * *)", "0 * * * *"),
        ("Every 2 hours (0 */2 * * *)", "0 */2 * * *"),
        ("Daily at 9 AM (0 9 * * *)", "0 9 * * *"),
        ("Daily at noon (0 12 * * *)", "0 12 * * *"),
        ("Daily at 6 PM (0 18 * * *)", "0 18 * * *"),
        ("Weekly Monday 9 AM (0 9 * * 1)", "0 9 * * 1"),
        ("Monthly 1st at midnight (0 0 1 * *)", "0 0 1 * *"),
    ]

    private var isDark: Bool {
        AppearanceTheme.isEffectivelyDark(theme: theme, colorScheme: colorScheme)
    }

    private var palette: (fg: Color, summaryBg: Color, border: Color, accent: Color) {
        if isDark {
            return (
                Color.white,
                Color(red: 0.18, green: 0.18, blue: 0.18),
                Color(red: 0.23, green: 0.23, blue: 0.24),
                Color(red: 0.04, green: 0.52, blue: 1.0)
            )
        }
        return (
            Color(red: 0.11, green: 0.11, blue: 0.12),
            Color(red: 0.96, green: 0.97, blue: 0.98),
            Color(red: 0.90, green: 0.90, blue: 0.92),
            Color(red: 0, green: 0.48, blue: 1)
        )
    }

    public init(
        scheduledTasksStore: ScheduledTasksStore,
        configStore: ConfigStore,
        theme: String
    ) {
        self.scheduledTasksStore = scheduledTasksStore
        self.configStore = configStore
        self.theme = theme
    }

    public var body: some View {
        let p = palette
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Scheduled Tasks")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(p.fg)

                Text(statusText)
                    .font(.system(size: 14))
                    .foregroundStyle(p.fg)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(p.summaryBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                GroupBox("Scheduler settings") {
                    HStack {
                        Text("Run timeout:")
                        Stepper(value: $runTimeoutSeconds, in: 0...3600, step: 1) {
                            Text("\(runTimeoutSeconds) s")
                        }
                        .help("Hard timeout for a single scheduled task run. 0 disables the timeout (not recommended).")
                        Spacer()
                        Button("💾 Save scheduler settings") {
                            saveSchedulerSettings()
                        }
                    }
                }

                GroupBox {
                    List(selection: $selectedTaskId) {
                        ForEach(scheduledTasksStore.tasks) { task in
                            Text(taskListLine(task: task))
                                .tag(Optional(task.taskId))
                        }
                    }
                    .frame(minHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(p.border, lineWidth: 1)
                    )
                } label: {
                    Text("Tasks")
                }

                GroupBox("Create New Task") {
                    LabeledContent("Task Name:") {
                        TextField("e.g., Daily Email Check", text: $nameField)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Schedule:") {
                        HStack {
                            Picker("", selection: $cronPresetIndex) {
                                ForEach(Self.cronPresets.indices, id: \.self) { i in
                                    Text(Self.cronPresets[i].label).tag(i)
                                }
                            }
                            .labelsHidden()
                            .frame(minWidth: 220)
                            .onChange(of: cronPresetIndex) { _, new in
                                if new > 0, new < Self.cronPresets.count {
                                    cronField = Self.cronPresets[new].cron
                                }
                            }
                            TextField("* * * * * (min hour day month weekday)", text: $cronField)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    LabeledContent("Message:") {
                        TextField("What should happen when this task runs?", text: $messageField)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                GroupBox("Post result to MCP tool (optional)") {
                    LabeledContent("MCP server:") {
                        HStack {
                            TextField("e.g. mcp-obsidian-advanced", text: $mcpServerField)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: mcpServerField) {
                                    syncMcpToolsForServer()
                                }
                            if !mcpServers.isEmpty {
                                Menu("Pick…") {
                                    ForEach(mcpServers, id: \.self) { s in
                                        Button(s) {
                                            mcpServerField = s
                                            syncMcpToolsForServer()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    LabeledContent("Tool name:") {
                        HStack {
                            TextField("e.g. obsidian_put_file", text: $mcpToolField)
                                .textFieldStyle(.roundedBorder)
                            if !mcpToolsForServer.isEmpty {
                                Menu("Pick…") {
                                    ForEach(mcpToolsForServer, id: \.self) { t in
                                        Button(t) { mcpToolField = t }
                                    }
                                }
                            }
                        }
                    }
                    LabeledContent("Arguments (JSON):") {
                        TextEditor(text: $mcpArgsText)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(minHeight: 70)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(p.border, lineWidth: 1))
                    }
                    HStack {
                        Button("🧩 Insert args template") {
                            insertArgsTemplate()
                        }
                        .help("Insert a starter JSON template with {{result}}, {{task_name}}, {{message}}, {{date}} placeholders.")
                        Spacer()
                    }
                }

                buttonRow()
            }
            .padding(20)
        }
        .onAppear {
            runTimeoutSeconds = max(0, min(3600, configStore.snapshot.scheduledTaskRunTimeoutSeconds))
            refreshStatus()
            loadMcpChoices()
        }
        .onChange(of: scheduledTasksStore.tasks) {
            refreshStatus()
        }
        .onChange(of: scheduledTasksStore.disabledTaskIds) {
            refreshStatus()
        }
        .onChange(of: selectedTaskId) { _, new in
            applySelection(taskId: new)
        }
        .alert(infoAlertTitle, isPresented: $showInfoAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(infoAlertMessage)
        }
        .confirmationDialog(
            "Delete this scheduled task?",
            isPresented: Binding(
                get: { confirmDeleteTaskId != nil },
                set: { if !$0 { confirmDeleteTaskId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = confirmDeleteTaskId {
                    deleteTask(id: id)
                }
                confirmDeleteTaskId = nil
            }
            Button("Cancel", role: .cancel) {
                confirmDeleteTaskId = nil
            }
        }
    }

    @ViewBuilder
    private func buttonRow() -> some View {
        HStack(spacing: 10) {
            Button("➕ Create Task") {
                createTask()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button("💾 Save") {
                saveSelectedTask()
            }
            .disabled(selectedTaskId == nil)
            .buttonStyle(.borderedProminent)
            .tint(Color(nsColor: .controlAccentColor))

            Button("▶ Start") {
                startSelected()
            }
            .disabled(lastSelectedTaskId == nil)
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Button("⏸ Stop") {
                stopSelected()
            }
            .disabled(lastSelectedTaskId == nil)
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Button("🔄 Refresh") {
                scheduledTasksStore.reload()
                refreshStatus()
                reselect(taskId: lastSelectedTaskId)
            }

            Button("▶ Run now") {
                runNowInfo()
            }
            .disabled(lastSelectedTaskId == nil)
            .buttonStyle(.borderedProminent)
            .tint(.purple)

            Button("✏️ Edit") {
                if let id = lastSelectedTaskId ?? selectedTaskId {
                    selectedTaskId = id
                }
            }

            Button("🗑️ Delete Selected") {
                if let id = lastSelectedTaskId ?? selectedTaskId {
                    confirmDeleteTaskId = id
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }

    private func refreshStatus() {
        let total = scheduledTasksStore.tasks.count
        let enabled = scheduledTasksStore.tasks.filter { scheduledTasksStore.isEnabled(taskId: $0.taskId) }.count
        statusText =
            "Total Tasks: \(total) | Enabled: \(enabled) | Execution: Python agent (native app edits scheduled_tasks.json; the agent runs tasks on schedule)"
    }

    private func taskListLine(task: ScheduledTaskRecord) -> String {
        let on = scheduledTasksStore.isEnabled(taskId: task.taskId)
        let statusIcon = on ? "✅" : "❌"
        let nextStr: String
        let countdown: String
        if on, let next = CronNextRun.nextDate(cron: task.cron, from: Date()) {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyy-MM-dd'T'HH:mm"
            nextStr = f.string(from: next)
            let now = Date()
            let delta = next.timeIntervalSince(now)
            if delta > 0 {
                if delta < 60 {
                    countdown = " (next in <1 min)"
                } else if delta < 3600 {
                    countdown = " (next in \(Int(delta / 60)) min)"
                } else if delta < 86400 {
                    countdown = " (next in \(Int(delta / 3600)) h)"
                } else {
                    countdown = " (next in \(Int(delta / 86400)) d)"
                }
            } else {
                countdown = ""
            }
        } else {
            nextStr = "N/A"
            countdown = ""
        }
        return "\(statusIcon) \(task.name) | Cron: \(task.cron) | Next: \(nextStr)\(countdown) | Runs: —"
    }

    private func applySelection(taskId: String?) {
        guard let taskId,
              let task = scheduledTasksStore.tasks.first(where: { $0.taskId == taskId })
        else {
            lastSelectedTaskId = nil
            return
        }
        lastSelectedTaskId = taskId
        nameField = task.name
        cronField = task.cron
        messageField = task.message
        if let pa = task.mcpPostAction {
            mcpServerField = pa.mcp
            mcpToolField = pa.tool
            mcpArgsText = encodeMcpArgs(pa.arguments)
        } else {
            mcpServerField = ""
            mcpToolField = ""
            mcpArgsText = ""
        }
        syncMcpToolsForServer()
        let cron = task.cron.trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = Self.cronPresets.firstIndex(where: { $0.cron == cron }), idx > 0 {
            cronPresetIndex = idx
        } else {
            cronPresetIndex = 0
        }
    }

    private func encodeMcpArgs(_ args: [String: JSONValue]?) -> String {
        guard let args, !args.isEmpty else { return "" }
        do {
            let data = try JSONEncoder().encode(JSONValue.object(args))
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func loadMcpChoices() {
        Task {
            let path = configStore.snapshot.mcpServersFile
            let result = try? await MCPToolsDiscovery.discover(mcpServersFile: path)
            let servers = (result?.servers.keys.sorted() ?? [])
            let map = result?.servers ?? [:]
            await MainActor.run {
                mcpDiscoveryMap = map
                mcpServers = servers
                syncMcpToolsForServer()
            }
        }
    }

    private func syncMcpToolsForServer() {
        let server = mcpServerField.trimmingCharacters(in: .whitespacesAndNewlines)
        if !server.isEmpty, let pairs = mcpDiscoveryMap[server] {
            mcpToolsForServer = pairs.map(\.name).sorted()
        } else {
            mcpToolsForServer = []
        }
    }

    private func insertArgsTemplate() {
        mcpArgsText = """
        {
          "filepath": "Scheduled/{{task_name}}.md",
          "content": "{{result}}"
        }
        """
    }

    private func mcpPostActionFromForm() throws -> MCPPostActionRecord? {
        let m = mcpServerField.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = mcpToolField.trimmingCharacters(in: .whitespacesAndNewlines)
        if m.isEmpty || t.isEmpty { return nil }
        let raw = mcpArgsText.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return MCPPostActionRecord(mcp: m, tool: t, arguments: nil)
        }
        guard let data = raw.data(using: .utf8) else {
            throw NSError(domain: "GrizzyClaw", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8"])
        }
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(let dict) = decoded else {
            throw NSError(domain: "GrizzyClaw", code: 2, userInfo: [NSLocalizedDescriptionKey: "Arguments must be a JSON object"])
        }
        return MCPPostActionRecord(mcp: m, tool: t, arguments: dict)
    }

    private func saveSchedulerSettings() {
        if let err = configStore.saveScheduledTaskRunTimeout(seconds: runTimeoutSeconds) {
            infoAlertTitle = "Error"
            infoAlertMessage = err
            showInfoAlert = true
        } else {
            infoAlertTitle = "Saved"
            infoAlertMessage = "Scheduler settings saved."
            showInfoAlert = true
        }
    }

    private func createTask() {
        let name = nameField.trimmingCharacters(in: .whitespacesAndNewlines)
        let cron = cronField.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = messageField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            presentInfo(title: "Missing Name", message: "Please enter a task name.")
            return
        }
        guard !cron.isEmpty else {
            presentInfo(title: "Missing Schedule", message: "Please enter a cron expression.")
            return
        }
        guard !message.isEmpty else {
            presentInfo(title: "Missing Message", message: "Please enter a task message.")
            return
        }
        do {
            let mcp = try mcpPostActionFromForm()
            try scheduledTasksStore.createTask(name: name, cron: cron, message: message, mcpPostAction: mcp)
            nameField = ""
            cronField = ""
            messageField = ""
            mcpServerField = ""
            mcpToolField = ""
            mcpArgsText = ""
            cronPresetIndex = 0
            presentInfo(title: "Task Created", message: "✅ Task created and saved to scheduled_tasks.json.")
        } catch {
            presentInfo(title: "Error", message: error.localizedDescription)
        }
    }

    private func saveSelectedTask() {
        guard let id = selectedTaskId ?? lastSelectedTaskId else {
            presentInfo(title: "No Selection", message: "Select a task to save.")
            return
        }
        let name = nameField.trimmingCharacters(in: .whitespacesAndNewlines)
        let cron = cronField.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = messageField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            presentInfo(title: "Missing Name", message: "Enter a task name.")
            return
        }
        guard !cron.isEmpty else {
            presentInfo(title: "Missing Schedule", message: "Enter a cron expression.")
            return
        }
        guard !message.isEmpty else {
            presentInfo(title: "Missing Message", message: "Enter a task message.")
            return
        }
        do {
            let mcp = try mcpPostActionFromForm()
            try scheduledTasksStore.updateTask(taskId: id, name: name, cron: cron, message: message, mcpPostAction: mcp)
            presentInfo(title: "Saved", message: "✅ Task updated.")
        } catch {
            presentInfo(title: "Error", message: error.localizedDescription)
        }
    }

    private func startSelected() {
        guard let id = lastSelectedTaskId ?? selectedTaskId else {
            presentInfo(title: "No Selection", message: "Select a task first, then click Start.")
            return
        }
        scheduledTasksStore.setScheduleEnabled(taskId: id, enabled: true)
        refreshStatus()
        reselect(taskId: id)
    }

    private func stopSelected() {
        guard let id = lastSelectedTaskId ?? selectedTaskId else {
            presentInfo(title: "No Selection", message: "Select a task first, then click Stop.")
            return
        }
        scheduledTasksStore.setScheduleEnabled(taskId: id, enabled: false)
        refreshStatus()
        reselect(taskId: id)
    }

    private func reselect(taskId: String?) {
        guard let taskId else { return }
        selectedTaskId = taskId
    }

    private func deleteTask(id: String) {
        do {
            try scheduledTasksStore.deleteTask(taskId: id)
            if selectedTaskId == id {
                selectedTaskId = nil
                lastSelectedTaskId = nil
            }
            refreshStatus()
            presentInfo(title: "Deleted", message: "✅ Task removed from scheduled_tasks.json.")
        } catch {
            presentInfo(title: "Error", message: error.localizedDescription)
        }
    }

    private func runNowInfo() {
        presentInfo(
            title: "Run now",
            message:
                "Running a task immediately executes the Python GrizzyClaw agent on that task’s message. Use the Python app with the agent running, or ask the model to call the grizzyclaw tool run_scheduled_task with this task’s id."
        )
    }

    private func presentInfo(title: String, message: String) {
        infoAlertTitle = title
        infoAlertMessage = message
        showInfoAlert = true
    }
}
