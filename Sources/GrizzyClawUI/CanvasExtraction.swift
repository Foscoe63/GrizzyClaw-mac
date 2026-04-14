import Foundation

/// Mirrors `main_window.py` control-line parsing for chat display and Visual Canvas targets.
enum CanvasExtraction {
    private static let canvasImageControl = try! NSRegularExpression(
        pattern: #"\[GRIZZYCLAW_CANVAS_IMAGE:([^\]]+)\]"#,
        options: []
    )
    private static let canvasURLControl = try! NSRegularExpression(
        pattern: #"\[GRIZZYCLAW_CANVAS_URL:([^\]]+)\]"#,
        options: []
    )
    private static let screenshotPath = try! NSRegularExpression(
        pattern: #"Screenshot saved:\s*`([^`]+)`"#,
        options: []
    )
    private static let screenshotPathFallback = try! NSRegularExpression(
        pattern: #"Screenshot saved:\s*([^\s\n]+\.png)"#,
        options: []
    )
    private static let base64Image = try! NSRegularExpression(
        pattern: #"```image/(png|jpeg|gif|webp)\s*\n([A-Za-z0-9+/=\s]+)\s*```"#,
        options: [.caseInsensitive]
    )
    private static let a2uiBlock = try! NSRegularExpression(
        pattern: #"```a2ui\s*\n([\s\S]*?)```"#,
        options: [.caseInsensitive]
    )
    private static let swarmPartial = try! NSRegularExpression(
        pattern: #"\[GRIZZYCLAW_SWARM_PARTIAL\s+([^\]]+)\]"#,
        options: []
    )
    private static let debateMissing = try! NSRegularExpression(
        pattern: #"\[GRIZZYCLAW_DEBATE_MISSING\s+([^\]]+)\]"#,
        options: []
    )
    private static let swarmPositions = try! NSRegularExpression(
        pattern: #"\[GRIZZYCLAW_SWARM_POSITIONS\s+slugs=([^\]]+)\]"#,
        options: []
    )
    /// MLX / Qwen-style channel blocks: `<|channel|>analysis<|message|>…<|end|>` and `<|channel|>final<|message|>…`.
    private static let mlxChannelBlockEnded = try! NSRegularExpression(
        pattern: #"<\|channel\|>(?:analysis|reasoning|think|commentary)<\|message\|>[\s\S]*?<\|end\|>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let mlxLooseTokens = try! NSRegularExpression(
        pattern: #"<\|[^|]+\|>"#,
        options: []
    )

    /// Strips MLX-style `<|channel|>…<|message|>` scaffolding so only the user-facing reply remains.
    static func stripMLXChannelFormat(_ text: String) -> String {
        let finalMarker = "<|channel|>final<|message|>"
        if let range = text.range(of: finalMarker, options: .caseInsensitive) {
            var s = String(text[range.upperBound...])
            s = mlxLooseTokens.stringByReplacingMatches(
                in: s,
                range: NSRange(s.startIndex..., in: s),
                withTemplate: ""
            )
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var s = text
        let full = NSRange(location: 0, length: (s as NSString).length)
        s = mlxChannelBlockEnded.stringByReplacingMatches(in: s, range: full, withTemplate: "")
        s = s.replacingOccurrences(of: "<|start|>assistant", with: "", options: .caseInsensitive)

        if let r = s.range(of: "<|channel|>analysis<|message|>", options: .caseInsensitive) {
            s = String(s[..<r.lowerBound])
        } else if let r = s.range(of: "<|channel|>reasoning<|message|>", options: .caseInsensitive) {
            s = String(s[..<r.lowerBound])
        } else if let r = s.range(of: "<|channel|>think<|message|>", options: .caseInsensitive) {
            s = String(s[..<r.lowerBound])
        }

        s = mlxLooseTokens.stringByReplacingMatches(
            in: s,
            range: NSRange(s.startIndex..., in: s),
            withTemplate: ""
        )
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Text safe to show in bubbles (strips agent control lines).
    static func stripDisplayControls(_ text: String) -> String {
        var s = stripMLXChannelFormat(text)
        for re in [
            canvasImageControl, canvasURLControl,
            swarmPartial, debateMissing, swarmPositions,
        ] {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        while s.contains("\n\n\n") {
            s = s.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Local file path from `[GRIZZYCLAW_CANVAS_IMAGE:…]` if present.
    static func extractCanvasImageControlPath(_ text: String) -> String? {
        let ns = text as NSString
        guard let m = canvasImageControl.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2
        else { return nil }
        let raw = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.hasPrefix("http://") == false, raw.hasPrefix("https://") == false else {
            return nil
        }
        return URL(fileURLWithPath: raw).resolvingSymlinksInPath().path
    }

    /// HTTP(S) URL from `[GRIZZYCLAW_CANVAS_URL:…]` (display policy matches Python: often skipped for loading).
    static func extractCanvasURLControl(_ text: String) -> String? {
        let ns = text as NSString
        guard let m = canvasURLControl.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2
        else { return nil }
        let u = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return u.isEmpty ? nil : u
    }

    /// First screenshot path from control line or “Screenshot saved:” lines.
    static func extractScreenshotPath(_ text: String) -> String? {
        if let p = extractCanvasImageControlPath(text) { return p }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let m = screenshotPath.firstMatch(in: text, range: full), m.numberOfRanges >= 2 {
            let raw = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            return resolveLocalPath(raw)
        }
        if let m = screenshotPathFallback.firstMatch(in: text, range: full), m.numberOfRanges >= 2 {
            let raw = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            return resolveLocalPath(raw)
        }
        return nil
    }

    private static func resolveLocalPath(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return nil }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath).resolvingSymlinksInPath().path
    }

    /// First ```a2ui``` JSON body, if any.
    static func extractA2UIPayloadString(_ text: String) -> String? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = a2uiBlock.firstMatch(in: text, range: full), m.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// First inline base64 image block → (format, data).
    static func extractBase64Image(_ text: String) -> (format: String, data: Data)? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = base64Image.firstMatch(in: text, range: full), m.numberOfRanges >= 3 else { return nil }
        let fmt = ns.substring(with: m.range(at: 1)).lowercased()
        let b64 = ns.substring(with: m.range(at: 2))
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard let data = Data(base64Encoded: b64, options: [.ignoreUnknownCharacters]) else { return nil }
        return (fmt, data)
    }
}
