import Foundation
import GrizzyClawCore
import Hub
import HuggingFace
import MLXLMCommon
import MLXLLM

/// Lists Hugging Face repo ids found under the MLX download root (delegates to ``CachedMLXHubRepoIds`` in GrizzyClawCore).
public enum MLXHubInstalledModels {
    /// Returns sorted unique repo ids for model folders under ``downloadRoot`` (Swift HubApi layout and/or Python `hub/` cache).
    public static func listRepoIds(downloadRoot: URL) -> [String] {
        CachedMLXHubRepoIds.listRepoIds(downloadRoot: downloadRoot)
    }
}

/// Prefetches MLX weights via the same path as chat (``loadModelContainer``); useful for explicit downloads from Preferences.
public enum MLXModelPrefetch {
    public static func prefetch(
        downloadBase: URL,
        modelId: String,
        revision: String,
        progressHandler: @Sendable @escaping (Progress) -> Void = { _ in }
    ) async throws {
        let hub = HubApi(downloadBase: downloadBase)
        _ = try await loadModelContainer(
            hub: hub,
            id: modelId,
            revision: revision,
            progressHandler: progressHandler
        )
    }
}
