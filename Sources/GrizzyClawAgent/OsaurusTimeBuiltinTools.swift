import Foundation
import GrizzyClawCore

/// Native Swift implementation of `osaurus.time` tools (no network, no Osaurus dylib).
/// Argument keys are tolerant of common model variants (`timezone` vs `time_zone`, etc.).
enum OsaurusTimeBuiltinTools {
    static func result(tool: String, arguments: [String: Any]) -> String {
        let composite = "osaurus.time.\(tool)"
        switch tool {
        case "current_time":
            return currentTime(arguments: arguments, composite: composite)
        case "format_date":
            return formatDate(arguments: arguments, composite: composite)
        case "parse_date":
            return parseDate(arguments: arguments, composite: composite)
        case "convert_timezone":
            return convertTimezone(arguments: arguments, composite: composite)
        case "add_duration":
            return addDuration(arguments: arguments, composite: composite)
        case "diff_dates":
            return diffDates(arguments: arguments, composite: composite)
        case "list_timezones":
            return listTimezones(arguments: arguments, composite: composite)
        default:
            return ToolEnvelope.failure(
                tool: composite,
                kind: "unknown_tool",
                message: "Unknown osaurus.time tool `\(tool)`."
            )
        }
    }

    // MARK: - Implementations

    private static func currentTime(arguments: [String: Any], composite: String) -> String {
        let tzId = string(from: arguments, keys: ["timezone", "time_zone", "iana", "zone"])
            ?? TimeZone.current.identifier
        guard let tz = TimeZone(identifier: tzId) else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Unknown IANA timezone `\(tzId)`.",
                field: "timezone"
            )
        }
        let now = Date()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let comps = cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond, .weekday], from: now)
        let iso = iso8601String(instant: now, timeZone: tz)
        return ToolEnvelope.success(
            tool: composite,
            result: [
                "timezone": tzId,
                "unix": now.timeIntervalSince1970,
                "iso8601": iso,
                "components": comps.asDict(),
            ])
    }

    private static func formatDate(arguments: [String: Any], composite: String) -> String {
        guard let base = parseInstant(arguments, keys: ["unix", "timestamp", "epoch", "instant"])
        else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Provide `unix` / `timestamp` (seconds since 1970) or `instant` ISO-8601 string.",
                field: "unix"
            )
        }
        let fmt = (string(from: arguments, keys: ["format", "style"]) ?? "iso8601").lowercased()
        let tzId = string(from: arguments, keys: ["timezone", "time_zone", "iana"])
        let tz = tzId.flatMap { TimeZone(identifier: $0) } ?? .current
        let localeId = string(from: arguments, keys: ["locale", "locale_identifier"])
        let locale = Locale(identifier: localeId ?? "en_US_POSIX")

        switch fmt {
        case "iso8601", "iso", "rfc3339":
            return ToolEnvelope.success(
                tool: composite,
                result: ["text": iso8601String(instant: base, timeZone: tz)])
        case "unix", "epoch":
            return ToolEnvelope.success(
                tool: composite,
                result: ["unix": base.timeIntervalSince1970])
        case "relative":
            let f = RelativeDateTimeFormatter()
            f.locale = locale
            let s = f.localizedString(for: base, relativeTo: Date())
            return ToolEnvelope.success(tool: composite, result: ["text": s])
        default:
            let df = DateFormatter()
            df.locale = locale
            df.timeZone = tz
            df.dateFormat = fmt
            return ToolEnvelope.success(tool: composite, result: ["text": df.string(from: base)])
        }
    }

    private static func parseDate(arguments: [String: Any], composite: String) -> String {
        let raw = string(from: arguments, keys: ["input", "date", "string", "value", "text"]) ?? ""
        guard !raw.isEmpty else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Missing date string (`input` / `date` / `string`).",
                field: "input"
            )
        }
        let tzId = string(from: arguments, keys: ["timezone", "time_zone", "iana"])
        let tz = tzId.flatMap { TimeZone(identifier: $0) } ?? .current
        guard let date = parseFlexibleDateString(raw, defaultTimeZone: tz) else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Could not parse date string: `\(raw.prefix(200))`",
                field: "input"
            )
        }
        return ToolEnvelope.success(
            tool: composite,
            result: [
                "unix": date.timeIntervalSince1970,
                "iso8601": iso8601String(instant: date, timeZone: tz),
                "timezone": tz.identifier,
            ])
    }

    private static func convertTimezone(arguments: [String: Any], composite: String) -> String {
        guard let instant = parseInstant(arguments, keys: ["unix", "timestamp", "epoch", "instant"])
        else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Provide `unix` / `timestamp` or `instant` to convert.",
                field: "unix"
            )
        }
        let toId =
            string(from: arguments, keys: ["to_timezone", "target_timezone", "timezone", "to"])
            ?? TimeZone.current.identifier
        guard let toTz = TimeZone(identifier: toId) else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Unknown target timezone `\(toId)`.",
                field: "to_timezone"
            )
        }
        return ToolEnvelope.success(
            tool: composite,
            result: [
                "unix": instant.timeIntervalSince1970,
                "iso8601": iso8601String(instant: instant, timeZone: toTz),
                "timezone": toTz.identifier,
            ])
    }

    private static func addDuration(arguments: [String: Any], composite: String) -> String {
        guard let base = parseInstant(arguments, keys: ["unix", "timestamp", "epoch", "instant", "base"])
        else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Provide base instant via `unix` / `timestamp` / `instant` / `base`.",
                field: "unix"
            )
        }
        var delta: TimeInterval?
        if let s = string(from: arguments, keys: ["seconds", "delta_seconds", "sec"]) {
            delta = Double(s.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if delta == nil, let n = arguments["seconds"] as? NSNumber {
            delta = n.doubleValue
        }
        if delta == nil, let isoDur = string(from: arguments, keys: ["iso_duration", "duration", "iso8601_duration"]) {
            delta = parseISO8601DurationSeconds(isoDur)
        }
        guard let d = delta else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Provide `seconds` (number) and/or `iso_duration` (e.g. P1DT2H).",
                field: "seconds"
            )
        }
        let out = base.addingTimeInterval(d)
        let tzId = string(from: arguments, keys: ["timezone", "time_zone", "iana"])
        let tz = tzId.flatMap { TimeZone(identifier: $0) } ?? .current
        return ToolEnvelope.success(
            tool: composite,
            result: [
                "unix": out.timeIntervalSince1970,
                "iso8601": iso8601String(instant: out, timeZone: tz),
                "timezone": tz.identifier,
                "added_seconds": d,
            ])
    }

    private static func diffDates(arguments: [String: Any], composite: String) -> String {
        guard let a = parseInstant(arguments, keys: ["a", "from", "start", "t1"]),
            let b = parseInstant(arguments, keys: ["b", "to", "end", "t2"])
        else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Provide two instants: `a`/`b` (or `from`/`to`) as unix timestamps or ISO strings.",
                field: "a"
            )
        }
        let dt = b.timeIntervalSince(a)
        let sign = dt >= 0 ? 1.0 : -1.0
        let absSec = abs(dt)
        let days = Int(absSec / 86400)
        let hours = Int((absSec.truncatingRemainder(dividingBy: 86400)) / 3600)
        let mins = Int((absSec.truncatingRemainder(dividingBy: 3600)) / 60)
        let secs = absSec.truncatingRemainder(dividingBy: 60)
        let human =
            "\(sign > 0 ? "" : "-")\(days)d \(hours)h \(mins)m \(String(format: "%.3f", secs))s"
        let isoDur = "P\(days)DT\(hours)H\(mins)M\(String(format: "%.3f", secs))S"
        return ToolEnvelope.success(
            tool: composite,
            result: [
                "total_seconds": dt,
                "iso8601_duration": isoDur,
                "human": human,
            ])
    }

    private static func listTimezones(arguments: [String: Any], composite: String) -> String {
        let prefix =
            (string(from: arguments, keys: ["prefix", "starts_with", "filter"]) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let all = TimeZone.knownTimeZoneIdentifiers.sorted()
        let filtered: [String] =
            prefix.isEmpty
            ? all
            : all.filter { $0.hasPrefix(prefix) }
        let cap = 500
        let slice = Array(filtered.prefix(cap))
        var result: [String: Any] = [
            "count": filtered.count,
            "returned": slice.count,
            "timezones": slice,
        ]
        if filtered.count > cap {
            result["truncated"] = true
            result["note"] = "List truncated to \(cap) entries; narrow `prefix` (e.g. `America/`)."
        }
        return ToolEnvelope.success(tool: composite, result: result)
    }

    // MARK: - Parsing helpers

    private static func string(from args: [String: Any], keys: [String]) -> String? {
        for k in keys {
            if let s = args[k] as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
            if let n = args[k] as? NSNumber {
                return n.stringValue
            }
        }
        return nil
    }

    private static func parseInstant(_ args: [String: Any], keys: [String]) -> Date? {
        for k in keys {
            guard let v = args[k] else { continue }
            if let n = v as? NSNumber {
                let t = n.doubleValue
                // Heuristic: seconds vs milliseconds
                if t > 1e12 { return Date(timeIntervalSince1970: t / 1000.0) }
                return Date(timeIntervalSince1970: t)
            }
            if let s = v as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { continue }
                if let d = Double(t), !t.contains("-") && !t.contains(":") {
                    if d > 1e12 { return Date(timeIntervalSince1970: d / 1000.0) }
                    return Date(timeIntervalSince1970: d)
                }
                if let d = parseFlexibleDateString(t, defaultTimeZone: TimeZone(secondsFromGMT: 0)!) {
                    return d
                }
                if let d = parseFlexibleDateString(t, defaultTimeZone: .current) { return d }
            }
        }
        return nil
    }

    private static func parseFlexibleDateString(_ raw: String, defaultTimeZone: TimeZone) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }

        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: s) { return d }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = defaultTimeZone
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ssZZZZZ",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
        ]
        for p in patterns {
            df.dateFormat = p
            if let d = df.date(from: s) { return d }
        }
        return nil
    }

    private static func iso8601String(instant: Date, timeZone: TimeZone) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = timeZone
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: instant)
    }

    /// Minimal ISO-8601 duration parser: `PnDTnHnMnS` (calendar months/years are approximate).
    private static func parseISO8601DurationSeconds(_ raw: String) -> TimeInterval? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("P") else { return nil }
        s.removeFirst()
        var timePart = ""
        if let r = s.range(of: "T") {
            timePart = String(s[s.index(after: r.lowerBound)...])
            s = String(s[..<r.lowerBound])
        }
        let dPart = parseDurationSection(s, units: [
            "D": 86400, "W": 604800, "M": 30 * 86400, "Y": 365 * 86400,
        ])
        let tPart = parseDurationSection(timePart, units: ["H": 3600, "M": 60, "S": 1])
        guard !dPart.isNaN, !tPart.isNaN else { return nil }
        return dPart + tPart
    }

    private static func parseDurationSection(_ str: String, units: [Character: TimeInterval]) -> TimeInterval {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        var i = trimmed.startIndex
        var sum: TimeInterval = 0
        while i < trimmed.endIndex {
            let startNum = i
            while i < trimmed.endIndex, trimmed[i].isNumber || trimmed[i] == "." {
                trimmed.formIndex(after: &i)
            }
            if startNum == i { return .nan }
            guard let v = Double(String(trimmed[startNum..<i])) else { return .nan }
            guard i < trimmed.endIndex else { return .nan }
            let u = trimmed[i]
            trimmed.formIndex(after: &i)
            guard let mult = units[u] else { return .nan }
            sum += v * mult
        }
        return sum
    }
}

private extension DateComponents {
    func asDict() -> [String: Int] {
        var d: [String: Int] = [:]
        if let y = year { d["year"] = y }
        if let m = month { d["month"] = m }
        if let day = day { d["day"] = day }
        if let h = hour { d["hour"] = h }
        if let mi = minute { d["minute"] = mi }
        if let s = second { d["second"] = s }
        if let w = weekday { d["weekday"] = w }
        return d
    }
}
