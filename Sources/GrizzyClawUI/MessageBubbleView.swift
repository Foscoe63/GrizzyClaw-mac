import AppKit
import Foundation
import GrizzyClawAgent
import GrizzyClawCore
import SwiftUI

// MARK: - Python `MessageBubble` parity (main_window.py)

/// Plain 28×28 icon row control: transparent, hover wash (matches Qt stylesheet).
private struct BubbleIconButton: View {
    let help: String
    let emoji: String
    var fontSnapshot: UserConfigSnapshot
    var isDark: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(AppearanceTheme.swiftUIFont(fontSnapshot, delta: 0))
        }
        .buttonStyle(.plain)
        .help(help)
        .frame(width: 28, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(hover ? (isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.1)) : Color.clear)
        )
        .onHover { hover = $0 }
        .accessibilityLabel(Text(help))
    }
}

/// Copy with ✓ flash and green tint (Python `_flash_copy_feedback`).
private struct MessageBubbleCopyButton: View {
    let text: String
    var fontSnapshot: UserConfigSnapshot
    var isDark: Bool

    @State private var copied = false
    @State private var hoverBg = false

    private var copyFill: Color {
        if copied {
            return Color(red: 0.2, green: 0.78, blue: 0.35).opacity(0.28)
        }
        if hoverBg {
            return isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.1)
        }
        return Color.clear
    }

    var body: some View {
        Button {
            let p = NSPasteboard.general
            p.clearContents()
            p.setString(text, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                copied = false
            }
        } label: {
            Text(copied ? "✓" : "📋")
                .font(AppearanceTheme.swiftUIFont(fontSnapshot, delta: 0))
                .fontWeight(copied ? .semibold : .regular)
                .foregroundStyle(copied ? Color(red: 0.14, green: 0.54, blue: 0.24) : .primary)
        }
        .buttonStyle(.plain)
        .help("Copy message")
        .frame(width: 28, height: 28)
        .background(RoundedRectangle(cornerRadius: 14).fill(copyFill))
        .onHover { h in
            if !copied { hoverBg = h }
        }
    }
}

/// Parity with Python `MessageBubble`: sender label, rounded bubble, copy; user: stretch → copy → label (bottom aligned).
/// Assistant: optional avatar → label → copy → speak → 👍 → 👎 → stretch.
struct MessageBubbleView: View {
    let message: ChatMessage
    let workspaceTitle: String
    let displayText: String
    let isStreamingPlaceholder: Bool
    let colorScheme: ColorScheme
    var fontSnapshot: UserConfigSnapshot
    /// Resolved filesystem path when `~` expanded; file must exist (Python `Path(avatar_path).exists()`).
    var assistantAvatarPath: String? = nil
    var onSpeak: ((String) -> Void)? = nil
    var onFeedbackUp: (() -> Void)? = nil
    var onFeedbackDown: (() -> Void)? = nil

    private var isUser: Bool { message.role == .user }
    private var isTool: Bool { message.role == .tool }

    /// Same monospace + soft-green panel as tool output — applies to assistant replies too.
    private var useTranscriptPanelStyle: Bool {
        !isUser && (message.role == .assistant || message.role == .tool)
    }

