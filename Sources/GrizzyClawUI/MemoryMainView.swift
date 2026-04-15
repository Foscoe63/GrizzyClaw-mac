import AppKit
import GrizzyClawCore
import SwiftUI

/// Parity with Python `MemoryDialog` (`grizzyclaw/gui/memory_dialog.py`).
struct MemoryMainView: View {
    @ObservedObject var workspaceStore: WorkspaceStore
    var selectedWorkspaceId: String?
    var theme: String

    private let userId = SessionPersistence.defaultUserId

    @State private var summaryText = "Loading..."
    @State private var categoryChoices: [CategoryChoice] = [.init(tag: nil, label: "All (0)")]
    @State private var selectedCategoryTag: String?
    @State private var memories: [MemoryItemRow] = []
    @State private var selectedMemoryId: String?

    @State private var showDeleteConfirm = false
    @State private var showClearConfirm = false
    @State private var pendingDeleteId: String?
    @State private var infoAlertTitle = ""
    @State private var infoAlertMessage = ""
    @State private var showInfoAlert = false

    @Environment(\.colorScheme) private var colorScheme

    private struct CategoryChoice: Identifiable, Hashable {
        let tag: String?
        let label: String
        var id: String { "\(tag ?? "all")-\(label)" }
    }

    private var isDark: Bool {
        AppearanceTheme.isEffectivelyDark(theme: theme, colorScheme: colorScheme)
    }

