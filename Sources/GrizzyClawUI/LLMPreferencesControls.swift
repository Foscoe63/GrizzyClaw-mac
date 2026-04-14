import GrizzyClawCore
import SwiftUI

// MARK: - Workspace API key providers (comma-separated YAML ↔ checkboxes, parity with Python)

extension ConfigYamlDocument {
    fileprivate func workspaceProviderTokens() -> Set<String> {
        string("workspace_api_key_providers", default: "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: Set<String>()) { $0.insert($1) }
    }

    fileprivate func setWorkspaceProviderTokens(_ tokens: Set<String>) {
        let sorted = tokens.filter { !$0.isEmpty }.sorted()
        set("workspace_api_key_providers", value: sorted.joined(separator: ","))
    }

    /// Toggle a single provider id in `workspace_api_key_providers`.
    func setWorkspaceProviderEnabled(id: String, enabled: Bool) {
        var s = workspaceProviderTokens()
        if enabled {
            s.insert(id)
        } else {
            s.remove(id)
        }
        setWorkspaceProviderTokens(s)
    }

    func isWorkspaceProviderEnabled(id: String) -> Bool {
        workspaceProviderTokens().contains(id)
    }

    /// Custom checkbox: on if list contains `custom` **or** the current custom display name (Python `LLMTab`).
    func isCustomWorkspaceProviderEnabled() -> Bool {
        let wap = workspaceProviderTokens()
        let name = string("custom_provider_name", default: "custom").trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = name.isEmpty ? "custom" : name
        return wap.contains("custom") || wap.contains(effective)
    }

    func setCustomWorkspaceProviderEnabled(_ enabled: Bool) {
        var s = workspaceProviderTokens()
        let name = string("custom_provider_name", default: "custom").trimmingCharacters(in: .whitespacesAndNewlines)
        let effective = name.isEmpty ? "custom" : name
        s.remove("custom")
        s.remove(effective)
        if enabled {
            s.insert(effective)
        }
        setWorkspaceProviderTokens(s)
    }
}

// MARK: - Model row: editable field + quick-pick menu + refresh (Qt editable `QComboBox` parity)

struct LLMModelField: View {
    @ObservedObject var doc: ConfigYamlDocument
    let modelKey: String
    let defaultModel: String
    let seeds: [String]
    /// `nil` → menu shows `seeds` + current model; non-`nil` → last refresh result (may be empty — parent shows alert).
    @Binding var fetched: [String]?
    @Binding var isRefreshing: Bool
    let refresh: () async -> [String]

    private var modelBinding: Binding<String> {
        doc.bindingString(modelKey, default: defaultModel)
    }

    private var menuOptions: [String] {
        let base: [String]
        if let fetched {
            base = fetched
        } else {
            base = seeds
        }
        let cur = modelBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if cur.isEmpty { return base }
        if base.contains(cur) { return base }
        return [cur] + base
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            TextField("Model", text: modelBinding)
            Menu {
                ForEach(menuOptions, id: \.self) { opt in
                    Button(opt) {
                        doc.set(modelKey, value: opt)
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button("↻") {
                Task {
                    await MainActor.run { isRefreshing = true }
                    let result = await refresh()
                    await MainActor.run {
                        isRefreshing = false
                        fetched = result
                    }
                }
            }
            .disabled(isRefreshing)
            .help("Refresh available models")
        }
    }
}
