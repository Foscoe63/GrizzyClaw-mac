import Foundation
import GrizzyClawCore
import SwiftUI

/// In-memory + disk prefs for chat composer (Python `gui_chat_prefs.json`).
@MainActor
public final class GuiChatPrefsStore: ObservableObject {
    @Published public private(set) var preferences: GuiChatPreferences
    /// `server + "\u{1E}" + tool` → enabled (default true when unknown = all on).
    @Published public private(set) var toolSwitch: [String: Bool] = [:]
    @Published public private(set) var lastDiscovery: MCPToolsDiscoveryResult?

    public init() {
        preferences = GuiChatPreferences.load()
        rebuildToolSwitchFromPreferences()
    }

    public static let pairSeparator: String = "\u{1E}"

    public static func pairKey(server: String, tool: String) -> String {
        let normalizedServer = server
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\[.*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTool = tool
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\[.*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedServer + pairSeparator + normalizedTool
    }

    public func modelButtonTitle() -> String {
        guard let p = preferences.llm?.provider?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty else {
            return "Default — app settings"
        }
        let m = preferences.llm?.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return m.isEmpty ? "\(p) → default" : "\(p) → \(m)"
    }

    /// Python `tools_menu_btn`: `"Tools ▾"` or `"Tools (filtered) ▾"` when any switch is off (`_tools_filtered`).
    public func toolsButtonTitle(effectiveDiscovery: MCPToolsDiscoveryResult?) -> String {
        guard let disc = effectiveDiscovery, !disc.servers.isEmpty else {
            return "Tools ▾"
        }
        for (srv, tools) in disc.servers {
            for t in tools {
                if !isToolOn(server: srv, tool: t.name) {
                    return "Tools (filtered) ▾"
                }
            }
        }
        return "Tools ▾"
    }

    /// Transcript after MCP tools: assistant-only (default), tool output only, or both.
    public var mcpTranscriptMode: GuiChatPreferences.McpTranscriptMode {
        preferences.mcpTranscriptMode ?? .assistant
    }

    public func setMcpTranscriptMode(_ mode: GuiChatPreferences.McpTranscriptMode) {
        var p = preferences
        p.mcpTranscriptMode = mode
        preferences = p
        persist()
    }

    public func mcpTranscriptModeMenuLabel() -> String {
        switch mcpTranscriptMode {
        case .assistant: return "Assistant"
        case .tool: return "Tool output"
        case .both: return "Both"
        }
    }

    /// Short token for narrow composer toolbar (MCP transcript `Menu` label).
    public func mcpTranscriptModeCompactToken() -> String {
        switch mcpTranscriptMode {
        case .assistant: return "Asst"
        case .tool: return "Tool"
        case .both: return "Both"
        }
    }

    public var mcpAutoFollowActions: Bool {
        preferences.mcpAutoFollowActions ?? true
    }

    public func setMcpAutoFollowActions(_ enabled: Bool) {
        var p = preferences
        p.mcpAutoFollowActions = enabled
        preferences = p
        persist()
    }

    public func resolverLlmOverride() -> GuiChatPreferences.LLM? {
        guard let p = preferences.llm?.provider?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty else {
            return nil
        }
        let m = preferences.llm?.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        return GuiChatPreferences.LLM(provider: p, model: (m?.isEmpty ?? true) ? nil : m)
    }

    public func setLlmDefault() {
        var snap = preferences
        snap.llm = nil
        preferences = snap
        persist()
    }

    public func setLlm(provider: String, model: String?) {
        let p = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else {
            setLlmDefault()
            return
        }
        let m = model?.trimmingCharacters(in: .whitespacesAndNewlines)
        var snap = preferences
        snap.llm = GuiChatPreferences.LLM(provider: p, model: (m?.isEmpty ?? true) ? nil : m)
        preferences = snap
        persist()
    }

    public func setToolEnabled(server: String, tool: String, enabled: Bool) {
        let k = Self.pairKey(server: server, tool: tool)
        toolSwitch[k] = enabled
        persistToolPairsOnly()
        objectWillChange.send()
    }

    /// When `usingDiscovery` is set (merged internal tools + workspace filter), only those rows are toggled — Python `ToolsPickerPopup` switches.
    public func toolsEnableAll(usingDiscovery disc: MCPToolsDiscoveryResult? = nil) {
        let d = disc ?? lastDiscovery
        guard let d, !d.servers.isEmpty else { return }
        for (srv, tools) in d.servers {
            for t in tools {
                toolSwitch[Self.pairKey(server: srv, tool: t.name)] = true
            }
        }
        persistToolPairsOnly()
        objectWillChange.send()
    }

    public func toolsDisableAll(usingDiscovery disc: MCPToolsDiscoveryResult? = nil) {
        let d = disc ?? lastDiscovery
        guard let d, !d.servers.isEmpty else { return }
        for (srv, tools) in d.servers {
            for t in tools {
                toolSwitch[Self.pairKey(server: srv, tool: t.name)] = false
            }
        }
        persistToolPairsOnly()
        objectWillChange.send()
    }

    /// Maps model output (e.g. `user-ddg-search`, `DDG-Search`) to configured names from last discovery.
    public func resolvedMcpToolPair(modelMcp: String, modelTool: String) -> (String, String) {
        let m = modelMcp.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = modelTool.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let disc = lastDiscovery else { return (m, t) }
        let merged = disc.mergingPythonInternalTools()
        let canonSrv = MCPIdentityResolution.canonicalServerName(
            modelOutput: m,
            knownServers: Array(merged.servers.keys)
        )
        let toolList = merged.servers[canonSrv]?.map(\.name) ?? []
        let canonTool = MCPIdentityResolution.canonicalToolName(modelOutput: t, knownTools: toolList)
        return (canonSrv, canonTool)
    }

    public func isToolOn(server: String, tool: String) -> Bool {
        let (s, t) = resolvedMcpToolPair(modelMcp: server, modelTool: tool)
        let k = Self.pairKey(server: s, tool: t)
        if let v = toolSwitch[k] { return v }
        guard let disc = lastDiscovery else {
            return isToolEnabledByStoredPairsOnly(modelServer: server, modelTool: tool)
        }
        let merged = disc.mergingPythonInternalTools()
        return MCPEnablementFromStoredPairs.isDiscoveredToolEnabled(
            storedPairs: preferences.mcpEnabledPairs,
            discoveredServer: s,
            discoveredTool: t,
            merged: merged
        )
    }

    /// When MCP discovery has not run yet, resolve enablement from `mcpEnabledPairs` on disk (same identity rules as discovery-backed path).
    private func isToolEnabledByStoredPairsOnly(modelServer: String, modelTool: String) -> Bool {
        guard let pairs = preferences.mcpEnabledPairs else { return true }
        if pairs.isEmpty { return false }
        let knownServers = Array(Set(pairs.compactMap { $0.first }))
        let canonS = MCPIdentityResolution.canonicalServerName(modelOutput: modelServer, knownServers: knownServers)
        let toolNames: [String] = pairs.compactMap { row in
            guard row.count >= 2,
                  MCPIdentityResolution.canonicalServerName(modelOutput: row[0], knownServers: knownServers) == canonS
            else { return nil }
            return row[1]
        }
        guard !toolNames.isEmpty else { return false }
        let canonT = MCPIdentityResolution.canonicalToolName(modelOutput: modelTool, knownTools: toolNames)
        return toolNames.contains(where: { $0.caseInsensitiveCompare(canonT) == .orderedSame })
    }

    public func applyDiscovery(_ result: MCPToolsDiscoveryResult) {
        lastDiscovery = result
        let merged = result.mergingPythonInternalTools()
        let previous = toolSwitch
        var next: [String: Bool] = [:]
        for (srv, tools) in merged.servers {
            for t in tools {
                let k = Self.pairKey(server: srv, tool: t.name)
                if let preserved = previous[k] {
                    next[k] = preserved
                } else {
                    next[k] = MCPEnablementFromStoredPairs.isDiscoveredToolEnabled(
                        storedPairs: preferences.mcpEnabledPairs,
                        discoveredServer: srv,
                        discoveredTool: t.name,
                        merged: merged
                    )
                }
            }
        }
        toolSwitch = next
        persistToolPairsOnly()
        objectWillChange.send()
    }

    /// Used for one-server probes so a successful test does not wipe tools from other servers.
    public func mergeDiscovery(_ result: MCPToolsDiscoveryResult) {
        guard let previous = lastDiscovery else {
            applyDiscovery(result)
            return
        }
        var combinedServers = previous.servers
        for (server, tools) in result.servers {
            combinedServers[server] = tools
        }
        let combined = MCPToolsDiscoveryResult(
            servers: combinedServers,
            errorMessage: result.errorMessage ?? previous.errorMessage
        )
        applyDiscovery(combined)
    }

    /// Full refreshes can fail transiently; keep the last good discovery instead of blanking the UI.
    public func applyDiscoveryPreservingPreviousOnFailure(_ result: MCPToolsDiscoveryResult) {
        if result.servers.isEmpty, result.errorMessage != nil, lastDiscovery != nil {
            objectWillChange.send()
            return
        }
        applyDiscovery(result)
    }

    public func cachedMcpToolCounts(jsonPath: String) -> [String: Int] {
        preferences.mcpToolCountsByJSONPath?[jsonPath] ?? [:]
    }

    public func setCachedMcpToolCounts(_ counts: [String: Int], jsonPath: String) {
        var snap = preferences
        var cache = snap.mcpToolCountsByJSONPath ?? [:]
        cache[jsonPath] = counts
        snap.mcpToolCountsByJSONPath = cache
        preferences = snap
        persist()
    }

    private func rebuildToolSwitchFromPreferences() {
        toolSwitch = [:]
        guard let pairs = preferences.mcpEnabledPairs else { return }
        for row in pairs where row.count >= 2 {
            toolSwitch[Self.pairKey(server: row[0], tool: row[1])] = true
        }
    }

    private func persist() {
        do {
            try preferences.save()
        } catch {
            GrizzyClawLog.error("gui_chat_prefs save failed: \(error.localizedDescription)")
        }
    }

    private func persistToolPairsOnly() {
        var enabled: [[String]] = []
        var allOn = true
        guard let raw = lastDiscovery else {
            // Avoid wiping saved allowlists when discovery has not run (e.g. toggles before refresh).
            return
        }
        let disc = raw.mergingPythonInternalTools()
        for (srv, tools) in disc.servers {
            for t in tools {
                let on = isToolOn(server: srv, tool: t.name)
                if on {
                    enabled.append([srv, t.name])
                } else {
                    allOn = false
                }
            }
        }
        var snap = preferences
        snap.mcpEnabledPairs = allOn ? nil : enabled
        preferences = snap
        persist()
    }
}