    private var palette: (bg: Color, fg: Color, summaryBg: Color, border: Color, accent: Color) {
        if isDark {
            return (
                Color(red: 0.12, green: 0.12, blue: 0.12),
                Color.white,
                Color(red: 0.18, green: 0.18, blue: 0.18),
                Color(red: 0.23, green: 0.23, blue: 0.24),
                Color(red: 0.04, green: 0.52, blue: 1.0)
            )
        }
        return (
            Color.white,
            Color(red: 0.11, green: 0.11, blue: 0.12),
            Color(red: 0.96, green: 0.97, blue: 0.98),
            Color(red: 0.90, green: 0.90, blue: 0.92),
            Color(red: 0, green: 0.48, blue: 1)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(summaryText)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(palette.fg)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.summaryBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Text("Category:")
                    .foregroundStyle(palette.fg)
                Picker("", selection: $selectedCategoryTag) {
                    ForEach(categoryChoices) { choice in
                        Text(choice.label).tag(choice.tag as String?)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                Spacer()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(memories.enumerated()), id: \.element.id) { idx, row in
                        memoryRow(row)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(rowBackground(idx: idx, selected: selectedMemoryId == row.id))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedMemoryId = row.id
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.bg)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(palette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("🔄 Refresh") { refresh() }
                Button("🗑️ Delete Selected") { deleteSelectedTapped() }
                Button("🚫 Clear All") { showClearConfirm = true }
                Button("Export (JSON)") { exportJSON() }
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bg)
        .onChange(of: selectedCategoryTag) {
            refreshListOnly()
        }
        .onAppear {
            refresh()
        }
        .onChange(of: selectedWorkspaceId) {
            refresh()
        }
        .alert("Confirm Delete", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                performDeleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete this memory?")
        }
        .alert("Confirm Clear", isPresented: $showClearConfirm) {
            Button("Clear", role: .destructive) {
                performClearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clear ALL memories for this user?")
        }
        .alert(infoAlertTitle, isPresented: $showInfoAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(infoAlertMessage)
        }
    }

    private func rowBackground(idx: Int, selected: Bool) -> Color {
        if selected {
            return palette.accent.opacity(isDark ? 0.45 : 0.35)
        }
        if idx.isMultiple(of: 2) {
            return isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02)
        }
        return Color.clear
    }

    private func memoryRow(_ row: MemoryItemRow) -> some View {
        let createdStr = formatListDate(row.createdAt)
        let cat = row.category
        let content = row.content
        let preview = content.count > 120 ? String(content.prefix(120)) + "..." : content
        let line = "\(createdStr) | \(cat) | \(preview)"
        return Text(line)
            .font(.system(size: 13))
            .foregroundStyle(selectedMemoryId == row.id ? Color.white : palette.fg)
            .textSelection(.enabled)
    }

    private func formatListDate(_ d: Date?) -> String {
        guard let d else { return "Unknown" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: d)
    }

    private var workspace: WorkspaceRecord? {
        guard let id = selectedWorkspaceId,
              let idx = workspaceStore.index else { return nil }
        return idx.workspaces.first(where: { $0.id == id })
    }

    private var dbURL: URL? {
        workspace?.memoryDatabaseURL()
    }

    private func refresh() {
        guard let url = dbURL, workspace != nil else {
            summaryText = "Select a workspace in the sidebar to load memory."
            memories = []
            categoryChoices = [CategoryChoice(tag: nil, label: "All (0)")]
            return
        }
        do {
            let s = try WorkspaceMemorySQLite.loadSummary(userId: userId, dbURL: url)
            let total = s.totalItems
            let recentCount = s.recentItems.count
            summaryText = "Total Memories: \(total) | Recent: \(recentCount) | User: \(userId)"
            var choices: [CategoryChoice] = [CategoryChoice(tag: nil, label: "All (\(total))")]
            for c in s.categories {
                choices.append(CategoryChoice(tag: c.name, label: "\(c.name) (\(c.itemCount))"))
            }
            categoryChoices = choices
            if let cur = selectedCategoryTag, !choices.contains(where: { $0.tag == cur }) {
                selectedCategoryTag = nil
            }
            try refreshListOnlyCore(url: url)
        } catch {
            summaryText = "Error loading memory: \(error.localizedDescription)"
            memories = []
        }
    }

    private func refreshListOnly() {
        guard let url = dbURL else { return }
        try? refreshListOnlyCore(url: url)
    }

    private func refreshListOnlyCore(url: URL) throws {
        memories = try WorkspaceMemorySQLite.listMemories(
            userId: userId,
            limit: 50,
            category: selectedCategoryTag,
            dbURL: url
        )
        selectedMemoryId = nil
    }

    private func deleteSelectedTapped() {
        guard let id = selectedMemoryId else {
            infoAlertTitle = "No Selection"
            infoAlertMessage = "Select a memory to delete."
            showInfoAlert = true
            return
        }
        pendingDeleteId = id
        showDeleteConfirm = true
    }

    private func performDeleteSelected() {
        guard let id = pendingDeleteId, let url = dbURL else { return }
        pendingDeleteId = nil
        do {
            let ok = try WorkspaceMemorySQLite.deleteMemory(id: id, dbURL: url)
            if ok {
                refresh()
                infoAlertTitle = "Deleted"
                infoAlertMessage = "Memory deleted."
                showInfoAlert = true
            } else {
                infoAlertTitle = "Error"
                infoAlertMessage = "Delete failed."
                showInfoAlert = true
            }
        } catch {
            infoAlertTitle = "Error"
            infoAlertMessage = error.localizedDescription
            showInfoAlert = true
        }
    }

    private func performClearAll() {
        guard let url = dbURL else { return }
        do {
            let n = try WorkspaceMemorySQLite.deleteAllForUser(userId: userId, dbURL: url)
            refresh()
            infoAlertTitle = "Cleared"
            infoAlertMessage = "Cleared \(n) memories."
            showInfoAlert = true
        } catch {
            infoAlertTitle = "Error"
            infoAlertMessage = error.localizedDescription
            showInfoAlert = true
        }
    }

    private func exportJSON() {
        guard dbURL != nil else { return }
        let panel = NSSavePanel()
        panel.title = "Export memories"
        panel.nameFieldStringValue = "memories.json"
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            let payload: [String: Any] = [
                "user_id": userId,
                "memories": memories.map { m in
                    [
                        "id": m.id,
                        "user_id": m.userId,
                        "content": m.content,
                        "category": m.category,
                        "created_at": m.createdAt.map { ISO8601DateFormatter().string(from: $0) } as Any,
                    ]
                },
            ]
            do {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: dest, options: .atomic)
                DispatchQueue.main.async {
                    infoAlertTitle = "Exported"
                    infoAlertMessage = "Exported \(memories.count) memories to \(dest.path)"
                    showInfoAlert = true
                }
            } catch {
                DispatchQueue.main.async {
                    infoAlertTitle = "Export error"
                    infoAlertMessage = error.localizedDescription
                    showInfoAlert = true
                }
            }
        }
    }
}
