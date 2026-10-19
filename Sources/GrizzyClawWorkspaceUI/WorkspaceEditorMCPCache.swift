import Foundation
import GrizzyClawCore

/// In-session MCP discovery cache (per workspace id); survives tab switches, lost on quit.
@MainActor
public enum WorkspaceEditorMCPCache {
    public static var discovery: [String: [String: [MCPToolDescriptor]]] = [:]
}
