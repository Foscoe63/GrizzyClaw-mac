import CoreGraphics
import Foundation
import GrizzyClawCore
import ImageIO
import Vision

enum OsaurusVisionBuiltinTools {
    static func result(tool: String, arguments: [String: Any]) async -> String {
        let composite = "osaurus.vision.\(tool)"
        switch tool {
        case "detect_text":
            return runTextRecognition(composite: composite, arguments: arguments)
        case "classify_image":
            return runClassify(composite: composite, arguments: arguments)
        default:
            return ToolEnvelope.failure(
                tool: composite,
                kind: "not_available_builtin",
                message:
                    "This Vision tool is not implemented in Grizzy's built-in driver yet. Use `detect_text` or `classify_image` with a local `path` to an image file.",
                retryable: false
            )
        }
    }

    private static func loadCGImage(arguments: [String: Any], composite: String) -> CGImage? {
        guard let url = resolveLocalImageURL(arguments: arguments) else {
            return nil
        }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else {
            return nil
        }
        return cg
    }

    private static func resolveLocalImageURL(arguments: [String: Any]) -> URL? {
        let raw =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["path", "file", "image"])
            ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url: URL =
            trimmed.lowercased().hasPrefix("file://")
            ? URL(string: trimmed) ?? URL(fileURLWithPath: "")
            : URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        guard url.isFileURL else { return nil }
        let path = url.path
        if path.contains("..") { return nil }
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) || path.hasPrefix("/tmp/") || path.hasPrefix("/private/tmp/") {
            return url
        }
        #else
        // `homeDirectoryForCurrentUser` is unavailable on iOS; sandbox paths live under `NSHomeDirectory()`.
        let home = NSHomeDirectory()
        let tmp = NSTemporaryDirectory()
        if path.hasPrefix(home) || path.hasPrefix(tmp) {
            return url
        }
        #endif
        return nil
    }

    private static func runTextRecognition(composite: String, arguments: [String: Any]) -> String {
        guard let cg = loadCGImage(arguments: arguments, composite: composite) else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message:
                    "Provide a readable local `path` to an image the app can read (iOS: sandbox paths such as Documents or tmp; macOS: your user home or `/tmp`).",
                field: "path"
            )
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            let observations = request.results ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            return ToolEnvelope.success(
                tool: composite,
                result: ["lines": lines, "text": lines.joined(separator: "\n")]
            )
        } catch {
            return ToolEnvelope.fromError(error, tool: composite)
        }
    }

    private static func runClassify(composite: String, arguments: [String: Any]) -> String {
        guard let cg = loadCGImage(arguments: arguments, composite: composite) else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message:
                    "Provide a local `path` to an image the app can read (iOS: sandbox paths such as Documents or tmp; macOS: your user home or `/tmp`).",
                field: "path"
            )
        }
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do {
            try handler.perform([request])
            let classifications = request.results ?? []
            let items = classifications.prefix(12).map { o in
                ["identifier": o.identifier, "confidence": o.confidence] as [String: Any]
            }
            return ToolEnvelope.success(tool: composite, result: ["labels": items])
        } catch {
            return ToolEnvelope.fromError(error, tool: composite)
        }
    }
}
