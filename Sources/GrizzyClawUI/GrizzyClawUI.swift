import GrizzyClawCore
import SwiftUI

/// Shared SwiftUI app chrome for `swift run` and the Xcode `.app` host.
public struct GrizzyClawRootApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            GrizzyClawMenuCommands()
        }
    }
}

public struct ContentView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GrizzyClaw")
                .font(.largeTitle.weight(.semibold))
            Text("Native macOS build (Swift)")
                .foregroundStyle(.secondary)
            Text("Version \(AppInfo.versionLabel)")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)

            Divider()
                .padding(.vertical, 4)

            Text("Config & data (Python parity)")
                .font(.headline)
            LabeledContent("Data directory") {
                Text(GrizzyClawPaths.userDataDirectory.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            LabeledContent("config.yaml") {
                Text(GrizzyClawPaths.configYAML.lastPathComponent)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("workspaces.json") {
                Text(GrizzyClawPaths.workspacesJSON.lastPathComponent)
                    .foregroundStyle(.secondary)
            }

            Button("Open data folder in Finder…") {
                GrizzyClawShell.revealUserDataFolder()
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])
        }
        .frame(minWidth: 520, minHeight: 380)
        .padding(32)
    }
}
