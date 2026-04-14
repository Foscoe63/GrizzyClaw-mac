import Foundation

/// One folder watcher; mirrors `grizzyclaw.automation.watcher_model.FolderWatcher` JSON (`~/.grizzyclaw/watchers/{id}.json`).
public struct FolderWatcherRecord: Codable, Equatable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var instructions: String
    public var watchPath: String
    public var recursive: Bool
    /// `fast`, `balanced`, or `patient` (debounce hint for the Python runtime).
    public var responsiveness: String
    public var enabled: Bool
    public var includeGlobs: [String]
    public var excludeGlobs: [String]
    public var maxConvergence: Int
    public var optionalLlmModel: String?
    /// Workspace (agent) that runs this watcher; `nil` uses the active workspace at runtime (Python parity field `workspace_id`).
    public var workspaceId: String?
    public var createdAt: String
    public var lastTriggeredAt: String?
    public var lastError: String?

    enum CodingKeys: String, CodingKey {
        case id, name, instructions
        case watchPath = "watch_path"
        case recursive, responsiveness, enabled
        case includeGlobs = "include_globs"
        case excludeGlobs = "exclude_globs"
        case maxConvergence = "max_convergence"
        case optionalLlmModel = "optional_llm_model"
        case workspaceId = "workspace_id"
        case createdAt = "created_at"
        case lastTriggeredAt = "last_triggered_at"
        case lastError = "last_error"
    }

    public static let defaultExcludeGlobs: [String] = [
        ".git/**",
        "**/node_modules/**",
        "**/.venv/**",
        "**/__pycache__/**",
    ]

    public init(
        id: String,
        name: String,
        instructions: String,
        watchPath: String,
        recursive: Bool,
        responsiveness: String,
        enabled: Bool,
        includeGlobs: [String],
        excludeGlobs: [String],
        maxConvergence: Int,
        optionalLlmModel: String?,
        workspaceId: String?,
        createdAt: String,
        lastTriggeredAt: String?,
        lastError: String?
    ) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.watchPath = watchPath
        self.recursive = recursive
        self.responsiveness = responsiveness
        self.enabled = enabled
        self.includeGlobs = includeGlobs
        self.excludeGlobs = excludeGlobs
        self.maxConvergence = maxConvergence
        self.optionalLlmModel = optionalLlmModel
        self.workspaceId = workspaceId
        self.createdAt = createdAt
        self.lastTriggeredAt = lastTriggeredAt
        self.lastError = lastError
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled watcher"
        instructions = try c.decodeIfPresent(String.self, forKey: .instructions) ?? ""
        watchPath = try c.decodeIfPresent(String.self, forKey: .watchPath) ?? ""
        recursive = try c.decodeIfPresent(Bool.self, forKey: .recursive) ?? true
        responsiveness = try c.decodeIfPresent(String.self, forKey: .responsiveness) ?? "balanced"
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        includeGlobs = try c.decodeIfPresent([String].self, forKey: .includeGlobs) ?? []
        excludeGlobs = try c.decodeIfPresent([String].self, forKey: .excludeGlobs) ?? Self.defaultExcludeGlobs
        maxConvergence = try c.decodeIfPresent(Int.self, forKey: .maxConvergence) ?? 5
        optionalLlmModel = try c.decodeIfPresent(String.self, forKey: .optionalLlmModel)
        workspaceId = try c.decodeIfPresent(String.self, forKey: .workspaceId)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? Self.isoNow()
        lastTriggeredAt = try c.decodeIfPresent(String.self, forKey: .lastTriggeredAt)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
    }

    public static func makeNew() -> FolderWatcherRecord {
        FolderWatcherRecord(
            id: UUID().uuidString,
            name: "Untitled watcher",
            instructions: "",
            watchPath: "",
            recursive: true,
            responsiveness: "balanced",
            enabled: true,
            includeGlobs: [],
            excludeGlobs: defaultExcludeGlobs,
            maxConvergence: 5,
            optionalLlmModel: nil,
            workspaceId: nil,
            createdAt: isoNow(),
            lastTriggeredAt: nil,
            lastError: nil
        )
    }

    private static func isoNow() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }
}
