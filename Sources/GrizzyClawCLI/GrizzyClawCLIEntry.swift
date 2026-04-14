import Foundation
import GrizzyClawCore

/// Headless CLI: `doctor` (health JSON) and `serve` (localhost HTTP control plane — Osaurus-style `/doctor`, `/health`).
@main
enum GrizzyClawCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let cmd = args.first else {
            printUsage()
            exit(64)
        }
        let rest = Array(args.dropFirst())
        switch cmd {
        case "doctor":
            await runDoctor(arguments: rest)
        case "serve":
            await runServe(arguments: rest)
        case "--help", "-h":
            printUsage()
            exit(0)
        default:
            printUsage()
            exit(64)
        }
    }

    private static func printUsage() {
        let port = GrizzyClawRuntimeConstants.controlHTTPPort
        fputs(
            """
            GrizzyClawCLI — control plane & diagnostics (no GUI).

              doctor [--pretty]     Print JSON health report (same as GET http://127.0.0.1:\(port)/doctor when serve is running).

              serve [--port N] [--bind HOST]   Bind loopback HTTP (default \(port)). GET /health, /doctor. Press Enter to stop.

            """,
            stderr
        )
    }

    private static func runDoctor(arguments: [String]) async {
        let pretty = arguments.contains("--pretty")
        let report = GrizzyClawDoctorService.buildReport()
        let enc = JSONEncoder()
        if pretty {
            enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        } else {
            enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        }
        do {
            let data = try enc.encode(report)
            if let s = String(data: data, encoding: .utf8) {
                print(s)
            }
            exit(0)
        } catch {
            fputs("encode: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func runServe(arguments: [String]) async {
        var port = GrizzyClawRuntimeConstants.controlHTTPPort
        var host = "127.0.0.1"
        var i = 0
        while i < arguments.count {
            switch arguments[i] {
            case "--port":
                guard i + 1 < arguments.count, let p = Int(arguments[i + 1]), (1 ..< 65_536).contains(p) else {
                    fputs("--port requires an integer 1–65535\n", stderr)
                    exit(64)
                }
                port = p
                i += 2
            case "--bind":
                guard i + 1 < arguments.count else {
                    fputs("--bind requires a host (e.g. 127.0.0.1)\n", stderr)
                    exit(64)
                }
                host = arguments[i + 1]
                i += 2
            default:
                fputs("unknown argument: \(arguments[i])\n", stderr)
                printUsage()
                exit(64)
            }
        }

        let server = GrizzyClawControlHTTPServer()
        do {
            try await server.start(host: host, port: port)
            fputs(
                "GrizzyClaw control plane: http://\(host):\(port)/health  http://\(host):\(port)/doctor\nPress Enter to stop.\n",
                stderr
            )
            _ = readLine()
            try await server.stop()
            exit(0)
        } catch {
            fputs("serve: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