    private var sender: String {
        switch message.role {
        case .user: return "You"
        case .assistant: return workspaceTitle
        case .system: return "System"
        case .tool: return "Tool"
        }
    }

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 0) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                Text(sender)
                    .font(AppearanceTheme.swiftUIFont(fontSnapshot, delta: -2, weight: .medium))
                    .foregroundColor(
                        useTranscriptPanelStyle
                            ? (isDark ? Color(red: 0.55, green: 0.78, blue: 0.62) : Color(red: 0.12, green: 0.42, blue: 0.28))
                            : (isDark ? Color(red: 0.6, green: 0.6, blue: 0.62) : Color(red: 0.56, green: 0.56, blue: 0.58))
                    )
                    .multilineTextAlignment(isUser ? .trailing : .leading)

                messageToolbarRow
            }
            .frame(maxWidth: 750, alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: 0) }
        }
        .padding(.vertical, 4)
    }

    /// Python `row.setSpacing(8)`, copy/controls `AlignBottom` with the label.
    private var messageToolbarRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 0)
                MessageBubbleCopyButton(text: displayText, fontSnapshot: fontSnapshot, isDark: isDark)
                bubbleChrome
            } else {
                if let path = assistantAvatarPath,
                   FileManager.default.fileExists(atPath: path),
                   let img = NSImage(contentsOfFile: path)
                {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                }
                bubbleChrome
                MessageBubbleCopyButton(text: displayText, fontSnapshot: fontSnapshot, isDark: isDark)
                if let speak = onSpeak {
                    BubbleIconButton(help: "Speak response", emoji: "🔊", fontSnapshot: fontSnapshot, isDark: isDark) {
                        speak(displayText)
                    }
                }
                if let up = onFeedbackUp {
                    BubbleIconButton(help: "Good response", emoji: "👍", fontSnapshot: fontSnapshot, isDark: isDark, action: up)
                }
                if let down = onFeedbackDown {
                    BubbleIconButton(help: "Poor response", emoji: "👎", fontSnapshot: fontSnapshot, isDark: isDark, action: down)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// QLabel: `setMaximumWidth(600)` — bubble hugs content width, never wider than 600 for text area.
    private var bubbleChrome: some View {
        bubbleTextCore
            .font(AppearanceTheme.swiftUIFont(fontSnapshot, delta: bubbleFontSizeDelta))
            .fontDesign(bubbleFontDesign)
            .foregroundColor(bubbleForeground)
            .multilineTextAlignment(isUser ? .trailing : .leading)
            .textSelection(.enabled)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                bubbleBackground,
                in: UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: isUser ? 18 : 4,
                    bottomTrailingRadius: isUser ? 4 : 18,
                    topTrailingRadius: 18
                )
            )
            .frame(maxWidth: 600, alignment: isUser ? .trailing : .leading)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var bubbleFontSizeDelta: CGFloat {
        if isUser { return 1 }
        if isTool { return 0 }
        return useTranscriptPanelStyle ? 0 : 1
    }

    private var bubbleFontDesign: Font.Design {
        if isUser { return .default }
        if isTool { return .default }
        return useTranscriptPanelStyle ? .monospaced : .default
    }

    @ViewBuilder
    private var bubbleTextCore: some View {
        if isTool {
            Text(Self.toolMarkdownAttributed(displayText))
        } else {
            Text(isStreamingPlaceholder && displayText == "…" ? "…" : displayText)
        }
    }

    /// Renders common MCP tool output (Markdown lists, **bold**, links) with plain-text fallback.
    private static func toolMarkdownAttributed(_ s: String) -> AttributedString {
        if let a = try? AttributedString(markdown: s) {
            return a
        }
        if let a = try? AttributedString(
            markdown: s,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return a
        }
        return AttributedString(s)
    }

    private var bubbleBackground: Color {
        if isUser {
            return Color(red: 0, green: 0.48, blue: 1)
        }
        if useTranscriptPanelStyle {
            return isDark
                ? Color(red: 0.14, green: 0.20, blue: 0.17)
                : Color(red: 0.88, green: 0.96, blue: 0.91)
        }
        if isDark {
            return Color(red: 0.23, green: 0.23, blue: 0.24)
        }
        return Color(red: 0.91, green: 0.91, blue: 0.92)
    }

    private var bubbleForeground: Color {
        if isUser { return .white }
        if useTranscriptPanelStyle {
            return isDark
                ? Color(red: 0.88, green: 0.94, blue: 0.90)
                : Color(red: 0.10, green: 0.16, blue: 0.13)
        }
        return isDark ? .white : .black
    }
}

