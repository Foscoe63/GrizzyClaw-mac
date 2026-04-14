import Darwin
import Foundation

/// Default localhost port for `GrizzyClawCLI serve` (Osaurus uses 1337; we pick a different default to avoid clashes).
public enum GrizzyClawRuntimeConstants {
    public static let controlHTTPPort: Int = 18_765
}

// MARK: - Doctor report (Osaurus-style health JSON; GrizzyClaw-specific checks)

/// Aggregated health snapshot for CLI, `GET /doctor`, and tooling.
public struct GrizzyClawDoctorReport: Codable, Sendable, Equatable {
    public var status: String
    public var timestamp: String
    public var app: DoctorAppSection
    public var checks: [DoctorCheck]
    public var hints: [String]
    public var localInference: LocalInferenceRuntimeSection
    public var sandbox: SandboxRuntimeSection
    public var controlPlane: ControlPlaneRuntimeSection
}

public struct DoctorAppSection: Codable, Sendable, Equatable {
    public var name: String
    public var version: String
    public var bundleIdentifier: String
}

public struct DoctorCheck: Codable, Sendable, Equatable {
    public var id: String
    public var ok: Bool
    public var detail: String
}

/// On Apple silicon, GrizzyClaw can use **mlx-swift-lm** (`llm_provider: mlx`) with Hugging Face downloads under `~/.grizzyclaw/mlx_models/`. Remote HTTP APIs remain the usual path on all Macs.
public struct LocalInferenceRuntimeSection: Codable, Sendable, Equatable {
    public var bundledEngine: String
    public var appleSilicon: Bool
    public var primaryMode: String
    public var detail: String
}

/// Parallels Osaurus’s Linux VM sandbox (Containerization + vsock). Not shipped in GrizzyClaw; tools run on the host via MCP / agent.
public struct SandboxRuntimeSection: Codable, Sendable, Equatable {
    public var linuxVMExecutionAvailable: Bool
    public var detail: String
}

/// HTTP control API (`serve`); always “capable” when this module is linked — actual server runs when `GrizzyClawCLI serve` starts.
public struct ControlPlaneRuntimeSection: Codable, Sendable, Equatable {
    public var embeddedHTTPServer: Bool
    public var defaultPort: Int
    public var endpoints: [String]
    public var detail: String
}

// MARK: - Build report

public enum GrizzyClawDoctorService {
    /// Builds a fresh report (safe to call from any thread; only reads filesystem metadata).
    public static func buildReport() -> GrizzyClawDoctorReport {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = fmt.string(from: Date())
        var checks: [DoctorCheck] = []
        var hints: [String] = []

        let fm = FileManager.default
        let ud = GrizzyClawPaths.userDataDirectory
        let udExists = fm.fileExists(atPath: ud.path)
        checks.append(
            DoctorCheck(
                id: "user_data_dir",
                ok: udExists,
                detail: udExists ? ud.path : "missing \(ud.path)"
            )
        )
        if !udExists {
            hints.append("Create ~/.grizzyclaw or launch the app once so the data directory exists.")
        }

        let cfg = GrizzyClawPaths.configYAML
        let cfgExists = fm.fileExists(atPath: cfg.path)
        checks.append(
            DoctorCheck(
                id: "config_yaml",
                ok: cfgExists,
                detail: cfgExists ? "present: \(cfg.path)" : "optional missing: \(cfg.path)"
            )
        )

        let ws = GrizzyClawPaths.workspacesJSON
        let wsExists = fm.fileExists(atPath: ws.path)
        checks.append(
            DoctorCheck(
                id: "workspaces_json",
                ok: wsExists,
                detail: wsExists ? "present" : "missing (workspaces UI may be empty until created)"
            )
        )
        if !wsExists {
            hints.append("Add workspaces via the Workspaces window or copy workspaces.json from the Python app.")
        }

        let sock = GrizzyClawPaths.daemonSocket
        let daemonListening = fm.fileExists(atPath: sock.path)
        checks.append(
            DoctorCheck(
                id: "daemon_socket_file",
                ok: true,
                detail: daemonListening
                    ? "socket path exists (Python daemon may be running): \(sock.path)"
                    : "no socket at \(sock.path) (expected if only the Swift app is used)"
            )
        )

        let status = udExists ? "ok" : "degraded"

        let appleSilicon = Self.isAppleSiliconHost()
        let mlxEngineLabel = appleSilicon ? "mlx-swift-lm" : "none"
        let mlxDetail: String
        if appleSilicon {
            mlxDetail =
                "On Apple silicon you can set llm_provider to mlx and llm_model to a Hugging Face repo id "
                + "(see mlx_model in ~/.grizzyclaw/config.yaml). By default weights download under \(GrizzyClawPaths.mlxModelsDirectory.path); "
                + "override with mlx_models_directory in config or workspace YAML. "
                + "Intel Macs cannot use the mlx provider build."
        } else {
            mlxDetail =
                "This Mac is not Apple silicon; use LM Studio, Ollama, OpenAI-compatible, or Anthropic endpoints. "
                + "The mlx on-device provider is available only on arm64."
        }

        let report = GrizzyClawDoctorReport(
            status: status,
            timestamp: timestamp,
            app: DoctorAppSection(
                name: "GrizzyClaw",
                version: AppInfo.versionLabel,
                bundleIdentifier: AppInfo.bundleIdentifier
            ),
            checks: checks,
            hints: hints,
            localInference: LocalInferenceRuntimeSection(
                bundledEngine: mlxEngineLabel,
                appleSilicon: appleSilicon,
                primaryMode: appleSilicon ? "http_compatible_or_mlx" : "http_compatible_providers",
                detail: mlxDetail
            ),
            sandbox: SandboxRuntimeSection(
                linuxVMExecutionAvailable: false,
                detail:
                    "Isolated Linux VM agent execution (Osaurus sandbox) is not part of GrizzyClaw. "
                    + "Tools and MCP servers run on this Mac with your permissions."
            ),
            controlPlane: ControlPlaneRuntimeSection(
                embeddedHTTPServer: true,
                defaultPort: GrizzyClawRuntimeConstants.controlHTTPPort,
                endpoints: ["/health", "/doctor"],
                detail:
                    "Run `swift run GrizzyClawCLI serve` (or the GrizzyClawCLI binary) to expose localhost HTTP. "
                    + "Osaurus-style always-on server + remote relay is out of scope unless added later."
            )
        )
        return report
    }

    private static func isAppleSiliconHost() -> Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let rc = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return rc == 0 && value != 0
    }
}
