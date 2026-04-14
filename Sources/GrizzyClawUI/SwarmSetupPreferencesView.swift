import AppKit
import GrizzyClawCore
import SwiftUI

/// Python `SwarmSetupTab` — Leader + specialists, presets, channel, apply to `workspaces.json`.
public struct SwarmSetupPreferencesView: View {
    @ObservedObject var workspaceStore: WorkspaceStore

    @State private var presetIndex = 0
    @State private var softwareRoster: Set<String> = Set(SwarmSetupModels.softwareOrder)
    @State private var personalRoster: Set<String> = Set(SwarmSetupModels.personalOrder)
    @State private var hybridRoster: Set<String> = Set(SwarmSetupModels.hybridOrder)
    @State private var channelText = "default"
    @State private var applyPrompts = true
    @State private var leaderAutoDelegate = true
    @State private var leaderConsensus = true
    @State private var statusText = ""
    @State private var applyError: String?

    private let intro =
        "Create or update workspaces for a Leader + specialists on one inter-agent channel. "
        + "Delegations use @workspace_slug from each workspace name (e.g. @planning_assistant, @code_assistant)."

    public init(workspaceStore: WorkspaceStore) {
        self.workspaceStore = workspaceStore
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(intro)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                settingsSection
                readinessSection
                agentsSection

                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Copy test prompt") {
                        copyTestPrompt()
                    }
                    .disabled(!hasManager || !canCopyTest)
                    Spacer()
                    Button("Apply setup") {
                        applySetup()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasManager)
                }

                if !hasManager {
                    Text("Workspaces are not available in this context.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: .systemOrange))
                }

                if let applyError {
                    Text(applyError)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }
            .padding(EdgeInsets(top: 24, leading: 40, bottom: 24, trailing: 40))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if workspaceStore.index == nil {
                workspaceStore.reload()
            }
        }
    }

    private var hasManager: Bool {
        workspaceStore.index != nil
    }

    private var rosterKeys: [String] {
        SwarmSetupModels.presetRosterKeys(presetIndex: presetIndex)
    }

    private var managedKinds: [SwarmSetupModels.SwarmKind] {
        SwarmSetupModels.managedKinds(
            presetIndex: presetIndex,
            softwareRoster: softwareRoster,
            personalRoster: personalRoster,
            hybridRoster: hybridRoster
        )
    }

    private var canCopyTest: Bool {
        managedKinds.contains { $0 != .leader }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)
            Picker("Preset", selection: $presetIndex) {
                Text("Software factory").tag(0)
                Text("Personal assistant").tag(1)
                Text("Hybrid (both)").tag(2)
            }
            .pickerStyle(.menu)

            Text("Each preset has its own specialist checklist. Leader is always included.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(rosterKeys, id: \.self) { key in
                    Toggle(SwarmSetupModels.checkboxLabel(kind: key), isOn: rosterBinding(for: key))
                }
            }
            .padding(.top, 4)

            Button("Restore default rosters (all three presets)") {
                softwareRoster = Set(SwarmSetupModels.softwareOrder)
                personalRoster = Set(SwarmSetupModels.personalOrder)
                hybridRoster = Set(SwarmSetupModels.hybridOrder)
            }
            .buttonStyle(.plain)
            .foregroundStyle(PreferencesTheme.accentPurple)

            HStack {
                Text("Inter-agent channel:")
                TextField("default", text: $channelText)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Apply / update system prompts for touched workspaces", isOn: $applyPrompts)

            Text("Leader policy")
                .font(.subheadline.weight(.semibold))
            Toggle("Auto-delegate when the Leader uses @mentions in replies", isOn: $leaderAutoDelegate)
            Toggle("Consensus: merge specialist replies and synthesize", isOn: $leaderConsensus)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func rosterBinding(for key: String) -> Binding<Bool> {
        switch presetIndex {
        case 0:
            return Binding(
                get: { softwareRoster.contains(key) },
                set: { on in
                    if on { softwareRoster.insert(key) } else { softwareRoster.remove(key) }
                }
            )
        case 1:
            return Binding(
                get: { personalRoster.contains(key) },
                set: { on in
                    if on { personalRoster.insert(key) } else { personalRoster.remove(key) }
                }
            )
        default:
            return Binding(
                get: { hybridRoster.contains(key) },
                set: { on in
                    if on { hybridRoster.insert(key) } else { hybridRoster.remove(key) }
                }
            )
        }
    }

    private var readinessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Readiness")
                .font(.headline)
            let wss = workspaceStore.index?.workspaces ?? []
            readinessRow(title: "Channel", value: SwarmReadiness.channelLabel(channelText))
            readinessRow(title: "Leader on channel", value: SwarmReadiness.leaderOnChannel(workspaces: wss, channelRaw: channelText))
            readinessRow(title: "Specialists on channel", value: SwarmReadiness.specialistCount(workspaces: wss, channelRaw: channelText))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func readinessRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title + ":")
                .frame(width: 160, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
            Spacer()
        }
    }

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agents that will be created or updated")
                .font(.headline)

            let kinds = managedKinds
            if kinds.filter({ $0 != .leader }).isEmpty {
                Text("No specialists selected — only the Leader will be created or updated.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: .systemOrange))
            }

            ForEach(kinds, id: \.rawValue) { kind in
                agentRow(kind: kind)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func agentRow(kind: SwarmSetupModels.SwarmKind) -> some View {
        let meta = SwarmSetupModels.specMeta(kind)
        let exists = workspaceStore.index?.workspaces.contains(where: { $0.name == meta.displayName }) ?? false
        let status = exists ? "Will update swarm settings" : "Will create"
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(meta.displayName)
                    .fontWeight(.semibold)
                Spacer()
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text("\(meta.description)  •  Template: \(meta.templateKey)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copyTestPrompt() {
        applyError = nil
        let kinds = managedKinds
        guard let firstSpec = kinds.first(where: { $0 != .leader }) else {
            statusText = "Add at least one specialist to generate a test prompt."
            return
        }
        let meta = SwarmSetupModels.specMeta(firstSpec)
        let display = meta.displayName
        let slug: String
        if let ws = workspaceStore.index?.workspaces.first(where: { $0.name == display }) {
            slug = SwarmSetupModels.mentionSlug(displayName: ws.name)
        } else {
            slug = SwarmSetupModels.mentionSlug(displayName: display)
        }
        let text = "@\(slug) Reply with exactly: SWARM_DELEGATION_OK (GrizzyClaw swarm test)."
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusText = "Copied test prompt to clipboard. Paste in the Leader workspace chat after Apply."
    }

    private func applySetup() {
        applyError = nil
        statusText = ""
        do {
            let r = try workspaceStore.applySwarmSetup(
                presetIndex: presetIndex,
                softwareRoster: softwareRoster,
                personalRoster: personalRoster,
                hybridRoster: hybridRoster,
                channel: channelText,
                applyPrompts: applyPrompts,
                leaderAutoDelegate: leaderAutoDelegate,
                leaderConsensus: leaderConsensus
            )
            statusText =
                "Applied. Created \(r.created), updated \(r.updated). "
                + "Channel \"\(r.channel)\" — delegate from the Leader with @mentions matching workspace slugs."
        } catch {
            applyError = error.localizedDescription
        }
    }
}
