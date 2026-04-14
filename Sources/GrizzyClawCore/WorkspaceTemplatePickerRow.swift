import Foundation

/// One row in the “Create workspace” template list (built-in and/or user templates merged like Python `get_all_templates`).
public struct WorkspaceTemplatePickerRow: Identifiable, Hashable, Sendable {
    public var id: String { templateKey }

    public let templateKey: String
    public let title: String
    public let subtitle: String
    public let icon: String
    public let color: String

    public init(templateKey: String, title: String, subtitle: String, icon: String, color: String) {
        self.templateKey = templateKey
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.color = color
    }
}
