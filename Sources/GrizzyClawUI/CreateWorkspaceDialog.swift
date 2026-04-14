import AppKit
import GrizzyClawCore
import SwiftUI

/// Parity with Python `TemplateDialog`: name field, template list, optional “Add new template”, Cancel / Create.
struct CreateWorkspaceDialog: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var workspaceStore: WorkspaceStore

    @Binding var isPresented: Bool
    @Binding var createName: String
    @Binding var selectedTemplateKey: String

    var onCreated: (String) -> Void

    @State private var showingAddTemplate = false
    @State private var addKey = ""
    @State private var addName = ""
    @State private var addDescription = ""
    @State private var addIcon = "🤖"
    @State private var addColor = "#007AFF"
    @State private var sheetError: String?

    private var accent: Color {
        colorScheme == .dark ? Color(red: 0.04, green: 0.52, blue: 1) : Color(red: 0, green: 0.48, blue: 1)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color(white: 0.23) : Color(white: 0.9)
    }

    private var templateRows: [WorkspaceTemplatePickerRow] {
        workspaceStore.mergedTemplateRowsForNewWorkspace()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Workspace")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name:")
                    .font(.subheadline.weight(.medium))
                TextField("My Workspace", text: $createName)
                    .textFieldStyle(.roundedBorder)
            }

            Text("Choose a template:")
                .font(.subheadline.weight(.medium))

            List(selection: $selectedTemplateKey) {
                ForEach(templateRows) { row in
                    templateRowView(row)
                        .tag(row.templateKey)
                }
            }
            .listStyle(.plain)
            .frame(minHeight: 220)
            .background(colorScheme == .dark ? Color(white: 0.12) : Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )

            Button {
                prepareAddTemplateFields()
                showingAddTemplate = true
            } label: {
                Text("➕ Add new template")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(borderColor)
            )
            .foregroundStyle(accent)

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.bordered)

                Button("Create") {
                    submitCreate()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(createName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 480)
        .background(colorScheme == .dark ? Color(white: 0.12) : Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if templateRows.allSatisfy({ $0.templateKey != selectedTemplateKey }),
               let first = templateRows.first?.templateKey {
                selectedTemplateKey = first
            }
        }
        .sheet(isPresented: $showingAddTemplate) {
            addTemplateSheet
        }
        .alert("Workspace", isPresented: Binding(
            get: { sheetError != nil },
            set: { if !$0 { sheetError = nil } }
        )) {
            Button("OK", role: .cancel) { sheetError = nil }
        } message: {
            Text(sheetError ?? "")
        }
    }

    private func templateRowView(_ row: WorkspaceTemplatePickerRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(row.icon)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.headline)
                Text(row.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var addTemplateSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. designer, my_assistant", text: $addKey)
                    TextField("Display name", text: $addName)
                    TextField("Short description", text: $addDescription)
                    TextField("Emoji icon", text: $addIcon)
                    TextField("#007AFF", text: $addColor)
                } header: {
                    Text("New template")
                } footer: {
                    Text("Config (system prompt, swarm, etc.) is copied from the template currently selected in the list above.")
                        .font(.caption)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add new template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddTemplate = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save template") { saveNewTemplate() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 320)
    }

    private func prepareAddTemplateFields() {
        addKey = ""
        sheetError = nil
        if let row = templateRows.first(where: { $0.templateKey == selectedTemplateKey }) {
            addName = row.title
            addDescription = row.subtitle
            addIcon = row.icon
            addColor = row.color
        } else {
            addName = ""
            addDescription = ""
            addIcon = "🤖"
            addColor = "#007AFF"
        }
    }

    private func saveNewTemplate() {
        let key = addKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "_")
        guard !key.isEmpty else {
            sheetError = "Please enter a template key."
            return
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard key.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            sheetError = "Template key can only contain letters, numbers, and underscores."
            return
        }
        let trimmedName = addName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? Self.titleCaseUnderscores(key) : trimmedName
        do {
            try workspaceStore.saveUserTemplateFromPicker(
                key: key,
                displayName: name,
                description: addDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                icon: addIcon.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "🤖",
                color: addColor.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "#007AFF",
                baseTemplateKey: selectedTemplateKey
            )
            selectedTemplateKey = key
            showingAddTemplate = false
        } catch {
            sheetError = error.localizedDescription
        }
    }

    private func submitCreate() {
        let name = createName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard let row = templateRows.first(where: { $0.templateKey == selectedTemplateKey }) else { return }
        do {
            let config = try workspaceStore.configForNewWorkspace(templateKey: selectedTemplateKey)
            let newId = try workspaceStore.createWorkspace(
                name: name,
                description: row.subtitle,
                icon: row.icon,
                color: row.color,
                config: config
            )
            isPresented = false
            onCreated(newId)
        } catch {
            sheetError = error.localizedDescription
        }
    }

    private static func titleCaseUnderscores(_ key: String) -> String {
        key.split(separator: "_").map { String($0).capitalized }.joined(separator: " ")
    }
}

private extension String {
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
