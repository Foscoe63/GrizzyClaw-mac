import AppKit
import GrizzyClawCore
import SwiftUI

/// Parity with Python `SubagentsDialog` (`grizzyclaw/gui/subagents_dialog.py`): title `Sub-agents`, 620×480 min,
/// 16pt margins, hint + specialist lines, tabs **Active** / **Completed** with "Active runs" / "Recently completed",
/// **Kill selected**, **Refresh**, debug line; refresh every 2s while open (`QTimer` 2000ms).
public struct SubagentsMainView: View {
    @ObservedObject public var configStore: ConfigStore

    @State private var state: GatewaySessionsClient.SubagentsGatewayState?
    @State private var loadError: String?
    @State private var selectedActiveIndex: Int?
    @State private var refreshTask: Task<Void, Never>?

    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    private var authToken: String? {
        guard let raw = configStore.snapshot.gatewayAuthToken else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    public init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(
                "Sub-agents are background runs spawned by the agent (SPAWN_SUBAGENT). "
                    + "Active and completed runs from all workspaces are listed. "
                    + "Enable in Workspaces → Edit → Swarm / Sub-agents."
            )
            .font(.system(size: 11))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .fixedSize(horizontal: false, vertical: true)

            Text(specialistText)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)

            TabView {
                activeTab
                    .tabItem { Text("Active") }

                completedTab
                    .tabItem { Text("Completed") }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button("Refresh") {
                    refresh()
                }
                Spacer()
            }

            Text(debugText)
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: .quaternaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
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
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            refresh()
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private var specialistText: String {
        state?.specialistAvailability ?? "Specialist availability: —"
    }

    private var debugText: String {
        if let e = loadError { return e }
        return state?.debugLine ?? ""
    }

    private var activeTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Active runs")
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .labelColor))

            List(selection: $selectedActiveIndex) {
                ForEach(Array(activeRowIndices), id: \.self) { index in
                    Text(activeLine(at: index))
                        .font(.system(size: 13))
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .listRowBackground(alternatingRowBackground(index: index))
                        .tag(Optional(index))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            HStack {
                Button("Kill selected") {
                    killSelected()
                }
                Spacer()
            }
        }
    }

    private var completedTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recently completed")
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .labelColor))

            List {
                ForEach(Array(completedRowIndices), id: \.self) { index in
                    Text(completedLines[index])
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
        }
    }

    private var activeLines: [String] {
        state?.activeLines ?? []
    }

    private var completedLines: [String] {
        state?.completedLines ?? []
    }

    private var activeRowIndices: [Int] {
        Array(activeLines.indices)
    }

    private var completedRowIndices: [Int] {
        Array(completedLines.indices)
    }

    private func activeLine(at index: Int) -> String {
        guard index >= 0, index < activeLines.count else { return "" }
        return activeLines[index]
    }

    private func alternatingRowBackground(index: Int) -> Color {
        let colors = NSColor.alternatingContentBackgroundColors
        guard !colors.isEmpty else { return Color.clear }
        return Color(nsColor: colors[index % colors.count])
    }

    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            let result = await GatewaySessionsClient.fetchSubagentsState()
            await MainActor.run {
                switch result {
                case .success(let s):
                    loadError = nil
                    state = s
                    if let sel = selectedActiveIndex, sel >= s.activeLines.count {
                        selectedActiveIndex = nil
                    }
                case .failure(let err):
                    loadError = "Daemon not reachable: \(err.message)"
                    state = nil
                }
            }
        }
    }

    private func killSelected() {
        guard let idx = selectedActiveIndex else {
            alertTitle = "Sub-agents"
            alertMessage = "Select an active run to kill."
            showAlert = true
            return
        }
        guard let ids = state?.activeRunIds, idx < ids.count else { return }
        let runId = ids[idx]
        guard !runId.isEmpty else { return }

        refreshTask?.cancel()
        refreshTask = Task {
            let result = await GatewaySessionsClient.killSubagentRun(runId: runId, authToken: authToken)
            await MainActor.run {
                switch result {
                case .success:
                    refresh()
                    alertTitle = "Sub-agents"
                    alertMessage = "Cancel requested for run \(runId). It will stop when it next checks."
                    showAlert = true
                case .failure(let err):
                    alertTitle = "Sub-agents"
                    alertMessage = err.message
                    showAlert = true
                }
            }
        }
    }
}
