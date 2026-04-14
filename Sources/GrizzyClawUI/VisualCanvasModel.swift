import AppKit
import Foundation
import GrizzyClawCore
import UniformTypeIdentifiers

public struct CanvasRow: Identifiable {
    public let id: UUID
    public enum Kind {
        case image(NSImage)
        case a2uiJSON(String)
    }

    public let kind: Kind

    public init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

/// Backing state for the Visual Canvas (parity with Python `CanvasWidget`).
@MainActor
public final class VisualCanvasModel: ObservableObject {
    @Published public private(set) var rows: [CanvasRow] = []

    public init() {}

    public var isEmpty: Bool { rows.isEmpty }

    public func clear() {
        rows = []
    }

    /// Append image from file (user load / attachment). Does not clear existing rows.
    public func appendImageFile(at path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return false }
        guard let img = NSImage(contentsOfFile: expanded) else { return false }
        rows.insert(CanvasRow(kind: .image(img)), at: 0)
        return true
    }

    /// Agent screenshot / control path: clear then show first successful path (Python `agent_screenshot_for_canvas`).
    public func setAgentScreenshot(path: String) {
        guard path.hasPrefix("http://") == false, path.hasPrefix("https://") == false else { return }
        let expanded = (path as NSString).expandingTildeInPath
        var candidates: [String] = [expanded]
        let base = (expanded as NSString).lastPathComponent
        let fallback = GrizzyClawPaths.userDataDirectory
            .appendingPathComponent("screenshots", isDirectory: true)
            .appendingPathComponent(base, isDirectory: false)
            .path
        if fallback != expanded {
            candidates.insert(fallback, at: 0)
        }
        for p in candidates where FileManager.default.fileExists(atPath: p) {
            clear()
            if appendImageFile(at: p) { return }
        }
        clear()
    }

    public func appendPixmap(_ image: NSImage) {
        rows.insert(CanvasRow(kind: .image(image)), at: 0)
    }

    public func appendA2UIPreview(_ json: String) {
        guard !json.isEmpty else { return }
        rows.insert(CanvasRow(kind: .a2uiJSON(json)), at: 0)
    }

    public func presentLoadPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            _ = self?.appendImageFile(at: url.path)
        }
    }

    /// Saves a composite of stacked images (A2UI rows skipped) as PNG.
    public func presentSavePanel() {
        let images: [NSImage] = rows.compactMap {
            if case .image(let i) = $0.kind { return i }
            return nil
        }
        guard let composite = Self.stackImages(images) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "canvas.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let tiff = composite.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else { return }
            try? png.write(to: url)
        }
    }

    private static func stackImages(_ images: [NSImage]) -> NSImage? {
        guard !images.isEmpty else { return nil }
        if images.count == 1 { return images[0] }
        var totalH: CGFloat = 0
        var maxW: CGFloat = 0
        for im in images {
            let s = im.size
            totalH += s.height
            maxW = max(maxW, s.width)
        }
        let out = NSImage(size: NSSize(width: maxW, height: totalH))
        out.lockFocus()
        defer { out.unlockFocus() }
        var y: CGFloat = 0
        for im in images {
            let s = im.size
            im.draw(
                at: NSPoint(x: (maxW - s.width) / 2, y: y),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            y += s.height
        }
        return out
    }
}
