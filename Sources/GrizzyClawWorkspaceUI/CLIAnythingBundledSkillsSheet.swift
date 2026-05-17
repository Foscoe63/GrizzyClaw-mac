import GrizzyClawCore
import SwiftUI

/// Import vendored CLI-Anything `SKILL.md` packs from the app bundle into `~/.grizzyclaw/skills/`.
public struct CLIAnythingBundledSkillsSheet: View {
    @Binding var isPresented: Bool
    let onImported: (String) -> Void

    @State private var entries: [CLIAnythingBundledCatalog.Entry] = CLIAnythingBundledCatalog.loadEntries()
    @State private var importError: String?

    public init(isPresented: Binding<Bool>, onImported: @escaping (String) -> Void) {
        _isPresented = isPresented
        self.onImported = onImported
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bundled CLI-Anything skills")
                .font(.headline)
            Text(
                "These files document CLI-Anything harness workflows. Importing copies `SKILL.md` into your skills folder with a stable id so the agent can follow them even without the harness."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let importError {
                Text(importError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            List {
                ForEach(entries) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.subheadline.weight(.medium))
                            Text(entry.catalogID)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text("Folder: \(entry.folder)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button("Import") {
                            importEntry(entry)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 260)

            HStack {
                Spacer()
                Button("Close") { isPresented = false }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
    }

    private func importEntry(_ entry: CLIAnythingBundledCatalog.Entry) {
        importError = nil
        guard let url = CLIAnythingBundledCatalog.bundledSkillMarkdownURL(folder: entry.folder) else {
            importError = "Missing bundle resource for folder `\(entry.folder)`."
            return
        }
        do {
            let id = try InstalledSkillStore.importSkill(from: url, preferredID: entry.catalogID)
            onImported(id)
            isPresented = false
        } catch {
            importError = error.localizedDescription
        }
    }
}
