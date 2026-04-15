import GrizzyClawCore
import SwiftUI

struct WorkspaceSkillEditorSection: View {
    @Binding var usesWorkspaceOverride: Bool
    @Binding var workspaceSkillIDs: [String]

    let inheritedSkillIDs: [String]
    let marketplaceEntries: [SkillMarketplaceEntry]
    let marketplaceLoadError: String?

    @State private var selectedSkill: String?
    @State private var showAddSkillSheet = false
    @State private var showGitHubImportSheet = false
    @State private var customSkillID = ""
    @State private var alertInfo: String?
    @State private var installedSkills: [InstalledSkillSummary] = []

    private var effectiveSkillIDs: [String] {
        usesWorkspaceOverride ? workspaceSkillIDs : inheritedSkillIDs
    }

    private var effectiveSkillSet: Set<String> {
        Set(effectiveSkillIDs.map { $0.lowercased() })
    }

    private var availableSkillEntries: [AvailableSkillEntry] {
        let builtinEntries = BuiltinClawHubSkills.all.map { builtin in
            AvailableSkillEntry(
                id: builtin.id,
                title: "\(builtin.icon) \(builtin.name)",
                subtitle: builtin.description,
                sourceLabel: "Built-in"
            )
        }
        let installedEntries = installedSkills
            .filter { installed in BuiltinClawHubSkills.skill(forID: installed.id) == nil }
            .map { installed in
                AvailableSkillEntry(
                    id: installed.id,
                    title: installed.title,
                    subtitle: installed.description,
                    sourceLabel: "Imported"
                )
            }
        return builtinEntries + installedEntries
    }

