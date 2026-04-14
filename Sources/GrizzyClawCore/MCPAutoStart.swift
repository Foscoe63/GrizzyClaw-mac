import Foundation

/// Starts local MCP stdio processes for every **enabled** server row that has a `command`, so a state that matches
/// “checkbox on + green” survives app restarts (processes always die on quit; this restores them).
@MainActor
public enum MCPAutoStart {
    private static var didRunThisProcess = false

    /// Call once after `config.yaml` is loaded (e.g. main window `onAppear`). Safe to call multiple times; only the first run starts servers.
    public static func startEnabledLocalServersIfNeeded(mcpServersFile configPath: String) {
        if didRunThisProcess { return }
        didRunThisProcess = true
        let path = configPath
        Task {
            await startEnabledLocalServers(mcpServersFile: path)
        }
    }

    /// Loads `grizzyclaw.json` MCP table and starts each enabled row that defines a local `command`.
    public static func startEnabledLocalServers(mcpServersFile configPath: String) async {
        let url = MCPServersFileIO.resolveJSONURL(mcpServersFile: configPath)
        let rows: [MCPServerRow]
        do {
            rows = try MCPServersFileIO.load(url: url)
        } catch {
            GrizzyClawLog.error("MCP auto-start: could not load MCP file: \(error.localizedDescription)")
            return
        }

        for row in rows where row.enabled {
            let d = row.dictionary
            let cmd = (d["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !cmd.isEmpty else { continue }

            if MCPLocalMCPProcessController.shared.isTrackedRunning(name: row.name) {
                continue
            }
            let rec = row.mergedRecord()
            do {
                try await MCPLocalMCPProcessController.shared.start(serverData: rec)
                GrizzyClawLog.debug("MCP auto-start: started \(row.name)")
            } catch {
                GrizzyClawLog.error("MCP auto-start: \(row.name) failed — \(error.localizedDescription)")
            }
        }
    }
}
