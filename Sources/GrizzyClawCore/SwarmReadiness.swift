import Foundation

/// Python `SwarmSetupTab._refresh_readiness` / `_ws_on_channel`.
public enum SwarmReadiness {
    public static func channelLabel(_ raw: String) -> String {
        SwarmSetupModels.channelNormalized(raw)
    }

    public static func leaderOnChannel(workspaces: [WorkspaceRecord], channelRaw: String) -> String {
        let ch = SwarmSetupModels.channelNormalized(channelRaw)
        var leaders = 0
        for ws in workspaces {
            guard wsOnChannel(ws, chNorm: ch) else { continue }
            let role = (ws.config?.string(forKey: "swarm_role") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if role == "leader" { leaders += 1 }
        }
        return leaders > 0 ? "Yes" : "No"
    }

    public static func specialistCount(workspaces: [WorkspaceRecord], channelRaw: String) -> String {
        let ch = SwarmSetupModels.channelNormalized(channelRaw)
        var specs = 0
        for ws in workspaces {
            guard wsOnChannel(ws, chNorm: ch) else { continue }
            let role = (ws.config?.string(forKey: "swarm_role") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if role.isEmpty || role.lowercased() == "none" { continue }
            if role == "leader" { continue }
            specs += 1
        }
        return String(specs)
    }

    private static func wsOnChannel(_ ws: WorkspaceRecord, chNorm: String) -> Bool {
        guard let cfg = ws.config else { return false }
        guard cfg.bool(forKey: "enable_inter_agent") == true else { return false }
        let raw = cfg.string(forKey: "inter_agent_channel") ?? ""
        let wch = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let eff = wch.isEmpty ? "default" : wch
        return eff == chNorm
    }
}
