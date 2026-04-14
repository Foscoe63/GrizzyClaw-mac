import Foundation

/// Local process / remote HTTP checks — mirrors Python `MCPTab._check_server_running_by_ps` and `_test_remote_connection`.
public enum MCPServerRuntimeStatus {
    public static func matchPatterns(serverData: [String: Any]) -> [String] {
        let cmd = (serverData["command"] as? String) ?? ""
        let rawArgs = serverData["args"]
        let args = normalizeMCPArgs(rawArgs)
        let name = ((serverData["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Patterns are used to detect running processes in `ps auxww` output.
        // We want them to be specific enough to avoid matching other servers, but
        // robust enough to find the actual executable/script.
        var patterns: [String] = []

        // 1. Full command + first few args is usually very specific.
        let cmdMatch = "\(cmd) \(args.prefix(3).map { String(describing: $0) }.joined(separator: " "))".trimmingCharacters(in: .whitespaces)
        if cmdMatch.count >= 8 { patterns.append(cmdMatch) }

        // 2. Specialty wrappers (npx, uvx).
        if cmd == "npx", !args.isEmpty {
            let pkg: String
            if args.count >= 2, args[0] == "-y" {
                pkg = String(describing: args[1])
            } else {
                pkg = String(describing: args[0])
            }
            // pkg is the best pattern for npx servers.
            if pkg.count >= 8 { patterns.append(pkg) }
            if args.count >= 2, args[0] == "-y" {
                patterns.append("npm exec \(pkg)")
            }
        } else if cmd == "uvx", let first = args.first {
            let pkg = String(describing: first)
            if pkg.count >= 8 { patterns.append(pkg) }
        } else if cmd == "node", let p = args.first {
            let path = String(describing: p)
            if path.count >= 8 {
                patterns.append(path)
                patterns.append(URL(fileURLWithPath: path).lastPathComponent)
            }
        }

        // 3. Full argument string and sub-fragments.
        if !args.isEmpty {
            let joinedAll = args.map { String(describing: $0) }.joined(separator: " ")
            if joinedAll.count >= 12 { patterns.append(joinedAll) }

            for a in args {
                let s = String(describing: a).trimmingCharacters(in: .whitespacesAndNewlines)
                // Avoid very short or common patterns like "@", "server", "mcp", ".js"
                // but include reasonably specific arguments (e.g. unique paths).
                if s.count >= 15 {
                    patterns.append(s)
                }
                if s.contains("/") {
                    let last = URL(fileURLWithPath: s).lastPathComponent
                    // High specificity for path tails to avoid "index.js" etc.
                    if last.count >= 12 { patterns.append(last) }
                }
            }
        }

        // 4. Server name (fallback, only if specific).
        if !name.isEmpty, name.count >= 10 { patterns.append(name) }

        var seen = Set<String>()
        var out: [String] = []
        for p in patterns {
            let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            // Stringent length check for status matching: 8 characters minimum.
            guard t.count >= 8 || t == name else { continue }
            if seen.insert(t).inserted {
                out.append(t)
            }
            if out.count >= 36 { break }
        }
        return out
    }

    public static func normalizeMCPArgs(_ args: Any?) -> [String] {
        if args == nil { return [] }
        if let a = args as? [String] { return a.map { String($0) } }
        if let a = args as? [Any] { return a.map { String(describing: $0) } }
        if let s = args as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("["), t.hasSuffix("]"),
               let data = t.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                return arr.map { String(describing: $0) }
            }
            return t.split(whereSeparator: \.isWhitespace).map(String.init)
        }
        return []
    }

    /// Extracts `--allow` + path pairs (e.g. fast-filesystem) and returns remaining args — mirrors Python `MCPDialog` edit prefill / save merge.
    public static func splitAllowFromArgs(_ args: [String]) -> (allowPaths: [String], remainingArgs: [String]) {
        var allow: [String] = []
        var rest: [String] = []
        var i = 0
        while i < args.count {
            if args[i] == "--allow", i + 1 < args.count {
                allow.append(args[i + 1])
                i += 2
            } else {
                rest.append(args[i])
                i += 1
            }
        }
        return (allow, rest)
    }

    /// Returns true if `ps aux` output contains any long pattern (local command servers).
    public static func isLocalCommandServerRunning(serverData: [String: Any]) -> Bool {
        evaluateLocalRunning(serverData: serverData).running
    }

    /// Same `ps aux` scan as ``isLocalCommandServerRunning`` with a short reason for logging (one `ps` invocation).
    public static func evaluateLocalRunning(serverData: [String: Any], psSnapshot: String? = nil) -> (running: Bool, detail: String) {
        guard serverData["command"] != nil else { return (false, "no command field") }
        let name = (serverData["name"] as? String) ?? "?"
        let patterns = matchPatterns(serverData: serverData)
        guard !patterns.isEmpty else { return (false, "empty matchPatterns for name=\(name)") }

        let text: String
        if let psSnapshot {
            text = psSnapshot
        } else {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/ps")
            // Use -ww for wide-wide output to avoid truncation of long command lines (common with npx/uvx).
            task.arguments = ["auxww"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()
            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                return (false, "ps auxww failed: \(error.localizedDescription)")
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let t = String(data: data, encoding: .utf8) else { return (false, "ps auxww unreadable UTF-8") }
            text = t
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let ls = String(line)
            for pat in patterns where ls.contains(pat) {
                let patPreview = pat.count > 100 ? String(pat.prefix(100)) + "…" : pat
                return (true, "name=\(name) matched pattern (\(patPreview.count) chars): \(patPreview)")
            }
        }
        let sample = patterns.prefix(6).map { p in
            let t = p.count > 48 ? String(p.prefix(48)) + "…" : p
            return "'\(t)'"
        }.joined(separator: ", ")
        return (false, "name=\(name) no ps line matched; tried \(patterns.count) patterns e.g. \(sample)")
    }

    /// Fetches a single `ps auxww` snapshot for efficient batch checking.
    public static func fetchPSSnapshot() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["auxww"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    /// Async HTTP reachability — **must not** block the main thread (the old semaphore + `dataTask` pattern could deadlock the UI).
    public static func isRemoteURLReachable(urlString: String, headers: [String: String]) async -> Bool {
        let u = urlString.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var comp = URL(string: u) else { return false }
        if comp.scheme == nil, let fixed = URL(string: "https://\(u)") {
            comp = fixed
        }
        var s = comp.absoluteString
        if !s.hasSuffix("/") { s += "/" }
        guard let url = URL(string: s) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 3
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                return (200..<300).contains(http.statusCode)
            }
            return true
        } catch {
            return false
        }
    }

    /// HTTP GET check matching Python `validate_server_config` for remote MCP (`httpx` accepts 200, 404, or 405 as reachable).
    public static func isRemoteMCPValidationReachable(urlString: String, headers: [String: String]) async -> Bool {
        let u = urlString.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var comp = URL(string: u) else { return false }
        if comp.scheme == nil, let fixed = URL(string: "https://\(u)") {
            comp = fixed
        }
        var s = comp.absoluteString
        if !s.hasSuffix("/") { s += "/" }
        guard let url = URL(string: s) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 5
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                return [200, 404, 405].contains(http.statusCode)
            }
            return false
        } catch {
            return false
        }
    }
}
