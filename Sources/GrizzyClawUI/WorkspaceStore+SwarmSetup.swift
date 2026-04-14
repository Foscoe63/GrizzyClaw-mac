import Foundation
import GrizzyClawCore

public struct SwarmApplyResult: Sendable {
    public let created: Int
    public let updated: Int
    public let channel: String
}

extension WorkspaceStore {
    /// Python `SwarmSetupTab._apply` — batch create/update; does not change active workspace when creating.
    public func applySwarmSetup(
        presetIndex: Int,
        softwareRoster: Set<String>,
        personalRoster: Set<String>,
        hybridRoster: Set<String>,
        channel: String,
        applyPrompts: Bool,
        leaderAutoDelegate: Bool,
        leaderConsensus: Bool
    ) throws -> SwarmApplyResult {
        let kinds = SwarmSetupModels.managedKinds(
            presetIndex: presetIndex,
            softwareRoster: softwareRoster,
            personalRoster: personalRoster,
            hybridRoster: hybridRoster
        )
        let ch = SwarmSetupModels.channelNormalized(channel)

        try GrizzyClawPaths.ensureUserDataDirectoryExists()
        let url = GrizzyClawPaths.workspacesJSON
        var file = try WorkspaceIndexLoader.loadFile(from: url)
        if file.workspaces.isEmpty {
            try WorkspaceBootstrap.writePythonDefaultWorkspacesFile(to: url)
            file = try WorkspaceIndexLoader.loadFile(from: url)
        }

        var created = 0
        var updated = 0

        for kind in kinds {
            let meta = SwarmSetupModels.specMeta(kind)
            let display = meta.displayName
            let templateKey = meta.templateKey

            if let existing = file.workspaces.first(where: { $0.name == display }) {
                var patch: [String: JSONValue] = [
                    "enable_inter_agent": .bool(true),
                    "inter_agent_channel": .string(ch),
                    "use_shared_memory": .bool(true),
                ]
                if kind == .leader {
                    patch["swarm_auto_delegate"] = .bool(leaderAutoDelegate)
                    patch["swarm_consensus"] = .bool(leaderConsensus)
                } else {
                    patch["swarm_auto_delegate"] = .bool(false)
                    patch["swarm_consensus"] = .bool(false)
                }
                if applyPrompts {
                    patch["system_prompt"] = .string(try SwarmSetupModels.effectiveSystemPrompt(for: kind))
                }

                let mergedConfig = Self.mergeConfigForSwarm(existing.config, patch: patch)
                let newDesc: String? = applyPrompts ? meta.description : existing.description

                guard let idx = file.workspaces.firstIndex(where: { $0.id == existing.id }) else { continue }
                let old = file.workspaces[idx]
                file.workspaces[idx] = old.updatingEditor(
                    name: old.name,
                    description: newDesc,
                    icon: old.icon ?? "🤖",
                    color: old.color ?? "#007AFF",
                    order: old.order ?? idx,
                    avatarPath: old.avatarPath,
                    config: mergedConfig
                )
                updated += 1
            } else {
                var base = try SwarmWorkspaceTemplateCatalog.configObject(forTemplateKey: templateKey)
                base["enable_inter_agent"] = .bool(true)
                base["inter_agent_channel"] = .string(ch)
                base["use_shared_memory"] = .bool(true)
                if kind == .leader {
                    base["swarm_auto_delegate"] = .bool(leaderAutoDelegate)
                    base["swarm_consensus"] = .bool(leaderConsensus)
                } else {
                    base["swarm_auto_delegate"] = .bool(false)
                    base["swarm_consensus"] = .bool(false)
                }
                if applyPrompts {
                    base["system_prompt"] = .string(try SwarmSetupModels.effectiveSystemPrompt(for: kind))
                }

                let desc: String? = applyPrompts ? meta.description : nil
                let ic = SwarmSetupModels.templateIconColor(templateKey: templateKey)

                let newId = String(UUID().uuidString.prefix(8)).lowercased()
                let ws = WorkspaceRecord.makeNew(
                    id: newId,
                    name: display,
                    description: desc,
                    icon: ic.icon,
                    color: ic.color,
                    order: file.workspaces.count,
                    config: .object(base)
                )
                file.workspaces.append(ws)
                created += 1
            }
        }

        try WorkspaceIndexLoader.save(file, to: url)
        reload()
        return SwarmApplyResult(created: created, updated: updated, channel: ch)
    }

    private static func mergeConfigForSwarm(_ existing: JSONValue?, patch: [String: JSONValue]) -> JSONValue {
        var dict: [String: JSONValue] = [:]
        if case .object(let o) = existing {
            dict = o
        }
        for (k, v) in patch {
            if case .null = v {
                dict.removeValue(forKey: k)
            } else {
                dict[k] = v
            }
        }
        return .object(dict)
    }
}
