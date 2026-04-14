import AppKit
import SwiftUI

/// Multiline composer matching Python `ChatInput`: **Return** sends, **Shift+Return** inserts newline; **Esc** forwarded to host.
struct ChatComposerNSTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 14
    /// From `config.yaml` `font_family` (e.g. System Default, Helvetica).
    var fontFamily: String = "System Default"
    var onSend: () -> Void
    var onEscape: () -> Void
    var onTextOrSelectionChange: (String, NSRange) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onSend: onSend,
            onEscape: onEscape,
            onTextOrSelectionChange: onTextOrSelectionChange
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.automaticallyAdjustsContentInsets = false

        let tv = EscapingNSTextView()
        let coord = context.coordinator
        tv.onEscape = { [weak coord] in coord?.handleEscape() }
        tv.delegate = coord
        tv.isRichText = false
        tv.importsGraphics = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.font = AppearanceTheme.nsFont(family: fontFamily, size: fontSize)
        tv.textColor = NSColor.labelColor
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.textContainerInset = NSSize(width: 16, height: 10)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.minSize = NSSize(width: 0, height: 44)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.string = text

        scroll.documentView = tv
        scroll.contentView.postsBoundsChangedNotifications = true

        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let c = context.coordinator
        c.onSend = onSend
        c.onEscape = onEscape
        c.onTextOrSelectionChange = onTextOrSelectionChange
        guard let tv = context.coordinator.textView else { return }
        tv.font = AppearanceTheme.nsFont(family: fontFamily, size: fontSize)
        tv.textColor = NSColor.labelColor
        if tv.string != text {
            c.isUpdatingFromSwiftUI = true
            tv.string = text
            c.isUpdatingFromSwiftUI = false
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSend: () -> Void
        var onEscape: () -> Void
        var onTextOrSelectionChange: (String, NSRange) -> Void
        weak var textView: NSTextView?
        var isUpdatingFromSwiftUI = false

        init(
            text: Binding<String>,
            onSend: @escaping () -> Void,
            onEscape: @escaping () -> Void,
            onTextOrSelectionChange: @escaping (String, NSRange) -> Void
        ) {
            self.text = text
            self.onSend = onSend
            self.onEscape = onEscape
            self.onTextOrSelectionChange = onTextOrSelectionChange
        }

        func handleEscape() {
            onEscape()
        }

        func textDidChange(_ notification: Notification) {
            propagate()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            propagate()
        }

        private func propagate() {
            guard let tv = textView, !isUpdatingFromSwiftUI else { return }
            text.wrappedValue = tv.string
            onTextOrSelectionChange(tv.string, tv.selectedRange())
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == NSSelectorFromString("insertNewline:") {
                let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
                if shift {
                    return false
                }
                onSend()
                return true
            }
            return false
        }
    }

    private final class EscapingNSTextView: NSTextView {
        var onEscape: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 {
                onEscape?()
                return
            }
            super.keyDown(with: event)
        }
    }
}
