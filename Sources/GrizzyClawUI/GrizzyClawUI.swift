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
    @StateObject private var workspaceStore = WorkspaceStore()
    @State private var selectedWorkspaceId: String?

    public init() {}

    public var body: some View {
        NavigationSplitView {
            workspaceSidebar
        } detail: {
            workspaceDetail
        }
        .frame(minWidth: 640, minHeight: 420)
        .onAppear {
            workspaceStore.reload()
            syncSelectionAfterLoad()
        }
    }

    private var workspaceSidebar: some View {
        List(selection: $selectedWorkspaceId) {
            if let err = workspaceStore.loadError {
                Section {
                    Text(err)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            if workspaceStore.index == nil && workspaceStore.loadError == nil {
                Section {
                    Text("No workspaces.json")
                        .foregroundStyle(.secondary)
                    Text("Use the Python app once, or add ~/.grizzyclaw/workspaces.json.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            if let idx = workspaceStore.index {
                Section("Workspaces (\(idx.workspaces.count))") {
                    ForEach(idx.workspaces) { ws in
                        workspaceRow(ws, index: idx)
                            .tag(Optional(ws.id))
                    }
                }
            }
            Section("App") {
                LabeledContent("Version") {
                    Text(AppInfo.versionLabel)
                        .font(.caption.monospaced())
                }
                Button("Open ~/.grizzyclaw in Finder…") {
                    GrizzyClawShell.revealUserDataFolder()
                }
                Text(GrizzyClawPaths.userDataDirectory.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    workspaceStore.reload()
                    syncSelectionAfterLoad()
                } label: {
                    Label("Reload workspaces", systemImage: "arrow.clockwise")
                }
                .help("Reload ~/.grizzyclaw/workspaces.json")
            }
        }
    }

    @ViewBuilder
    private func workspaceRow(_ ws: WorkspaceRecord, index: WorkspaceIndex) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(ws.icon ?? "📁")
            VStack(alignment: .leading, spacing: 2) {
                Text(ws.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    if ws.id == index.activeWorkspaceId {
                        Text("Active")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    if ws.id == index.baselineWorkspaceId {
                        Text("Baseline")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var workspaceDetail: some View {
        if let id = selectedWorkspaceId, let ws = workspaceStore.index?.workspaces.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(ws.icon ?? "🤖") \(ws.name)")
                        .font(.title2.weight(.semibold))
                    LabeledContent("ID", value: ws.id)
                    if let d = ws.description, !d.isEmpty {
                        LabeledContent("Description") {
                            Text(d).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let c = ws.color {
                        LabeledContent("Color", value: c)
                    }
                    if let cfg = ws.config {
                        LabeledContent("Config keys") {
                            Text(configKeySummary(cfg))
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Select a workspace")
                    .font(.title3.weight(.semibold))
                Text("Choose a row in the sidebar to inspect metadata (read-only).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func syncSelectionAfterLoad() {
        guard let idx = workspaceStore.index else {
            selectedWorkspaceId = nil
            return
        }
        if let s = selectedWorkspaceId, idx.workspaces.contains(where: { $0.id == s }) {
            return
        }
        selectedWorkspaceId = idx.activeWorkspaceId ?? idx.workspaces.first?.id
    }

    private func configKeySummary(_ value: JSONValue) -> String {
        switch value {
        case .object(let dict):
            return dict.keys.sorted().joined(separator: ", ")
        case .array(let a):
            return "array(\(a.count) items)"
        default:
            return String(describing: value)
        }
    }
}
