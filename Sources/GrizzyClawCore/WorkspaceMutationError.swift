import Foundation

public enum WorkspaceMutationError: LocalizedError, Sendable {
    case workspaceNotFound(String)
    case cannotDeleteLastWorkspace
    case emptyName
    case saveFailed(String)
    case invalidShareLink
    case invalidTemplateKey(String)

    public var errorDescription: String? {
        switch self {
        case .workspaceNotFound(let id):
            return "No workspace with id \"\(id)\"."
        case .cannotDeleteLastWorkspace:
            return "Cannot delete the last workspace."
        case .emptyName:
            return "Workspace name cannot be empty."
        case .saveFailed(let reason):
            return reason
        case .invalidShareLink:
            return "Invalid or unsupported share link."
        case .invalidTemplateKey(let reason):
            return reason
        }
    }
}
