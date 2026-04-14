import GrizzyClawCore
import SwiftUI

struct ConfigSummaryView: View {
    @ObservedObject var store: ConfigStore

    var body: some View {
        NavigationStack {
            Form {
                if let err = store.loadError {
                    Section {
                        GrizzyClawStatusBanner(text: err)
                    }
                }
                if store.snapshot.fileMissing {
                    Section {
                        Text("No config.yaml found. Use the Python app once, or add ~/.grizzyclaw/config.yaml.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("File") {
                    LabeledContent("Path") {
                        Text(store.snapshot.configPathDisplay)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
                Section("Appearance") {
                    LabeledContent("Theme", value: store.snapshot.theme)
                    LabeledContent("Font", value: store.snapshot.fontFamily)
                    LabeledContent("Font size") {
                        Text("\(store.snapshot.fontSize)")
                    }
                    Toggle("Compact mode", isOn: .constant(store.snapshot.compactMode))
                        .disabled(true)
                }
                Section("Default LLM") {
                    LabeledContent("Provider", value: store.snapshot.defaultLlmProvider)
                    LabeledContent("Model", value: store.snapshot.defaultModel)
                    LabeledContent("Max tokens") {
                        Text("\(store.snapshot.maxTokens)")
                    }
                    LabeledContent("Max session messages") {
                        Text("\(store.snapshot.maxSessionMessages)")
                    }
                    LabeledContent("Max context") {
                        Text("\(store.snapshot.maxContextLength)")
                    }
                    LabeledContent("Session persistence") {
                        Text(store.snapshot.sessionPersistence ? "On (chat saved under ~/.grizzyclaw/sessions/)" : "Off")
                            .font(.caption)
                    }
                }
                Section("Endpoints") {
                    LabeledContent("Ollama", value: store.snapshot.ollamaUrl)
                    LabeledContent("Ollama model", value: store.snapshot.ollamaModel)
                    LabeledContent("LM Studio", value: store.snapshot.lmstudioUrl)
                    LabeledContent("LM Studio model", value: store.snapshot.lmstudioModel)
                }
                Section("API keys (YAML + optional Keychain)") {
                    LabeledContent("OpenAI") { secretBadge(store.snapshot.hasOpenaiApiKey) }
                    LabeledContent("Anthropic") { secretBadge(store.snapshot.hasAnthropicApiKey) }
                    LabeledContent("OpenRouter") { secretBadge(store.snapshot.hasOpenrouterApiKey) }
                    Text(
                        "The native app loads keys from config.yaml, then overrides any field with a matching macOS Keychain item (service \(GrizzyClawKeychain.service), account name = YAML key, e.g. openai_api_key). Keychain values take precedence and are never shown here."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Section("MCP & agent tooling") {
                    LabeledContent("Servers file") {
                        Text(store.snapshot.mcpServersFile)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    Text(
                        "This native shell streams LLMs directly. MCP tool calls, exec approval, circuit breakers, and the full multi-turn agent loop run in the Python/Qt app (AgentCore). Use the same ~/.grizzyclaw/ paths so configs stay shared."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Config")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.reload()
                    } label: {
                        Label("Reload config", systemImage: "arrow.clockwise")
                    }
                    .help("Reload ~/.grizzyclaw/config.yaml")
                }
            }
        }
    }

    @ViewBuilder
    private func secretBadge(_ present: Bool) -> some View {
        Text(present ? "Present (hidden)" : "Not set")
            .foregroundStyle(present ? .secondary : .tertiary)
            .font(.caption)
    }
}
