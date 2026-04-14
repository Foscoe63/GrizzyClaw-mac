import AppKit
import GrizzyClawCore
import SwiftUI

/// CRUD for `~/.grizzyclaw/watchers/*.json` (parity with Python **Watchers** dialog).
struct WatchersMainView: View {
    @ObservedObject var store: WatcherStore
    @ObservedObject var workspaceStore: WorkspaceStore
    @State private var selectedId: String?
    @State private var editing: FolderWatcherRecord?
    /// True when the sheet was opened right after **New watcher** (Osaurus-style create copy).
    @State private var editingIsCreateFlow = false
    @State private var deleteTarget: FolderWatcherRecord?
    @State private var includeGlobsDraft = ""
    @State private var excludeGlobsDraft = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedId) {
                if store.isReloading {
                    Section {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                if store.loadError != nil || store.saveError != nil {
                    Section {
                        GrizzyClawStoreErrorBanner(loadError: store.loadError, saveError: store.saveError)
                    }
                }
                if !store.isReloading && store.watchers.isEmpty && store.loadError == nil {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "eye.slash")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No watchers yet")
                                .font(.headline)
                            Text("Create one with + or add JSON files under ~/.grizzyclaw/watchers/.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                }
                ForEach(store.watchers) { w in
                    HStack {
                        Image(systemName: w.enabled ? "eye" : "eye.slash")
                            .foregroundStyle(w.enabled ? .primary : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(w.name.isEmpty ? w.id : w.name)
                                .font(.headline)
                            if !w.watchPath.isEmpty {
                                Text(w.watchPath)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tag(w.id as String?)
                }
            }
            .navigationTitle("Watchers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.reload()
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .help("Reload ~/.grizzyclaw/watchers/")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        do {
                            let created = try store.create()
                            selectedId = created.id
                            editingIsCreateFlow = true
                            openEditor(created)
                        } catch {
                            store.saveError = error.localizedDescription
                        }
                    } label: {
                        Label("New watcher", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let w = store.watchers.first(where: { $0.id == selectedId }) {
                watcherDetail(w)
            } else {
                emptyDetail
            }
        }
        .sheet(item: $editing) { row in
            watcherEditSheet(row)
        }
        .alert("Delete watcher?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                if let id = deleteTarget?.id {
                    try? store.delete(id: id)
                    if selectedId == id { selectedId = nil }
                }
                deleteTarget = nil
            }
        } message: {
            Text(deleteTarget?.name ?? "")
        }
        .onAppear {
            workspaceStore.reload()
            store.reload()
            store.saveError = nil
        }
    }

    private func workspaceLabel(for id: String?) -> String {
        guard let id, !id.isEmpty,
              let w = workspaceStore.index?.workspaces.first(where: { $0.id == id }) else {
            return "Default (active workspace)"
        }
        return w.name
    }

    private var emptyDetail: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder.badge.gearshape")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Select a watcher")
                .font(.headline)
            Text("Create one with + or pick a row. Files are stored next to the Python app under ~/.grizzyclaw/watchers/.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func watcherDetail(_ w: FolderWatcherRecord) -> some View {
        Form {
            Section {
                LabeledContent("ID") {
                    Text(w.id)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                LabeledContent("File") {
                    Text(GrizzyClawPaths.watchersDirectory.appendingPathComponent("\(w.id).json").path)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            Section("Summary") {
                LabeledContent("Watch path", value: w.watchPath.isEmpty ? "—" : w.watchPath)
                LabeledContent("Agent", value: workspaceLabel(for: w.workspaceId))
                LabeledContent("Enabled", value: w.enabled ? "Yes" : "No")
                LabeledContent("Responsiveness", value: w.responsiveness)
            }
            Section {
                Button("Edit…") { openEditorExisting(w) }
                Button("Delete…", role: .destructive) { deleteTarget = w }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(w.name.isEmpty ? "Watcher" : w.name)
    }

    private func openEditor(_ w: FolderWatcherRecord) {
        includeGlobsDraft = w.includeGlobs.joined(separator: "\n")
        excludeGlobsDraft = w.excludeGlobs.joined(separator: "\n")
        store.saveError = nil
        editing = w
    }

    /// Opens editor from the detail pane (existing watcher).
    private func openEditorExisting(_ w: FolderWatcherRecord) {
        editingIsCreateFlow = false
        openEditor(w)
    }

    private func watcherEditSheet(_ w: FolderWatcherRecord) -> some View {
        WatcherEditForm(
            watcher: w,
            isCreateFlow: editingIsCreateFlow,
            workspaceStore: workspaceStore,
            includeGlobsDraft: $includeGlobsDraft,
            excludeGlobsDraft: $excludeGlobsDraft,
            onSave: { updated in
                do {
                    try store.save(updated)
                    editing = nil
                    editingIsCreateFlow = false
                } catch {
                    store.saveError = error.localizedDescription
                }
            },
            onCancel: {
                editing = nil
                editingIsCreateFlow = false
            }
        )
        .frame(minWidth: 580, minHeight: 640)
    }
}

/// Osaurus `WatcherEditorSheet`–style editor: folder picker, card row, instructions placeholder, monitoring section; keeps GrizzyClaw globs + advanced.
private struct WatcherEditForm: View {
    @Environment(\.colorScheme) private var colorScheme

    let watcher: FolderWatcherRecord
    var isCreateFlow: Bool
    @ObservedObject var workspaceStore: WorkspaceStore
    @Binding var includeGlobsDraft: String
    @Binding var excludeGlobsDraft: String
    var onSave: (FolderWatcherRecord) -> Void
    var onCancel: () -> Void

    @State private var name = ""
    @State private var instructions = ""
    /// `nil` means no folder chosen (Osaurus parity).
    @State private var selectedWatchPath: String?
    @State private var recursive = true
    @State private var responsiveness = "balanced"
    @State private var enabled = true
    @State private var maxConvergence = 5
    @State private var optionalLlmModel = ""
    /// Empty string = use active workspace at runtime (`workspace_id` omitted in JSON).
    @State private var agentWorkspaceId = ""

    private var hasWatchFolder: Bool {
        guard let p = selectedWatchPath else { return false }
        return !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSave: Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let ins = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return !n.isEmpty && !ins.isEmpty && hasWatchFolder
    }

    private var responsivenessHint: String {
        switch responsiveness {
        case "fast": return "Quick reactions (~0.2s debounce)."
        case "patient": return "Waits longer (~3s) before batching changes."
        default: return "Balanced debounce (~1s)."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    watcherNameField
                    watchedFolderSection
                    instructionsSection
                    monitoringSection
                    filtersSection
                    advancedSection
                }
                .padding(24)
            }

            sheetFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            name = watcher.name
            instructions = watcher.instructions
            selectedWatchPath = watcher.watchPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : watcher.watchPath
            recursive = watcher.recursive
            responsiveness = watcher.responsiveness
            enabled = watcher.enabled
            maxConvergence = watcher.maxConvergence
            optionalLlmModel = watcher.optionalLlmModel ?? ""
            agentWorkspaceId = watcher.workspaceId ?? ""
            includeGlobsDraft = watcher.includeGlobs.joined(separator: "\n")
            excludeGlobsDraft = watcher.excludeGlobs.joined(separator: "\n")
        }
    }

    // MARK: - Header (Osaurus-style)

    private var sheetHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                Image(systemName: isCreateFlow ? "eye.badge.clock.fill" : "pencil.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(isCreateFlow ? "Create Watcher" : "Edit Watcher")
                    .font(.system(size: 16, weight: .semibold))
                Text(isCreateFlow
                    ? "Set up a folder monitor"
                    : "Modify your file system watcher")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $enabled)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .help("Enabled")

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(nsColor: .controlBackgroundColor)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(headerBackground)
    }

    private var headerBackground: some View {
        Color(nsColor: .controlBackgroundColor)
            .opacity(colorScheme == .dark ? 0.6 : 1)
    }

    private var watcherNameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: "textformat")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("e.g., Downloads Organizer", text: $name)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(fieldChrome)
        }
    }

    // MARK: - Watched folder (Osaurus: Browse + NSOpenPanel)

    private var watchedFolderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            watcherSectionTitle("Watch path", icon: "folder.badge.gearshape")

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(hasWatchFolder ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                        Image(systemName: pathIconName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(hasWatchFolder ? Color.accentColor : .secondary)
                    }
                    .frame(width: 36, height: 36)

                    if let raw = selectedWatchPath?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(fileURLWithPath: raw).lastPathComponent)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            Text(raw)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } else {
                        Text("No folder or volume selected")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer(minLength: 8)

                    if hasWatchFolder {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                selectedWatchPath = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear path")
                    }

                    HStack(spacing: 6) {
                        Button {
                            selectWatchFolder(startAtVolumes: false)
                        } label: {
                            Text("Browse…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Choose any folder or volume")

                        Button {
                            selectWatchFolder(startAtVolumes: true)
                        } label: {
                            Text("Volumes…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Start at /Volumes to pick a disk")
                    }
                }
                .padding(10)
                .background(fieldChrome)

                Text("Watch a project folder, your home directory, or an entire disk. Disks are listed under /Volumes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Folder vs volume hint for the leading icon.
    private var pathIconName: String {
        guard let raw = selectedWatchPath?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return "folder.badge.questionmark"
        }
        if raw == "/" || raw.hasPrefix("/Volumes/") {
            return "externaldrive.fill"
        }
        return "folder.fill"
    }

    private func selectWatchFolder(startAtVolumes: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose Folder or Volume"
        panel.prompt = "Select"
        panel.message = "Select a folder or a volume. Use ⌘⇧G to type a path (for example / or /Volumes)."
        if startAtVolumes {
            let vol = URL(fileURLWithPath: "/Volumes")
            if FileManager.default.fileExists(atPath: vol.path) {
                panel.directoryURL = vol
            }
        } else if let cur = selectedWatchPath?.trimmingCharacters(in: .whitespacesAndNewlines), !cur.isEmpty {
            let u = URL(fileURLWithPath: cur)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                panel.directoryURL = u
            } else {
                panel.directoryURL = u.deletingLastPathComponent()
            }
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            selectedWatchPath = url.path
        }
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            watcherSectionTitle("Instructions", icon: "text.alignleft")

            ZStack(alignment: .topLeading) {
                if instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("What should the AI do when changes are detected?")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 12)
                        .padding(.leading, 16)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $instructions)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120, maxHeight: 180)
                    .padding(10)
            }
            .background(fieldChrome)

            Text("Instructions are sent to the automation runtime along with changed paths.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Monitoring

    private var monitoringSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            watcherSectionTitle("Monitoring", icon: "gear")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: recursive ? "arrow.triangle.2.circlepath" : "arrow.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(recursive ? Color.accentColor : .secondary)
                        .frame(width: 16)
                    Toggle("Recursive monitoring", isOn: $recursive)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Spacer()
                }
                Text("When on, changes in subfolders are included.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Responsiveness")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker("Responsiveness", selection: $responsiveness) {
                        Text("Fast").tag("fast")
                        Text("Balanced").tag("balanced")
                        Text("Patient").tag("patient")
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 160, alignment: .trailing)
                }
                Text(responsivenessHint)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Agent")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker("Agent", selection: $agentWorkspaceId) {
                        Text("Default (active workspace)").tag("")
                        ForEach(workspaceStore.index?.workspaces ?? []) { w in
                            Text(w.name).tag(w.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 220, alignment: .trailing)
                }
                Text("Workspace (agent) used when automation runs for this watcher.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .background(cardChrome)
    }

    // MARK: - Filters & advanced

    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            watcherSectionTitle("Filters", icon: "line.3.horizontal.decrease.circle")
            Text("One glob per line; empty include = all files.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Text("Include")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $includeGlobsDraft)
                .frame(minHeight: 56)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(fieldChrome)
            Text("Exclude")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $excludeGlobsDraft)
                .frame(minHeight: 72)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(fieldChrome)
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            watcherSectionTitle("Advanced", icon: "slider.horizontal.3")
            Stepper("Max convergence: \(maxConvergence)", value: $maxConvergence, in: 1...50)
            TextField("Optional LLM model override", text: $optionalLlmModel)
                .textFieldStyle(.roundedBorder)
        }
        .padding(16)
        .background(cardChrome)
    }

    private func watcherSectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
        }
    }

    private var fieldChrome: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
            )
    }

    private var cardChrome: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(PreferencesTheme.groupFill(colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(PreferencesTheme.groupStroke(colorScheme), lineWidth: 1)
            )
    }

    // MARK: - Footer

    private var sheetFooter: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Cancel", action: onCancel)
            Button(isCreateFlow ? "Create Watcher" : "Save Changes", action: save)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSave)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            Color(nsColor: .controlBackgroundColor)
                .overlay(alignment: .top) {
                    Divider()
                }
        )
    }

    private func save() {
        guard canSave else { return }
        let inc = includeGlobsDraft.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let exc = excludeGlobsDraft.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let optModel = optionalLlmModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = selectedWatchPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let merged = FolderWatcherRecord(
            id: watcher.id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled watcher" : name,
            instructions: instructions,
            watchPath: path,
            recursive: recursive,
            responsiveness: responsiveness,
            enabled: enabled,
            includeGlobs: inc,
            excludeGlobs: exc.isEmpty ? FolderWatcherRecord.defaultExcludeGlobs : exc,
            maxConvergence: maxConvergence,
            optionalLlmModel: optModel.isEmpty ? nil : optModel,
            workspaceId: agentWorkspaceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : agentWorkspaceId.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: watcher.createdAt,
            lastTriggeredAt: watcher.lastTriggeredAt,
            lastError: watcher.lastError
        )
        onSave(merged)
    }
}
