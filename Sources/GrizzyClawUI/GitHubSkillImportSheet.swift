import GrizzyClawCore
import SwiftUI

struct GitHubSkillImportSheet: View {
    @Binding var isPresented: Bool
    let onImportedSkillIDs: ([String]) -> Void

    @State private var githubURL = ""
    @State private var fetchBusy = false
    @State private var importBusy = false
    @State private var previews: [GitHubSkillPreview] = []
    @State private var selectedPreviewIDs = Set<String>()
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import skills from GitHub")
                .font(.headline)

            Text("Paste a GitHub repository URL or a raw `SKILL.md` URL. Repositories with `.claude-plugin/marketplace.json` can import multiple skills, similar to Osaurus.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField("https://github.com/owner/repo", text: $githubURL)
                    .textFieldStyle(.roundedBorder)
                Button(fetchBusy ? "Loading…" : "Fetch") {
                    Task { await fetchPreviews() }
                }
                .disabled(fetchBusy || importBusy || githubURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if previews.isEmpty {
                Text("No GitHub skills loaded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List(previews, selection: Binding(
                    get: { selectedPreviewIDs },
                    set: { selectedPreviewIDs = $0 }
                )) { preview in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selectedPreviewIDs.contains(preview.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedPreviewIDs.contains(preview.id) ? Color.accentColor : Color.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preview.title)
                                .font(.body.weight(.medium))
                            Text(preview.suggestedSkillID)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            if !preview.description.isEmpty {
                                Text(preview.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(preview.sourceLabel)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedPreviewIDs.contains(preview.id) {
                            selectedPreviewIDs.remove(preview.id)
                        } else {
                            selectedPreviewIDs.insert(preview.id)
                        }
                    }
                }
                .frame(minHeight: 220)
            }

            HStack {
                Button("Select all") {
                    selectedPreviewIDs = Set(previews.map(\.id))
                }
                .disabled(previews.isEmpty)

                Button("Clear") {
                    selectedPreviewIDs.removeAll()
                }
                .disabled(selectedPreviewIDs.isEmpty)

                Spacer()

                Button("Close") {
                    isPresented = false
                }

                Button(importBusy ? "Importing…" : "Import Selected") {
                    Task { await importSelected() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(importBusy || selectedPreviewIDs.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 480)
    }

    private func fetchPreviews() async {
        fetchBusy = true
        defer { fetchBusy = false }
        errorMessage = nil
        do {
            let loaded = try await GitHubSkillImportService.fetchSkills(from: githubURL)
            previews = loaded
            selectedPreviewIDs = Set(loaded.map(\.id))
        } catch {
            previews = []
            selectedPreviewIDs = []
            errorMessage = error.localizedDescription
        }
    }

    private func importSelected() async {
        importBusy = true
        defer { importBusy = false }
        errorMessage = nil
        do {
            let chosen = previews.filter { selectedPreviewIDs.contains($0.id) }
            let importedIDs = try chosen.map { preview in
                try InstalledSkillStore.installMarkdown(preview.markdown, preferredID: preview.suggestedSkillID)
            }
            onImportedSkillIDs(importedIDs)
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
