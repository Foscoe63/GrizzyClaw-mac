import Foundation
import Hub
import MLXLMCommon
import MLXLLM

/// Caches loaded ``ModelContainer`` instances by Hugging Face id + revision (weights are large; reload is expensive).
actor MLXModelCache {
    static let shared = MLXModelCache()

    private var containers: [String: ModelContainer] = [:]

    private func cacheKey(modelId: String, revision: String) -> String {
        "\(modelId)@\(revision)"
    }

    func container(
        hub: HubApi,
        modelId: String,
        revision: String,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> ModelContainer {
        let key = cacheKey(modelId: modelId, revision: revision)
        if let existing = containers[key] {
            return existing
        }
        let loaded = try await loadModelContainer(
            hub: hub,
            id: modelId,
            revision: revision,
            progressHandler: progressHandler
        )
        containers[key] = loaded
        return loaded
    }

    /// Drops cached containers (e.g. after a failed generation). Next request reloads from disk / hub.
    func clear() {
        containers.removeAll()
    }
}
