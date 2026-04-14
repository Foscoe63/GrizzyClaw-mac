import GrizzyClawCore
import SwiftUI

/// Parity with Python `TriggersDialog` / `triggers.json`.
public struct AutomationTriggersMainView: View {
    @State private var rules: [AutomationTriggerRecord] = []
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var selectedId: String?

    @State private var newName = ""
    @State private var newEvent = "message"
    @State private var newCondType = "contains"
    @State private var newCondValue = ""
    @State private var newActionType = "agent_message"
    @State private var newActionConfigJSON = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Automation Triggers")
                .font(.title2.weight(.semibold))
                .padding(.bottom, 4)
            Text("Rules in ~/.grizzyclaw/triggers.json — same format as the Python app. The agent daemon evaluates them on message and other events.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Refresh") { reload() }
                Button("Delete selected", role: .destructive) { deleteSelected() }
                    .disabled(selectedId == nil)
                Spacer()
            }
            .padding(.bottom, 8)

            List(rules, id: \.id, selection: $selectedId) { r in
                Text(lineLabel(r))
            }
            .frame(minHeight: 180)

            GroupBox("Create trigger") {
                Form {
                    TextField("Name", text: $newName)
                    Picker("Event", selection: $newEvent) {
                        Text("message").tag("message")
                        Text("webhook").tag("webhook")
                        Text("schedule").tag("schedule")
                        Text("file_change").tag("file_change")
                        Text("git_event").tag("git_event")
                    }
                    HStack {
                        Picker("Condition", selection: $newCondType) {
                            Text("contains").tag("contains")
                            Text("matches").tag("matches")
                            Text("equals").tag("equals")
                            Text("path_matches").tag("path_matches")
                        }
                        .frame(minWidth: 140)
                        TextField("Pattern (empty = always)", text: $newCondValue)
                    }
                    Picker("Action", selection: $newActionType) {
                        Text("agent_message").tag("agent_message")
                        Text("webhook").tag("webhook")
                        Text("notify").tag("notify")
                    }
                    TextField("Action config JSON (e.g. {\"url\":\"https://…\"})", text: $newActionConfigJSON, axis: .vertical)
                        .lineLimit(2...6)
                        .font(.system(.body, design: .monospaced))
                    Button("Add trigger") { addTrigger() }
                        .keyboardShortcut(.defaultAction)
                }
                .formStyle(.grouped)
                .padding(4)
            }
        }
        .padding(20)
        .frame(minWidth: 650, minHeight: 500)
        .onAppear { reload() }
    }

    private func lineLabel(_ r: AutomationTriggerRecord) -> String {
        let on = r.enabled ? "✅" : "❌"
        var cond = ""
        if let c = r.condition {
            cond = " \(c.type)=\(jsonValueShort(c.value))"
        }
        return "\(on) \(r.name) | \(r.event)\(cond) → \(r.action.type)"
    }

    private func jsonValueShort(_ v: JSONValue) -> String {
        switch v {
        case .string(let s): return s.count > 40 ? String(s.prefix(40)) + "…" : s
        default: return String(describing: v)
        }
    }

    private func reload() {
        loadError = nil
        saveError = nil
        do {
            rules = try AutomationTriggersPersistence.load()
        } catch {
            loadError = error.localizedDescription
            rules = []
        }
    }

    private func addTrigger() {
        saveError = nil
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            saveError = "Enter a name."
            return
        }
        var condition: TriggerConditionDTO?
        let cv = newCondValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cv.isEmpty {
            condition = TriggerConditionDTO(type: newCondType, value: .string(cv))
        }
        var config: [String: JSONValue] = [:]
        let cfgRaw = newActionConfigJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cfgRaw.isEmpty {
            guard let data = cfgRaw.data(using: .utf8),
                  let obj = try? JSONDecoder().decode(JSONValue.self, from: data),
                  case .object(let dict) = obj
            else {
                saveError = "Action config must be JSON object, e.g. {\"url\":\"https://…\"}"
                return
            }
            config = dict
        }
        let action = TriggerActionDTO(type: newActionType, config: config)
        let id = String(UUID().uuidString.prefix(8))
        let rule = AutomationTriggerRecord(
            id: id,
            name: name,
            enabled: true,
            event: newEvent,
            description: "",
            condition: condition,
            action: action
        )
        var next = rules
        next.append(rule)
        persist(next)
        if saveError == nil {
            newName = ""
            newCondValue = ""
            newActionConfigJSON = ""
        }
    }

    private func deleteSelected() {
        guard let sid = selectedId else { return }
        saveError = nil
        let next = rules.filter { $0.id != sid }
        persist(next)
        selectedId = nil
    }

    private func persist(_ next: [AutomationTriggerRecord]) {
        do {
            try AutomationTriggersPersistence.save(next)
            rules = next
        } catch {
            saveError = error.localizedDescription
        }
    }
}
