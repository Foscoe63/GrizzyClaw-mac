import Foundation

/// One-step setup for **real** Osaurus-style macOS tools via the [Macuse](https://macuse.app) MCP server (stdio).
/// This does not install the app; it only adds a `grizzyclaw.json` row when missing.
public enum OsaurusParityMCPSetup {
    public static let macuseAppBundleExecutable =
        "/Applications/Macuse.app/Contents/MacOS/macuse"

    /// Standard MCP row matching Macuse docs (`macuse mcp`).
    public static func macuseServerRow(enabled: Bool = true) -> MCPServerRow {
        MCPServerRow(
            name: "macuse",
            enabled: enabled,
            dictionary: [
                "command": macuseAppBundleExecutable,
                "args": ["mcp"],
            ]
        )
    }

    /// `true` if the default Macuse install path exists.
    public static func isMacuseInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: macuseAppBundleExecutable)
    }

    /// Appends the Macuse server if no row named `macuse` (case-insensitive) exists. Sorts by name.
    @discardableResult
    public static func appendMacuseIfMissing(servers: inout [MCPServerRow]) -> Bool {
        if servers.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "macuse" }) {
            return false
        }
        servers.append(macuseServerRow())
        servers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return true
    }

    /// Single-server JSON fragment for pasting into `grizzyclaw.json` under `mcpServers` (merge manually).
    public static func macuseMCPFragmentJSONForPasteboard() -> String {
        """
        "macuse": {
          "command": "\(macuseAppBundleExecutable)",
          "args": ["mcp"],
          "enabled": true
        }
        """
    }
}
