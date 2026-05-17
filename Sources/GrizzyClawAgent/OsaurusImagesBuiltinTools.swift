import CoreGraphics
import Foundation
import GrizzyClawCore
import ImageIO

enum OsaurusImagesBuiltinTools {
    static func result(tool: String, arguments: [String: Any]) -> String {
        let composite = "osaurus.images.\(tool)"
        switch tool {
        case "get_image_info":
            return imageInfo(composite: composite, arguments: arguments)
        default:
            return ToolEnvelope.failure(
                tool: composite,
                kind: "not_available_builtin",
                message:
                    "Image transforms are not implemented in Grizzy's built-in driver yet. Use `get_image_info` with a local `path`.",
                retryable: false
            )
        }
    }

    private static func imageInfo(composite: String, arguments: [String: Any]) -> String {
        let raw =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["path", "file", "input"])
            ?? ""
        let path = (raw as NSString).expandingTildeInPath
        guard !path.isEmpty, !path.contains("..") else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Provide a safe local `path` (no `..`).",
                field: "path"
            )
        }
        let url = URL(fileURLWithPath: path)
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let allowed =
            path.hasPrefix(home) || path.hasPrefix("/tmp/") || path.hasPrefix("/private/tmp/")
        #else
        let home = NSHomeDirectory()
        let tmp = NSTemporaryDirectory()
        let allowed = path.hasPrefix(home) || path.hasPrefix(tmp)
        #endif
        guard allowed else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message:
                    "Path must be readable by the app (iOS: under the app sandbox, e.g. Documents or tmp; macOS: your user home or `/tmp`).",
                field: "path"
            )
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
            let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "read_error",
                message: "Could not read image metadata.",
                retryable: false
            )
        }
        let w = cg.width
        let h = cg.height
        return ToolEnvelope.success(
            tool: composite,
            result: [
                "path": path,
                "width": w,
                "height": h,
                "properties": props,
            ])
    }
}
