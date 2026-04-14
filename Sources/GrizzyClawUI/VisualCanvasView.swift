import AppKit
import SwiftUI

/// Visual Canvas panel matching Python `CanvasWidget` (header, Load/Save/Clear, scroll stack).
struct VisualCanvasView: View {
    @ObservedObject var model: VisualCanvasModel
    @Environment(\.colorScheme) private var colorScheme

    private var canvasBackground: Color {
        colorScheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color(red: 0.98, green: 0.98, blue: 0.98)
    }

    private var canvasBorder: Color {
        colorScheme == .dark ? Color(red: 0.22, green: 0.22, blue: 0.24) : Color(red: 0.90, green: 0.90, blue: 0.92)
    }

    private var headerColor: Color {
        colorScheme == .dark ? Color(red: 0.95, green: 0.95, blue: 0.97) : Color(red: 0.11, green: 0.11, blue: 0.12)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text("Visual Canvas")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(headerColor)
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    pillButton(title: "Load") { model.presentLoadPanel() }
                    pillButton(title: "Save") { model.presentSavePanel() }
                    pillButton(title: "Clear") { model.clear() }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minWidth: 380)

            ScrollView {
                VStack(spacing: 12) {
                    if model.isEmpty {
                        Text(
                            "Images (screenshots, attachments),\n"
                                + "A2UI cards/diagrams, and inline images\n"
                                + "will appear here."
                        )
                        .multilineTextAlignment(.center)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 0.56, green: 0.56, blue: 0.58))
                        .frame(maxWidth: .infinity)
                        .padding(48)
                        .frame(minHeight: 260)
                    }
                    ForEach(model.rows) { row in
                        switch row.kind {
                        case .image(let img):
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 600, maxHeight: 400)
                                .frame(maxWidth: .infinity)
                        case .a2uiJSON(let json):
                            VStack(alignment: .leading, spacing: 8) {
                                Text("A2UI")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ScrollView {
                                    Text(json)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(minHeight: 120, maxHeight: 280)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(minWidth: 200)
                .padding(24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 320)
            }
            .background(canvasBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(canvasBorder, lineWidth: 1)
            )
            .frame(minHeight: 360)
        }
        .padding(16)
        .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func pillButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.90, green: 0.90, blue: 0.92).opacity(colorScheme == .dark ? 0.35 : 1))
            )
            .foregroundStyle(headerColor)
    }
}

// MARK: - Dedicated window host (see `GrizzyClawRootScene` Window id `visualCanvas`)

/// Root for the Visual Canvas `Window` scene: canvas UI + sync when the user closes the window with the red close button.
struct VisualCanvasWindowContent: View {
    @ObservedObject var model: VisualCanvasModel
    var onWindowWillClose: () -> Void

    var body: some View {
        VisualCanvasView(model: model)
            .background(VisualCanvasWindowCloseSync(onClosed: onWindowWillClose))
    }
}

/// Observes `NSWindow.willClose` so toolbar toggle state stays in sync when the window is dismissed from window chrome.
private struct VisualCanvasWindowCloseSync: NSViewRepresentable {
    var onClosed: () -> Void

    func makeNSView(context: Context) -> CanvasWindowCloseHookView {
        let v = CanvasWindowCloseHookView()
        v.onClosed = onClosed
        return v
    }

    func updateNSView(_ nsView: CanvasWindowCloseHookView, context: Context) {
        nsView.onClosed = onClosed
    }
}

private final class CanvasWindowCloseHookView: NSView {
    /// Updated from `NSViewRepresentable`; avoids Swift 6 isolation issues on AppKit views.
    nonisolated(unsafe) var onClosed: (() -> Void)?
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        guard let window else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.onClosed?()
        }
    }
}
