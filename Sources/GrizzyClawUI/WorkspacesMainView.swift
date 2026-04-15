import AppKit
import GrizzyClawCore
import SwiftUI
import UniformTypeIdentifiers

/// Workspace browser + detail (`workspaces.json` parity); layout aligned with Python `WorkspaceDialog`.
struct WorkspacesMainView: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var workspaceStore: WorkspaceStore
    @ObservedObject var configStore: ConfigStore
    @ObservedObject var chatSession: ChatSessionModel
    @Binding var selectedWorkspaceId: String?

    @State private var showingCreate = false
    @State private var showingImport = false
    @State private var importLinkText = ""
    @State private var deleteTargetId: String?
    @State private var mutationError: String?

    @State private var createName = ""
    @State private var selectedTemplateKey = BuiltInWorkspaceTemplates.orderedKeys[0]

    var body: some View {
        NavigationSplitView {
            workspaceSidebar
        } detail: {
            workspaceDetail
        }
        .navigationTitle("🗂️ Workspaces")
        .sheet(isPresented: $showingCreate) {
            CreateWorkspaceDialog(
                workspaceStore: workspaceStore,
                isPresented: $showingCreate,
                createName: $createName,
                selectedTemplateKey: $selectedTemplateKey,
                onCreated: { newId in
                    selectedWorkspaceId = newId
                    workspaceStore.persistActiveWorkspace(id: newId)
                    mutationError = nil
                }
            )
        }
        .sheet(isPresented: $showingImport) {
            NavigationStack {
                Form {
                    Section {
                        TextField("Paste share link", text: $importLinkText, axis: .vertical)
                            .lineLimit(3...8)
                    } footer: {
                        Text("Paste a link exported with “Copy share link” from another GrizzyClaw.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Import workspace")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingImport = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Import") {
                            importWorkspaceFromPastedLink()
                        }
                        .disabled(importLinkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .frame(minWidth: 420, minHeight: 220)
        }
        .alert("Workspace", isPresented: Binding(
            get: { mutationError != nil },
            set: { if !$0 { mutationError = nil } }
        )) {
            Button("OK", role: .cancel) { mutationError = nil }
        } message: {
            Text(mutationError ?? "")
        }
        .confirmationDialog(
            "Delete this workspace?",
            isPresented: Binding(
                get: { deleteTargetId != nil },
                set: { if !$0 { deleteTargetId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = deleteTargetId {
                    deleteWorkspace(id: id)
                }
                deleteTargetId = nil
            }
            Button("Cancel", role: .cancel) { deleteTargetId = nil }
        } message: {
            Text("This cannot be undone. Session files for that workspace id remain under ~/.grizzyclaw/sessions/ unless you remove them manually.")
        }
    }

    private var workspaceSidebar: some View {
        let theme = configStore.snapshot.theme
        let sidebarBg = AppearanceTheme.sidebarBackground(theme: theme, colorScheme: colorScheme)

        return VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Workspaces")
                    .font(.system(size: 18, weight: .bold))
                Spacer(minLength: 0)
                Button {
                    workspaceStore.reload()
                    syncSelectionAfterLoad()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload ~/.grizzyclaw/workspaces.json")
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 10)

            List(selection: $selectedWorkspaceId) {
                if workspaceStore.isReloading {
                    Section {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                if workspaceStore.loadError != nil || workspaceStore.saveError != nil {
                    Section {
                        GrizzyClawStoreErrorBanner(
                            loadError: workspaceStore.loadError,
                            saveError: workspaceStore.saveError
                        )
                    }
                }
                if workspaceStore.index == nil && workspaceStore.loadError == nil {
                    Section {
                        Text("No workspaces.json")
                            .foregroundStyle(.secondary)
                        Text("Use + New, or add ~/.grizzyclaw/workspaces.json.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let idx = workspaceStore.index {
                    Section {
                        ForEach(idx.workspaces) { ws in
                            workspaceRow(ws, index: idx)
                                .tag(Optional(ws.id))
                        }
                        .onMove { source, destination in
                            do {
                                try workspaceStore.moveWorkspace(from: source, to: destination)
                            } catch {
                                mutationError = error.localizedDescription
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button("+ New") {
                        resetCreateDraft()
                        showingCreate = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help("Create a new workspace")

                    Button("Import Link") {
                        importLinkText = ""
                        showingImport = true
                    }
                    .buttonStyle(.bordered)
                    .help("Import from a pasted share link")
                }

                HStack(spacing: 8) {
                    Button("Import File") {
                        importWorkspaceFromFile()
                    }
                    .buttonStyle(.bordered)
                    .help("Import a workspace/agent JSON file")

                    Button("Export JSON") {
                        exportSelectedWorkspaceJSON()
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedWorkspaceId == nil)
                    .help("Export the selected workspace as a JSON file")

                    Button("Delete") {
                        if let id = selectedWorkspaceId {
                            deleteTargetId = id
                        }
                    }
                    .disabled(!canDeleteSelection)
                    .foregroundStyle(canDeleteSelection ? Color(red: 1, green: 0.23, blue: 0.19) : .secondary)
                    .help("Delete the selected workspace")
                }

                if let idx = workspaceStore.index,
                   let bid = idx.baselineWorkspaceId,
                   selectedWorkspaceId != bid {
                    Button("Return to baseline") {
                        workspaceStore.returnToBaselineWorkspace()
                        selectedWorkspaceId = workspaceStore.index?.activeWorkspaceId
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .help("Switch active workspace to the baseline (⌃⇧B)")
                }

                Button("Open ~/.grizzyclaw in Finder…") {
                    GrizzyClawShell.revealUserDataFolder()
                }
                .font(.caption)
                .buttonStyle(.plain)

                Text(GrizzyClawPaths.userDataDirectory.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(sidebarBg)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 280, max: 320)
    }

    private var canDeleteSelection: Bool {
        guard let id = selectedWorkspaceId,
              let idx = workspaceStore.index,
              idx.workspaces.count > 1 else { return false }
        return idx.workspaces.contains(where: { $0.id == id })
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
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var workspaceDetail: some View {
        if let id = selectedWorkspaceId, let ws = workspaceStore.index?.workspaces.first(where: { $0.id == id }) {
            WorkspaceFullEditorView(
                workspace: ws,
                workspaceStore: workspaceStore,
                configStore: configStore,
                chatSession: chatSession,
                defaultProvider: configStore.snapshot.defaultLlmProvider,
                defaultModel: configStore.snapshot.defaultModel,
                defaultOllamaUrl: configStore.snapshot.ollamaUrl,
                onSave: {},
                onNavigateToWorkspaceId: { selectedWorkspaceId = $0 }
            )
            .id(ws.id)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Select a workspace")
                    .font(.title3.weight(.semibold))
                Text("Choose a workspace in the sidebar. Use 💾 Save Changes (⌘S) in the editor to persist changes to ~/.grizzyclaw/workspaces.json.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
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

    private func resetCreateDraft() {
        createName = ""
        let rows = workspaceStore.mergedTemplateRowsForNewWorkspace()
        selectedTemplateKey = rows.first?.templateKey ?? BuiltInWorkspaceTemplates.orderedKeys[0]
    }

    private func importWorkspaceFromPastedLink() {
        let text = importLinkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            let newId = try workspaceStore.importWorkspaceFromLink(text)
            selectedWorkspaceId = newId
            showingImport = false
            importLinkText = ""
            mutationError = nil
        } catch {
            mutationError = error.localizedDescription
        }
    }

    private func deleteWorkspace(id: String) {
        do {
            try workspaceStore.deleteWorkspace(id: id)
            if selectedWorkspaceId == id {
                selectedWorkspaceId = workspaceStore.index?.activeWorkspaceId
                    ?? workspaceStore.index?.workspaces.first?.id
            }
            mutationError = nil
        } catch {
            mutationError = error.localizedDescription
        }
    }

    private func importWorkspaceFromFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "Import Workspace"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                let newId = try workspaceStore.importWorkspaceFromJSONData(data)
                selectedWorkspaceId = newId
                mutationError = nil
            } catch {
                mutationError = error.localizedDescription
            }
        }
    }

    private func exportSelectedWorkspaceJSON() {
        guard let id = selectedWorkspaceId else { return }
        do {
            let data = try workspaceStore.exportWorkspaceToJSONData(id: id)
            let workspaceName = workspaceStore.index?.workspaces.first(where: { $0.id == id })?.name ?? "workspace"
            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true
            savePanel.nameFieldStringValue = "\(workspaceName.replacingOccurrences(of: "/", with: "-")).json"
            savePanel.allowedContentTypes = [.json]
            savePanel.prompt = "Export Workspace"
            savePanel.begin { response in
                guard response == .OK, let url = savePanel.url else { return }
                do {
                    try data.write(to: url, options: .atomic)
                    mutationError = nil
                } catch {
                    mutationError = error.localizedDescription
                }
            }
        } catch {
            mutationError = error.localizedDescription
        }
    }
}
