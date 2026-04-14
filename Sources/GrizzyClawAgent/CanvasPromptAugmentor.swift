import Foundation

/// Appends Visual Canvas guidance so normal chats can intentionally emit canvas-friendly payloads.
public enum CanvasPromptAugmentor {
    public static func suffix() -> String {
        [
            "## Visual Canvas",
            "This chat can open a Visual Canvas from assistant replies.",
            "When the user asks for a mockup, wireframe, UI sketch, flowchart, diagram, card layout, or explicitly mentions the visual canvas, prefer replying with exactly one fenced ```a2ui code block containing compact valid JSON and no prose before or after the block.",
            "For ordinary text answers, do not emit a2ui blocks unless the user asked for a visual representation.",
            "Do not invent screenshot file paths or `[GRIZZYCLAW_CANVAS_IMAGE:...]` markers. Use them only when a tool result gave you a real local image path.",
            "Do not emit ```image/png (or other image/*) blocks unless you have valid base64 image data. When in doubt, prefer a single ```a2ui block.",
        ].joined(separator: "\n")
    }
}
