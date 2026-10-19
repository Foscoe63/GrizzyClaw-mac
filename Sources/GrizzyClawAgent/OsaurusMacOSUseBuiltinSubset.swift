import Foundation
import GrizzyClawCore

#if os(macOS)
import AppKit
import CoreGraphics
#endif

enum OsaurusMacOSUseBuiltinSubset {
    static func result(tool: String, arguments: [String: Any]) -> String {
        let composite = "osaurus.macos-use.\(tool)"
#if os(macOS)
        switch tool {
        case "list_apps":
            return listApps(composite: composite)
        case "list_displays":
            return listDisplays(composite: composite)
        case "list_windows":
            return listWindows(composite: composite, arguments: arguments)
        case "get_active_window":
            return activeWindow(composite: composite)
        default:
            return ToolEnvelope.failure(
                tool: composite,
                kind: "not_available_builtin",
                message:
                    "Full macOS UI automation (accessibility driving) is not part of Grizzy's built-in tools. Built-in subset: `list_apps`, `list_displays`, `list_windows`, `get_active_window`.",
                retryable: false
            )
        }
#else
        return ToolEnvelope.failure(
            tool: composite,
            kind: "unsupported_platform",
            message: "macOS Use tools are only available on macOS.",
            retryable: false
        )
#endif
    }

#if os(macOS)
    private static func listApps(composite: String) -> String {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let rows: [[String: Any]] = apps.compactMap { a in
            guard let name = a.localizedName else { return nil }
            return [
                "pid": a.processIdentifier,
                "name": name,
                "bundle_id": a.bundleIdentifier ?? "",
                "active": a.isActive,
                "hidden": a.isHidden,
            ]
        }
        return ToolEnvelope.success(tool: composite, result: ["apps": rows, "count": rows.count])
    }

    private static func listDisplays(composite: String) -> String {
        let maxDisplays = 32
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: maxDisplays)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(maxDisplays), &displayIDs, &count) == .success else {
            return ToolEnvelope.success(tool: composite, result: ["displays": []])
        }
        let rows: [[String: Any]] = displayIDs.prefix(Int(count)).map { id in
            let bounds = CGDisplayBounds(id)
            return [
                "id": UInt32(id),
                "x": bounds.origin.x,
                "y": bounds.origin.y,
                "width": bounds.size.width,
                "height": bounds.size.height,
                "main": CGDisplayIsMain(id) != 0,
            ]
        }
        return ToolEnvelope.success(tool: composite, result: ["displays": rows])
    }

    private static func listWindows(composite: String, arguments: [String: Any]) -> String {
        let pid = OsaurusBuiltinToolArguments.int(from: arguments, keys: ["pid", "process_id"], default: -1)
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let filtered: [[String: Any]] =
            pid > 0
            ? info.filter { w in
                let v = w["kCGWindowOwnerPID"] as? Int32 ?? Int32(truncatingIfNeeded: (w["kCGWindowOwnerPID"] as? NSNumber)?.intValue ?? 0)
                return Int(v) == pid
            }
            : info
        let rows = filtered.prefix(80).map { w -> [String: Any] in
            [
                "window_id": w["kCGWindowNumber"] ?? 0,
                "owner": w["kCGWindowOwnerName"] ?? "",
                "name": w["kCGWindowName"] ?? "",
                "bounds": w["kCGWindowBounds"] ?? [:],
            ]
        }
        return ToolEnvelope.success(tool: composite, result: ["windows": rows, "count": rows.count])
    }

    private static func activeWindow(composite: String) -> String {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return ToolEnvelope.success(tool: composite, result: [:])
        }
        let row: [String: Any] = [
            "pid": app.processIdentifier,
            "name": app.localizedName ?? "",
            "bundle_id": app.bundleIdentifier ?? "",
        ]
        return ToolEnvelope.success(tool: composite, result: row)
    }
#endif
}
