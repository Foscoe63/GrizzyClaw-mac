import AppKit
import GrizzyClawCore
import SwiftUI

/// Parity with Python `ClawHubTab` (`settings_dialog.py`): cards, HF token + eye toggle, skills list, Install URL, actions.
struct ClawHubPreferencesView: View {
    @ObservedObject var doc: ConfigYamlDocument

    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedSkill: String?
    @State private var skillInstallURL = ""
    @State private var installBusy = false
    @State private var checkUpdatesBusy = false
    @State private var hfShowToken = false
    @State private var showAddSkillSheet = false
    @State private var showGitHubImportSheet = false
    @State private var addSkillByIdText = ""
    @State private var alertInfo: String?

    private static let maxContentWidth: CGFloat = 680

    private var isDark: Bool { colorScheme == .dark }
    private var bg: Color { isDark ? Color(red: 0.12, green: 0.12, blue: 0.12) : Color(nsColor: .windowBackgroundColor) }
    private var fg: Color { isDark ? .white : Color(red: 0.11, green: 0.11, blue: 0.12) }
    private var secondary: Color { Color(nsColor: .secondaryLabelColor) }
    private var card: Color { isDark ? Color(red: 0.18, green: 0.18, blue: 0.18) : Color(red: 0.98, green: 0.98, blue: 0.98) }
    private var border: Color { isDark ? Color(red: 0.23, green: 0.23, blue: 0.24) : Color(red: 0.90, green: 0.90, blue: 0.92) }

    private var enabledSkillsBinding: Binding<[String]> {
        doc.bindingStringArray("enabled_skills")
    }

    private var enabledLowercased: Set<String> {
        Set(enabledSkillsBinding.wrappedValue.map { $0.lowercased() })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("ClawHub - Skills")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(fg)
                Text("Configure HuggingFace and the built-in skills registry.")
                    .font(.system(size: 13))
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)