    private var overrideBinding: Binding<Bool> {
        Binding(
            get: { usesWorkspaceOverride },
            set: { newValue in
                if newValue, !usesWorkspaceOverride {
                    workspaceSkillIDs = effectiveSkillIDs
                }
                usesWorkspaceOverride = newValue
                selectedSkill = nil
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Skills for this agent")
                    .font(.headline)
                Text(
                    "Use global ClawHub defaults by default, or enable a workspace-specific override for this agent. "
                        + "This keeps default skills centralized while letting specialists diverge when needed."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Override global skill defaults for this agent", isOn: overrideBinding)

            if usesWorkspaceOverride {
                Text("This workspace saves its own `enabled_skills` list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("This workspace inherits the global `enabled_skills` list from `config.yaml`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            List(selection: $selectedSkill) {
                if effectiveSkillIDs.isEmpty {
                    Text("No skills enabled.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(effectiveSkillIDs, id: \.self) { skillID in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skillTitle(for: skillID))
                            if let subtitle = skillSubtitle(for: skillID) {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(Optional(skillID))
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(minHeight: 120, maxHeight: 240)

            HStack(spacing: 8) {
                Button("+ Add Skill") {
                    ensureWorkspaceOverrideSeeded()
                    showAddSkillSheet = true
                }
                Button("Import GitHub…") {
                    ensureWorkspaceOverrideSeeded()
                    showGitHubImportSheet = true
                }
                Button("Import Local…") {
                    importLocalSkill()
                }
                Button("Remove") {
                    removeSelectedSkill()
                }
                .disabled(selectedSkill == nil || effectiveSkillIDs.isEmpty)
                if usesWorkspaceOverride {
                    Button("Reset to global defaults") {
                        usesWorkspaceOverride = false
                        selectedSkill = nil
                    }
                }
                Button("Refresh available skills") {
                    reloadInstalledSkills()
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Available skills")
                    .font(.subheadline.weight(.medium))
                Text(
                    "Built-in and imported skills appear here. Toggling a skill on or off creates a workspace override automatically if this agent is still inheriting global defaults."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                List(availableSkillEntries) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(entry.title)
                                Text(entry.sourceLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.id)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text(entry.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Toggle("", isOn: bindingForSkillEnabled(entry.id))
                            .labelsHidden()
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .frame(minHeight: 180, maxHeight: 280)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Marketplace bundles")
                    .font(.subheadline.weight(.medium))
                Text(
                    "Bundle actions update the current agent override. If this workspace is inheriting defaults, adding or removing a bundle first creates an override seeded from the inherited skill set."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if let marketplaceLoadError {
                    Text(marketplaceLoadError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if marketplaceEntries.isEmpty {
                    Text("No marketplace entries loaded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(marketplaceEntries) { entry in
                        let bundleAdded = entry.enabledSkillsAdd.allSatisfy { effectiveSkillSet.contains($0.lowercased()) }
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name)
                                    .font(.subheadline.weight(.medium))
                                if !entry.description.isEmpty {
                                    Text(entry.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if !entry.enabledSkillsAdd.isEmpty {
                                    Text(entry.enabledSkillsAdd.joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 12)
                            Button(bundleAdded ? "Remove" : "Add") {
                                toggleMarketplaceBundle(entry, remove: bundleAdded)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(bundleAdded ? Color(red: 0.75, green: 0.22, blue: 0.17) : nil)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .sheet(isPresented: $showAddSkillSheet) {
            addSkillSheet
        }
        .sheet(isPresented: $showGitHubImportSheet) {
            GitHubSkillImportSheet(isPresented: $showGitHubImportSheet) { importedIDs in
                ensureWorkspaceOverrideSeeded()
                reloadInstalledSkills()
                for id in importedIDs {
                    appendSkill(id)
                }
                alertInfo = "Imported \(importedIDs.count) GitHub skill(s) into this agent override."
            }
        }
        .alert("Skills", isPresented: Binding(
            get: { alertInfo != nil },
            set: { if !$0 { alertInfo = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertInfo ?? "")
        }
        .task {
            reloadInstalledSkills()
        }
    }

    private var addSkillSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add skill to this agent")
                .font(.headline)

            let available = BuiltinClawHubSkills.availableToAdd(enabledLowercased: effectiveSkillSet)
            if available.isEmpty {
                Text("All built-in skills are already enabled for this agent. Add a custom id below if you installed a skill separately.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                List(available) { skill in
                    Button {
                        appendSkill(skill.id)
                        showAddSkillSheet = false
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skill.name)
                            Text(skill.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 180)
            }

            Divider()

            Text("Custom skill id")
                .font(.subheadline)
            HStack {
                TextField("e.g. my_custom_skill", text: $customSkillID)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let value = customSkillID.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    appendSkill(value)
                    customSkillID = ""
                    showAddSkillSheet = false
                }
            }

            HStack {
                Spacer()
                Button("Close") { showAddSkillSheet = false }
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 320)
    }

    private func skillTitle(for skillID: String) -> String {
        if let builtin = BuiltinClawHubSkills.skill(forID: skillID) {
            return "\(builtin.icon) \(builtin.name)"
        }
        return skillID
    }

    private func skillSubtitle(for skillID: String) -> String? {
        if let builtin = BuiltinClawHubSkills.skill(forID: skillID) {
            return "\(builtin.id) - \(builtin.description)"
        }
        return "Custom installed skill id"
    }

    private func ensureWorkspaceOverrideSeeded() {
        guard !usesWorkspaceOverride else { return }
        workspaceSkillIDs = effectiveSkillIDs
        usesWorkspaceOverride = true
    }

    private func appendSkill(_ rawID: String) {
        ensureWorkspaceOverrideSeeded()
        let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let lowered = trimmed.lowercased()
        guard !workspaceSkillIDs.contains(where: { $0.lowercased() == lowered }) else { return }
        workspaceSkillIDs.append(trimmed)
    }

    private func removeSelectedSkill() {
        guard let selectedSkill else { return }
        ensureWorkspaceOverrideSeeded()
        workspaceSkillIDs.removeAll { $0.caseInsensitiveCompare(selectedSkill) == .orderedSame }
        self.selectedSkill = nil
    }

    private func toggleMarketplaceBundle(_ entry: SkillMarketplaceEntry, remove: Bool) {
        ensureWorkspaceOverrideSeeded()
        if remove {
            let removeSet = Set(entry.enabledSkillsAdd.map { $0.lowercased() })
            workspaceSkillIDs.removeAll { removeSet.contains($0.lowercased()) }
            if let selectedSkill, removeSet.contains(selectedSkill.lowercased()) {
                self.selectedSkill = nil
            }
            return
        }

        for skillID in entry.enabledSkillsAdd {
            appendSkill(skillID)
        }
    }

    private func bindingForSkillEnabled(_ skillID: String) -> Binding<Bool> {
        Binding(
            get: { effectiveSkillSet.contains(skillID.lowercased()) },
            set: { enabled in
                if enabled {
                    appendSkill(skillID)
                } else {
                    removeSkill(skillID)
                }
            }
        )
    }

    private func removeSkill(_ rawID: String) {
        ensureWorkspaceOverrideSeeded()
        workspaceSkillIDs.removeAll { $0.caseInsensitiveCompare(rawID) == .orderedSame }
        if let selectedSkill, selectedSkill.caseInsensitiveCompare(rawID) == .orderedSame {
            self.selectedSkill = nil
        }
    }

    private func importLocalSkill() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.prompt = "Import Skill"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                do {
                    let skillID = try InstalledSkillStore.importSkill(from: url)
                    reloadInstalledSkills()
                    appendSkill(skillID)
                    alertInfo = "Imported local skill `\(skillID)` into this agent override."
                } catch {
                    alertInfo = error.localizedDescription
                }
            }
        }
    }

    private func reloadInstalledSkills() {
        do {
            installedSkills = try InstalledSkillStore.listInstalledSkills()
        } catch {
            installedSkills = []
            alertInfo = error.localizedDescription
        }
    }
}

private struct AvailableSkillEntry: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let sourceLabel: String
}
