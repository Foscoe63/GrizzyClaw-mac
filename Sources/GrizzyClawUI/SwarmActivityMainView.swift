import AppKit
import GrizzyClawCore
import SwiftUI

/// Parity with Python `SwarmActivityDialog` (`swarm_activity_dialog.py`): 16pt margins, 11px gray hint,
/// `QListWidget` + alternating rows, Refresh left + stretch — native colors (no custom hex sheet like Sessions).
public struct SwarmActivityMainView: View {
    @State private var lines: [String] = []
    @State private var refreshTask: Task<Void, Never>?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent swarm events (delegations, claims, consensus).")
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            List {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowBackground(alternatingRowBackground(index: index))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button("Refresh") {
                    refresh()
                }
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            refresh()
        }
        .onDisappear {
            refreshTask?.cancel()
        }
    }

    private func alternatingRowBackground(index: Int) -> Color {
        let colors = NSColor.alternatingContentBackgroundColors
        guard !colors.isEmpty else { return Color.clear }
        return Color(nsColor: colors[index % colors.count])
    }

    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            let result = await GatewaySessionsClient.fetchSwarmHistory(limit: 50)
            await MainActor.run {
                switch result {
                case .success(let rows):
                    lines = rows
                case .failure(let err):
                    lines = ["Daemon not reachable: \(err.message)"]
                }
            }
        }
    }
}