                huggingFaceCard
                skillsCard
            }
            .padding(EdgeInsets(top: 20, leading: 24, bottom: 24, trailing: 24))
            .frame(maxWidth: Self.maxContentWidth, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg)
        .sheet(isPresented: $showAddSkillSheet) {
            addSkillSheet
        }
        .sheet(isPresented: $showGitHubImportSheet) {
            GitHubSkillImportSheet(isPresented: $showGitHubImportSheet) { importedIDs in
                appendSkills(importedIDs)
                alertInfo =
                    "Imported \(importedIDs.count) skill(s) from GitHub and added them to the global defaults."
            }
        }
        .alert("GrizzyClaw", isPresented: Binding(
            get: { alertInfo != nil },
            set: { if !$0 { alertInfo = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertInfo ?? "")
        }
    }

    private var huggingFaceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🤗 Hugging Face")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(fg)
            Text("Access HuggingFace models and spaces")
                .font(.system(size: 12))
                .foregroundStyle(secondary)
            HStack(spacing: 12) {
                Group {
                    if hfShowToken {
                        TextField("", text: doc.bindingOptionalStringNull("hf_token"))
                    } else {
                        SecureField("Enter your HuggingFace API token", text: doc.bindingOptionalStringNull("hf_token"))
                    }
                }
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(isDark ? Color(red: 0.23, green: 0.23, blue: 0.24) : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(border, lineWidth: 1))

                Button {
                    hfShowToken.toggle()
                } label: {
                    Text("👁")
                        .font(.system(size: 14))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                .help("Show or hide token")
            }
            Text("Get your token from huggingface.co/settings/tokens")
                .font(.system(size: 12))
                .foregroundStyle(secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(border, lineWidth: 1))
    }

    private var skillsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("⚡ Skills Registry")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(fg)
            Text("Set global skill defaults and install AI capabilities")
                .font(.system(size: 12))
                .foregroundStyle(secondary)
            Text("These `enabled_skills` are the global defaults used by agents/workspaces that do not set their own override.")
                .font(.system(size: 12))
                .foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Built-ins: web_search, filesystem, documentation, browser, memory, scheduler, calendar, gmail, github, mcp_marketplace")
                .font(.system(size: 12))
                .foregroundStyle(secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Install from URL:")
                    .font(.system(size: 13))
                    .foregroundStyle(fg)
                TextField("https://github.com/.../Skill-repo", text: $skillInstallURL)
                    .textFieldStyle(.roundedBorder)
                if installBusy {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                }
                Button("Install") {
                    Task { await runInstallFromURL() }
                }
                .disabled(installBusy || skillInstallURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Clone repo and install as reference skill (SKILL.md). Requires git and pip install grizzyclaw.")
            }

            HStack(spacing: 8) {
                Button("Import GitHub…") {
                    showGitHubImportSheet = true
                }
                Button("Import Local…") {
                    importLocalSkill()
                }
                Spacer()
            }
            .controlSize(.regular)

            List(selection: $selectedSkill) {
                ForEach(doc.stringArray("enabled_skills"), id: \.self) { name in
                    Text(name)
                        .tag(Optional(name))
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(minHeight: 100, maxHeight: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(border, lineWidth: 1))

            HStack(spacing: 8) {
                Button("+ Add Skill") {
                    showAddSkillSheet = true
                }
                Button("Remove") {
                    removeSelectedSkill()
                }
                Button("Configure") {
                    configureSelectedSkill()
                }
                Button("Refresh") {
                    doc.reloadValue(forKey: "enabled_skills")
                    alertInfo = "Global skill defaults reloaded from saved config.yaml on disk."
                }
                Button("Check for updates") {
                    Task { await runCheckUpdates() }
                }
                .disabled(checkUpdatesBusy)
                Spacer(minLength: 0)
            }
            .controlSize(.regular)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(border, lineWidth: 1))
    }

    private var addSkillSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add skill")
                .font(.headline)
            let available = BuiltinClawHubSkills.availableToAdd(enabledLowercased: enabledLowercased)
            if available.isEmpty {
                Text("All built-in skills from the registry are already enabled. Use “Install from URL” for GitHub skills, or add a custom id below.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                List(available) { skill in
                    Button {
                        appendSkill(skill.id)
                        showAddSkillSheet = false
                    } label: {
                        Text(skill.pickerLabel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 160)
            }
            Divider()
            Text("Custom skill id")
                .font(.subheadline)
            HStack {
                TextField("e.g. my_custom_skill", text: $addSkillByIdText)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    let s = addSkillByIdText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !s.isEmpty else { return }
                    appendSkill(s)
                    addSkillByIdText = ""
                    showAddSkillSheet = false
                }
            }
            HStack {
                Spacer()
                Button("Close") { showAddSkillSheet = false }
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 280)
    }

    private func appendSkill(_ raw: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }
        var cur = enabledSkillsBinding.wrappedValue
        let low = s.lowercased()
        guard !cur.contains(where: { $0.lowercased() == low }) else { return }
        cur.append(s)
        enabledSkillsBinding.wrappedValue = cur
    }

    private func appendSkills(_ ids: [String]) {
        for id in ids {
            appendSkill(id)
        }
    }

    private func removeSelectedSkill() {
        guard let sel = selectedSkill else {
            alertInfo = "Select a skill in the list first."
            return
        }
        var cur = enabledSkillsBinding.wrappedValue
        cur.removeAll { $0 == sel }
        enabledSkillsBinding.wrappedValue = cur
        selectedSkill = nil
    }

    private func configureSelectedSkill() {
        guard selectedSkill != nil else {
            alertInfo = "Select a skill from the list first."
            return
        }
        let url = GrizzyClawPaths.skillsJSON
        _ = try? GrizzyClawPaths.ensureUserDataDirectoryExists()
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "{\"skills\": {}}\n".write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        alertInfo =
            "Per-skill options are stored in ~/.grizzyclaw/skills.json (same as the Python app). "
            + "The file was revealed in Finder — open it in an editor to configure web_search, documentation, etc."
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
            Task { @MainActor in
                do {
                    let skillID = try InstalledSkillStore.importSkill(from: url)
                    appendSkill(skillID)
                    alertInfo = "Imported local skill `\(skillID)` and added it to the global defaults."
                } catch {
                    alertInfo = error.localizedDescription
                }
            }
        }
    }

    private func runInstallFromURL() async {
        installBusy = true
        defer { installBusy = false }
        let url = skillInstallURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            await MainActor.run {
                alertInfo = "Paste a GitHub repo URL (e.g. https://github.com/.../SwiftUI-Agent-Skill) and click Install."
            }
            return
        }
        do {
            let skillId = try await ClawHubPythonBridge.installSkillFromURL(url)
            await MainActor.run {
                appendSkill(skillId)
                skillInstallURL = ""
                alertInfo =
                    "Installed skill: \(skillId). It has been added to your enabled list. "
                    + "Restart the app to use it in chat if it was already running."
            }
        } catch {
            await MainActor.run {
                alertInfo = "Install failed:\n\n\(error.localizedDescription)"
            }
        }
    }

    private func runCheckUpdates() async {
        checkUpdatesBusy = true
        defer { checkUpdatesBusy = false }
        let ids = enabledSkillsBinding.wrappedValue
        let result = await ClawHubPythonBridge.checkSkillUpdates(enabledSkillIds: ids)
        await MainActor.run {
            switch result {
            case .success(let text):
                alertInfo = "Skill versions\n\n\(text)"
            case .failure(let err):
                alertInfo = err.localizedDescription
            }
        }
    }
}
