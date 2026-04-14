import GrizzyClawCore
import SwiftUI

/// Parity with Python `UsageDashboardDialog` (`usage_dashboard_dialog.py`): global metrics, per-workspace table,
/// 2s refresh, benchmark button. Native app aggregates token/latency totals from `workspaces.json`.
public struct UsageDashboardMainView: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject public var workspaceStore: WorkspaceStore
    @ObservedObject public var configStore: ConfigStore
    @ObservedObject public var chatSession: ChatSessionModel
    @Binding public var selectedWorkspaceId: String?

    @State private var benchmarkBusy = false
    @State private var benchmarkResult = ""

    public init(
        workspaceStore: WorkspaceStore,
        configStore: ConfigStore,
        chatSession: ChatSessionModel,
        selectedWorkspaceId: Binding<String?>
    ) {
        self.workspaceStore = workspaceStore
        self.configStore = configStore
        self.chatSession = chatSession
        self._selectedWorkspaceId = selectedWorkspaceId
    }

    public var body: some View {
        let c = Self.palette(theme: configStore.snapshot.theme, colorScheme: colorScheme)
        VStack(alignment: .leading, spacing: 16) {
            Text("Usage Dashboard")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(c.fg)

            globalSection(c: c)

            workspaceSection(c: c)

            HStack(spacing: 12) {
                Button("Run benchmark (active workspace)") {
                    runBenchmark()
                }
                .disabled(benchmarkBusy)

                Text(benchmarkResult)
                    .font(.system(size: 12))
                    .foregroundStyle(c.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 480, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(c.bg)
        .onAppear {
            workspaceStore.reload()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            workspaceStore.reload()
        }
    }

    /// Mirrors `_get_theme_colors` in `usage_dashboard_dialog.py`.
    private static func palette(theme: String, colorScheme: ColorScheme) -> (bg: Color, fg: Color, border: Color, secondary: Color) {
        let dark = AppearanceTheme.isEffectivelyDark(theme: theme, colorScheme: colorScheme)
        if dark {
            return (
                Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255),
                Color.white,
                Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255),
                Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
            )
        }
        return (
            Color.white,
            Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255),
            Color(red: 229 / 255, green: 229 / 255, blue: 234 / 255),
            Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
        )
    }

    @ViewBuilder
    private func globalSection(c: (bg: Color, fg: Color, border: Color, secondary: Color)) -> some View {
        let g = globalAggregates
        VStack(alignment: .leading, spacing: 10) {
            Text("Global (this session)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(c.fg)
            VStack(alignment: .leading, spacing: 8) {
                metricRow(c: c, label: "Tokens in:", value: g.tokensIn > 0 ? formatInt(g.tokensIn) : "—")
                metricRow(c: c, label: "Tokens out:", value: g.tokensOut > 0 ? formatInt(g.tokensOut) : "—")
                metricRow(c: c, label: "Latency (mean):", value: g.latencyMeanMs.map { String(format: "%.0f ms", $0) } ?? "—")
                metricRow(c: c, label: "Latency (p99):", value: "—")
                metricRow(c: c, label: "Error rate:", value: "—")
                metricRow(c: c, label: "Est. cost:", value: g.estCost.map { String(format: "$%.4f", $0) } ?? "—")
            }
            Text(
                "Totals are summed from workspace records in workspaces.json. In-process LLM metrics (Python observability) are not available in the native app."
            )
            .font(.system(size: 11))
            .foregroundStyle(c.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(c.border, lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 8).fill(c.bg))
        )
    }

    private func metricRow(
        c: (bg: Color, fg: Color, border: Color, secondary: Color),
        label: String,
        value: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(c.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(c.fg)
            Spacer()
        }
    }

    private struct WorkspaceTableRow: Identifiable {
        let id: String
        let title: String
        let messages: Int
        let avgMs: Double
        let totalTokens: Int
        let quality: String
    }

    @ViewBuilder
    private func workspaceSection(c: (bg: Color, fg: Color, border: Color, secondary: Color)) -> some View {
        let rows = workspaceRows
        VStack(alignment: .leading, spacing: 10) {
            Text("Per-workspace (speed / quality)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(c.fg)
            Table(rows) {
                TableColumn("Workspace") { r in
                    Text(r.title).foregroundStyle(c.fg)
                }
                TableColumn("Messages") { r in
                    Text("\(r.messages)").foregroundStyle(c.fg)
                }
                .width(80)
                TableColumn("Avg response (ms)") { r in
                    Text(String(format: "%.0f", r.avgMs)).foregroundStyle(c.fg)
                }
                .width(120)
                TableColumn("Total tokens") { r in
                    Text(formatInt(r.totalTokens)).foregroundStyle(c.fg)
                }
                TableColumn("Quality %") { r in
                    Text(r.quality).foregroundStyle(c.fg)
                }
            }
            .frame(minHeight: 180)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(c.border, lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 8).fill(c.bg))
        )
    }

    private var workspaceRows: [WorkspaceTableRow] {
        let list = workspaceStore.index?.workspaces ?? []
        return list.map { w in
            let msgs = w.messageCount ?? 0
            let avg = msgs > 0 ? (w.totalResponseTimeMs ?? 0) / Double(msgs) : 0
            let tok = (w.totalInputTokens ?? 0) + (w.totalOutputTokens ?? 0)
            let up = w.feedbackUp ?? 0
            let down = w.feedbackDown ?? 0
            let totalFb = up + down
            let q: String = totalFb > 0
                ? String(format: "%.1f%%", Double(up) / Double(totalFb) * 100)
                : "N/A"
            let icon = (w.icon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let title = icon.isEmpty ? w.name : "\(icon) \(w.name)"
            return WorkspaceTableRow(
                id: w.id,
                title: title,
                messages: msgs,
                avgMs: avg,
                totalTokens: tok,
                quality: q
            )
        }
    }

    private struct GlobalAgg {
        var tokensIn: Int
        var tokensOut: Int
        var latencyMeanMs: Double?
        var estCost: Double?
    }

    private var globalAggregates: GlobalAgg {
        let list = workspaceStore.index?.workspaces ?? []
        var tin = 0
        var tout = 0
        var sumRt = 0.0
        var sumMsgs = 0
        for w in list {
            tin += w.totalInputTokens ?? 0
            tout += w.totalOutputTokens ?? 0
            let m = w.messageCount ?? 0
            if m > 0 {
                sumRt += w.totalResponseTimeMs ?? 0
                sumMsgs += m
            }
        }
        let mean: Double? = sumMsgs > 0 ? sumRt / Double(sumMsgs) : nil
        let cost: Double? = (tin + tout) > 0 ? Self.estimateCost(tokensIn: tin, tokensOut: tout) : nil
        return GlobalAgg(tokensIn: tin, tokensOut: tout, latencyMeanMs: mean, estCost: cost)
    }

    /// Python `_estimate_cost`.
    private static func estimateCost(tokensIn: Int, tokensOut: Int) -> Double {
        Double(tokensIn) / 1_000_000.0 * 0.5 + Double(tokensOut) / 1_000_000.0 * 1.5
    }

    private func formatInt(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func runBenchmark() {
        benchmarkResult = "Running…"
        benchmarkBusy = true
        let cs = chatSession
        Task {
            let result = await cs.runUsageBenchmark(
                workspaceStore: workspaceStore,
                configStore: configStore,
                selectedWorkspaceId: selectedWorkspaceId,
                guiLlmOverride: nil as GuiChatPreferences.LLM?
            )
            await MainActor.run {
                benchmarkBusy = false
                switch result {
                case .succeeded(let elapsedMs, let approxTokens):
                    benchmarkResult = String(format: "Done: %.0f ms, ~%d tokens", elapsedMs, approxTokens)
                case .failed(let err):
                    benchmarkResult = "Error: \(String(err.prefix(80)))"
                }
                workspaceStore.reload()
            }
        }
    }
}
