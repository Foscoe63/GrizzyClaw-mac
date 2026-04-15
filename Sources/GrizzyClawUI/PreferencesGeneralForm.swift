import GrizzyClawCore
import SwiftUI

/// General tab layout matching GrizzyClaw (Qt): label column + controls, group box, spinbox-style numbers.
struct PreferencesGeneralForm: View {
    @ObservedObject var doc: ConfigYamlDocument
    @EnvironmentObject var statusBarStore: StatusBarStore

    var body: some View {
        ScrollView {
            GroupBox {
                VStack(alignment: .leading, spacing: 18) { // Match form.setSpacing(18)
                    labeledTextFieldRow("App Name:", text: doc.bindingString("app_name", default: "GrizzyClaw"))
                    labeledToggleRow("Enable Debug Mode", isOn: doc.bindingBool("debug", default: false))
                    labeledPickerRow(
                        "Default Provider:",
                        selection: defaultProviderBinding,
                        tags: defaultProviderPickerTags
                    )
                    Text("Configure models in the 'LLM Providers' tab")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                        .padding(.leading, PreferencesTheme.labelColumnWidth + 12)
                    intStepperRow(
                        "Max Context:",
                        value: doc.bindingInt("max_context_length", default: 4000),
                        range: 1000...100_000,
                        step: 1000
                    )
                    labeledPickerRow(
                        "Log Level:",
                        selection: doc.bindingString("log_level", default: "INFO"),
                        tags: ["None", "DEBUG", "INFO", "WARNING", "ERROR"]
                    )
                    intStepperRow(
                        "Max tool-use rounds:",
                        value: doc.bindingInt("max_agentic_iterations", default: 10),
                        range: 3...30,
                        step: 1
                    )
                    intStepperRow(
                        "Memory retrieval limit:",
                        value: doc.bindingInt("memory_retrieval_limit", default: 10),
                        range: 3...50,
                        step: 1
                    )
                    labeledToggleRow(
                        "Prompt to continue or answer after tool results",
                        isOn: doc.bindingBool("agent_reflection_enabled", default: true)
                    )
                    labeledToggleRow(
                        "Ask for PLAN before tools (complex tasks)",
                        isOn: doc.bindingBool("agent_plan_before_tools", default: false)
                    )
                    intStepperRow(
                        "Tool result max chars:",
                        value: doc.bindingInt("agent_tool_result_max_chars", default: 4000),
                        range: 500...20_000,
                        step: 1
                    )
                    labeledToggleRow("Retry hint when a tool fails", isOn: doc.bindingBool("agent_retry_on_tool_failure", default: true))
                    intStepperRow(
                        "Max session messages:",
                        value: doc.bindingInt("max_session_messages", default: 20),
                        range: 5...200,
                        step: 1
                    )
                    .help("Context window: older turns are trimmed; tool-heavy turns get priority slots.")
                }
                .padding(2)
            } label: {
                Text("General")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .groupBoxStyle(GrizzyClawGroupBoxStyle())
            .padding(.horizontal, 40) // Match container_layout.setContentsMargins(40, 24, 40, 24)
            .padding(.vertical, 24)
            .onChange(of: doc.root.keys.count) {
                statusBarStore.showMessage("Settings saved", timeoutMs: 3000)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PreferencesPanelChromeBackground())
    }

    // MARK: - Provider picker (Python `GeneralTab`)

    private func yamlDefaultProviderToDisplay(_ yaml: String) -> String {
        switch yaml {
        case "lmstudio_v1": return "lmstudio-v1"
        case "opencode_zen": return "opencode-zen"
        default: return yaml
        }
    }

    private func displayDefaultProviderToYaml(_ display: String) -> String {
        switch display {
        case "lmstudio-v1": return "lmstudio_v1"
        case "opencode-zen": return "opencode_zen"
        default: return display
        }
    }

    private func defaultProviderPickerOptions() -> [String] {
        var base = ["ollama", "lmstudio", "openai", "anthropic", "openrouter", "cursor", "opencode-zen"]
        #if arch(arm64)
        base.insert("mlx", at: 2)
        #endif
        if doc.bool("lmstudio_v1_enabled", default: false) {
            base.append("lmstudio-v1")
        }
        let customUrl = doc.optionalString("custom_provider_url").trimmingCharacters(in: .whitespacesAndNewlines)
        if !customUrl.isEmpty {
            let name = doc.string("custom_provider_name", default: "custom").trimmingCharacters(in: .whitespacesAndNewlines)
            base.append(name.isEmpty ? "custom" : name)
        }
        return base
    }

    private var defaultProviderPickerTags: [String] {
        let opts = defaultProviderPickerOptions()
        let cur = yamlDefaultProviderToDisplay(doc.string("default_llm_provider", default: "ollama"))
        if opts.contains(cur) { return opts }
        return [cur] + opts
    }

    private var defaultProviderBinding: Binding<String> {
        Binding(
            get: { yamlDefaultProviderToDisplay(doc.string("default_llm_provider", default: "ollama")) },
            set: { doc.set("default_llm_provider", value: displayDefaultProviderToYaml($0)) }
        )
    }

    // MARK: - Rows (Qt-like)

    @ViewBuilder
    private func labeledToggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text("") // Label column spacer (empty text)
                .frame(width: PreferencesTheme.labelColumnWidth, alignment: .trailing)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.checkbox)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func labeledTextFieldRow(_ title: String, text: Binding<String>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 13))
                .frame(width: PreferencesTheme.labelColumnWidth, alignment: .trailing)
                .foregroundStyle(.primary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func labeledPickerRow(_ title: String, selection: Binding<String>, tags: [String]) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 13))
                .frame(width: PreferencesTheme.labelColumnWidth, alignment: .trailing)
                .foregroundStyle(.primary)
            Picker("", selection: selection) {
                ForEach(tags, id: \.self) { t in
                    Text(t).tag(t)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, -8)
        }
    }

    @ViewBuilder
    private func intStepperRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 13))
                .frame(width: PreferencesTheme.labelColumnWidth, alignment: .trailing)
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                TextField("", value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: PreferencesTheme.numericFieldWidth)
                    .multilineTextAlignment(.trailing)
                Stepper("", value: value, in: range, step: step)
                    .labelsHidden()
            }
            Spacer(minLength: 0)
        }
    }
}

/// Group box with subtle border (Qt `QGroupBox`-like); fills adapt to Light/Dark.
private struct GrizzyClawGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        GrizzyClawGroupBoxChrome(configuration: configuration)
    }
}

private struct GrizzyClawGroupBoxChrome: View {
    let configuration: GroupBoxStyleConfiguration
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label
                .padding(.bottom, 2)
            configuration.content
                .padding(24) // Match Qt-like margins
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: PreferencesTheme.groupCornerRadius, style: .continuous)
                        .fill(PreferencesTheme.groupFill(colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PreferencesTheme.groupCornerRadius, style: .continuous)
                        .stroke(PreferencesTheme.groupStroke(colorScheme), lineWidth: 1)
                )
        }
    }
}
