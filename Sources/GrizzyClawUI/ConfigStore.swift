import Combine
import GrizzyClawCore
import SwiftUI

/// Loads read-only `~/.grizzyclaw/config.yaml` (Python `load_settings_for_app` / `Settings.from_file` subset).
@MainActor
public final class ConfigStore: ObservableObject {
    @Published public private(set) var snapshot: UserConfigSnapshot
    @Published public private(set) var routingExtras: RoutingExtras
    @Published public private(set) var loadError: String?

    public init() {
        snapshot = UserConfigSnapshot.empty
        routingExtras = .default
    }

    public func reload() {
        loadError = nil
        do {
            snapshot = try UserConfigLoader.loadUserConfigIfPresent()
        } catch {
            loadError = error.localizedDescription
            GrizzyClawLog.error("config load failed: \(error.localizedDescription)")
            snapshot = UserConfigSnapshot.missingFile(at: GrizzyClawPaths.configYAML)
        }
        GrizzyClawLog.setDebugEnabled(snapshot.debug)
        do {
            routingExtras = try UserConfigLoader.loadRoutingExtras()
        } catch {
            routingExtras = .default
        }
    }

    /// Persists `scheduled_task_run_timeout_seconds` to `config.yaml` (Python `SchedulerDialog.save_scheduler_settings`).
    public func saveScheduledTaskRunTimeout(seconds: Int) -> String? {
        do {
            try UserConfigYAMLPatch.setScheduledTaskRunTimeout(seconds: seconds, configURL: GrizzyClawPaths.configYAML)
            reload()
            return nil
        } catch {
            GrizzyClawLog.error("save scheduled_task_run_timeout_seconds failed: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }
}
