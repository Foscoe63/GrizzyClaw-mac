import Foundation

/// Runs `grizzyclaw` CLI via Python when the pip package is installed (same as Python Settings → ClawHub).
public enum ClawHubPythonBridge: Sendable {

    public struct ProcessOutput: Sendable {
        public let exitCode: Int32
        public let stdout: String
        public let stderr: String
    }

    private static func python3Candidates() -> [String] {
        ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
    }

    /// `grizzyclaw skills install <url>` — returns installed skill id (normalized).
    public static func installSkillFromURL(_ urlString: String) async throws -> String {
        let url = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            throw NSError(
                domain: "ClawHub",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Paste a GitHub repo URL first."]
            )
        }
        var lastError: String = ""
        for py in python3Candidates() where FileManager.default.isExecutableFile(atPath: py) {
            let out = try await runProcess(
                executable: py,
                arguments: ["-m", "grizzyclaw.cli", "skills", "install", url],
                environment: ProcessInfo.processInfo.environment
            )
            if out.exitCode == 0 {
                if let sid = parseInstalledSkillId(out.stdout) {
                    return sid
                }
                lastError = out.stdout + out.stderr
                continue
            }
            let msg = (out.stderr + out.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
            lastError = msg.isEmpty ? "exit \(out.exitCode)" : msg
            if msg.contains("No module named 'grizzyclaw'") || msg.contains("No module named grizzyclaw") {
                continue
            }
            throw NSError(domain: "ClawHub", code: Int(out.exitCode), userInfo: [NSLocalizedDescriptionKey: lastError])
        }
        throw NSError(
            domain: "ClawHub",
            code: 2,
            userInfo: [
                NSLocalizedDescriptionKey:
                    lastError.isEmpty
                    ? "Could not run Python grizzyclaw CLI. Install the GrizzyClaw package (pip install grizzyclaw) or use the Python app to install from URL."
                    : lastError,
            ]
        )
    }

    /// Best-effort version / update check using the same registry helpers as Python (requires `grizzyclaw` import).
    public static func checkSkillUpdates(enabledSkillIds: [String]) async -> Result<String, Error> {
        let ids = enabledSkillIds.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !ids.isEmpty else {
            return .success("No skills in the enabled list.")
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: ids),
              let jsonStr = String(data: jsonData, encoding: .utf8)
        else {
            return .failure(NSError(domain: "ClawHub", code: 3, userInfo: [NSLocalizedDescriptionKey: "Encoding failed"]))
        }
        let script = """
        import json, sys
        raw = sys.stdin.read()
        ids = json.loads(raw)
        lines = []
        try:
            from grizzyclaw.skills.registry import get_skill, get_skill_version, check_skill_update
        except Exception as e:
            print("IMPORT_ERROR: " + str(e), file=sys.stderr)
            sys.exit(2)
        for skill_id in ids:
            meta = get_skill(skill_id)
            ver = get_skill_version(skill_id) if meta else None
            name = meta.name if meta else skill_id
            if ver:
                lines.append(f"{name}: v{ver}")
            else:
                lines.append(f"{name}: (no version)")
            result = check_skill_update(skill_id)
            if result:
                cur, latest = result
                lines.append(f"  → Update available: {cur} → {latest}")
        if not lines:
            print("No version info or updatable skills. Add version/update_url to skills to see updates.")
        else:
            print("\\n".join(lines))
        """
        for py in python3Candidates() where FileManager.default.isExecutableFile(atPath: py) {
            do {
                let out = try await runProcess(
                    executable: py,
                    arguments: ["-c", script],
                    environment: ProcessInfo.processInfo.environment,
                    stdinString: jsonStr + "\n"
                )
                if out.exitCode == 0 {
                    let t = out.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    return .success(t.isEmpty ? "Done." : t)
                }
                let err = (out.stderr + out.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
                if err.contains("IMPORT_ERROR") || err.contains("No module named 'grizzyclaw'") {
                    continue
                }
                return .failure(NSError(domain: "ClawHub", code: Int(out.exitCode), userInfo: [NSLocalizedDescriptionKey: err]))
            } catch {
                return .failure(error)
            }
        }
        return .failure(
            NSError(
                domain: "ClawHub",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Install the GrizzyClaw Python package to check versions: pip install grizzyclaw",
                ]
            )
        )
    }

    private static func parseInstalledSkillId(_ stdout: String) -> String? {
        let lines = stdout.split(whereSeparator: \.isNewline).map(String.init)
        for line in lines {
            if let range = line.range(of: "Installed skill:", options: .caseInsensitive) {
                let rest = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if let first = rest.split(separator: " ").first {
                    return String(first)
                }
            }
        }
        return nil
    }

    private static func runProcess(
        executable: String,
        arguments: [String],
        environment: [String: String],
        stdinString: String? = nil
    ) async throws -> ProcessOutput {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: executable)
                p.arguments = arguments
                p.environment = environment
                let outPipe = Pipe()
                let errPipe = Pipe()
                p.standardOutput = outPipe
                p.standardError = errPipe
                if let stdinString {
                    let inPipe = Pipe()
                    p.standardInput = inPipe
                    if let data = stdinString.data(using: .utf8) {
                        inPipe.fileHandleForWriting.write(data)
                    }
                    inPipe.fileHandleForWriting.closeFile()
                }
                do {
                    try p.run()
                    p.waitUntilExit()
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout = String(data: outData, encoding: .utf8) ?? ""
                    let stderr = String(data: errData, encoding: .utf8) ?? ""
                    cont.resume(returning: ProcessOutput(exitCode: p.terminationStatus, stdout: stdout, stderr: stderr))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
