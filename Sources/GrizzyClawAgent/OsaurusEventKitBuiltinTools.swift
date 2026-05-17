import EventKit
import Foundation
import GrizzyClawCore

enum OsaurusEventKitBuiltinTools {
    // MARK: - Calendar

    static func calendar(tool: String, arguments: [String: Any]) async -> String {
        let composite = "osaurus.calendar.\(tool)"
        let store = EKEventStore()
        if #available(iOS 17.0, macOS 14.0, *) {
            do {
                guard try await store.requestFullAccessToEvents() else {
                    return ToolEnvelope.failure(
                        tool: composite,
                        kind: "permission_denied",
                        message: "Calendar access was denied.",
                        retryable: false
                    )
                }
            } catch {
                return ToolEnvelope.fromError(error, tool: composite)
            }
        } else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "unsupported_os",
                message: "Calendar tools require iOS 17+ / macOS 14+.",
                retryable: false
            )
        }
        switch tool {
        case "get_events", "search_events":
            return listEvents(store: store, composite: composite, arguments: arguments)
        case "create_event":
            return createEvent(store: store, composite: composite, arguments: arguments)
        case "open_event":
            let id =
                OsaurusBuiltinToolArguments.string(from: arguments, keys: ["id", "event_id", "identifier"])
                ?? ""
            guard !id.isEmpty else {
                return ToolEnvelope.failure(
                    tool: composite,
                    kind: "invalid_args",
                    message: "Pass `id` (EventKit event identifier).",
                    field: "id"
                )
            }
            return ToolEnvelope.success(
                tool: composite,
                result: [
                    "event_id": id,
                    "note": "Use the Calendar app to open this identifier; Grizzy does not embed Calendar UI.",
                ])
        default:
            return ToolEnvelope.failure(
                tool: composite,
                kind: "unknown_tool",
                message: "Unknown osaurus.calendar tool `\(tool)`."
            )
        }
    }

    // MARK: - Reminders

    static func reminders(tool: String, arguments: [String: Any]) async -> String {
        let composite = "osaurus.reminders.\(tool)"
        let store = EKEventStore()
        if #available(iOS 17.0, macOS 14.0, *) {
            do {
                guard try await store.requestFullAccessToReminders() else {
                    return ToolEnvelope.failure(
                        tool: composite,
                        kind: "permission_denied",
                        message: "Reminders access was denied.",
                        retryable: false
                    )
                }
            } catch {
                return ToolEnvelope.fromError(error, tool: composite)
            }
        } else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "unsupported_os",
                message: "Reminders tools require iOS 17+ / macOS 14+.",
                retryable: false
            )
        }
        switch tool {
        case "get_lists":
            let lists = store.calendars(for: .reminder)
            let rows: [[String: Any]] = lists.map {
                ["id": $0.calendarIdentifier, "title": $0.title]
            }
            return ToolEnvelope.success(tool: composite, result: ["lists": rows])
        case "get_reminders", "search_reminders":
            return await fetchReminders(store: store, composite: composite, arguments: arguments)
        case "create_reminder":
            return await createReminder(store: store, composite: composite, arguments: arguments)
        case "open_reminder":
            return ToolEnvelope.success(
                tool: composite,
                result: [
                    "note":
                        "Open the Reminders app to manage items; Grizzy does not deep-link into a specific reminder row."
                ])
        default:
            return ToolEnvelope.failure(
                tool: composite,
                kind: "unknown_tool",
                message: "Unknown osaurus.reminders tool `\(tool)`."
            )
        }
    }

    // MARK: - Calendar impl

    private static func listEvents(
        store: EKEventStore,
        composite: String,
        arguments: [String: Any]
    ) -> String {
        let (start, end) = dateRange(arguments: arguments, defaultDaysForward: 14)
        let calendars = store.calendars(for: .event)
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = store.events(matching: pred)
        let q =
            (OsaurusBuiltinToolArguments.string(from: arguments, keys: ["query", "q", "text"]) ?? "")
            .lowercased()
        let filtered: [EKEvent] =
            q.isEmpty
            ? events
            : events.filter {
                ($0.title ?? "").lowercased().contains(q) || ($0.notes ?? "").lowercased().contains(q)
            }
        let rows: [[String: Any]] = filtered.prefix(80).map { e in
            [
                "id": e.eventIdentifier ?? "",
                "title": e.title ?? "",
                "start": e.startDate.timeIntervalSince1970,
                "end": e.endDate.timeIntervalSince1970,
                "calendar": e.calendar?.title ?? "",
                "location": e.location ?? "",
                "notes": e.notes ?? "",
            ]
        }
        return ToolEnvelope.success(tool: composite, result: ["events": rows, "count": rows.count])
    }

    private static func createEvent(
        store: EKEventStore,
        composite: String,
        arguments: [String: Any]
    ) -> String {
        let title =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["title", "summary", "name"])
            ?? "New event"
        guard let start = parseDateArg(arguments, keys: ["start", "start_date", "begin", "unix"]),
            let end = parseDateArg(arguments, keys: ["end", "end_date", "finish", "until"])
        else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Provide `start` and `end` as unix seconds or ISO-8601 strings.",
                field: "start"
            )
        }
        let ev = EKEvent(eventStore: store)
        ev.title = title
        ev.startDate = start
        ev.endDate = max(end, start.addingTimeInterval(300))
        ev.calendar = store.defaultCalendarForNewEvents ?? store.calendars(for: .event).first
        guard ev.calendar != nil else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "configuration_error",
                message: "No writable calendar found.",
                retryable: false
            )
        }
        ev.location = OsaurusBuiltinToolArguments.string(from: arguments, keys: ["location", "where"])
        do {
            try store.save(ev, span: .thisEvent)
            return ToolEnvelope.success(
                tool: composite,
                result: ["id": ev.eventIdentifier ?? "", "title": ev.title ?? title]
            )
        } catch {
            return ToolEnvelope.fromError(error, tool: composite)
        }
    }

    // MARK: - Reminders impl

    private static func fetchReminders(
        store: EKEventStore,
        composite: String,
        arguments: [String: Any]
    ) async -> String {
        let listId = OsaurusBuiltinToolArguments.string(from: arguments, keys: ["list_id", "list"])
        let calendars: [EKCalendar]? =
            if let listId, !listId.isEmpty {
                store.calendars(for: .reminder).filter { $0.calendarIdentifier == listId }
            } else { nil }
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
        let qFilter =
            (OsaurusBuiltinToolArguments.string(from: arguments, keys: ["query", "q", "text"]) ?? "")
            .lowercased()
        let rows: [[String: String]] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: pred) { rems in
                let list = rems ?? []
                let filtered =
                    qFilter.isEmpty
                    ? list
                    : list.filter {
                        ($0.title ?? "").lowercased().contains(qFilter)
                            || ($0.notes ?? "").lowercased().contains(qFilter)
                    }
                let mapped: [[String: String]] = filtered.prefix(120).map { r in
                    [
                        "id": r.calendarItemIdentifier,
                        "title": r.title ?? "",
                        "notes": r.notes ?? "",
                        "due": r.dueDateComponents.map { "\($0)" } ?? "",
                        "completed": r.isCompleted ? "true" : "false",
                    ]
                }
                cont.resume(returning: mapped)
            }
        }
        return ToolEnvelope.success(tool: composite, result: ["reminders": rows, "count": rows.count])
    }

    private static func createReminder(
        store: EKEventStore,
        composite: String,
        arguments: [String: Any]
    ) async -> String {
        let title =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["title", "text", "name"])
            ?? "Reminder"
        let listId = OsaurusBuiltinToolArguments.string(from: arguments, keys: ["list_id", "list"])
        let cal =
            store.calendars(for: .reminder).first { $0.calendarIdentifier == listId }
            ?? store.defaultCalendarForNewReminders()
            ?? store.calendars(for: .reminder).first
        guard let cal else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "configuration_error",
                message: "No reminder list available to save into.",
                retryable: false
            )
        }
        let r = EKReminder(eventStore: store)
        r.title = title
        r.calendar = cal
        r.priority = 0
        if let due = parseDateArg(arguments, keys: ["due", "due_date", "when"]) {
            r.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due)
        }
        do {
            try store.save(r, commit: true)
            return ToolEnvelope.success(
                tool: composite,
                result: ["id": r.calendarItemIdentifier, "title": r.title ?? title]
            )
        } catch {
            return ToolEnvelope.fromError(error, tool: composite)
        }
    }

    // MARK: - Helpers

    private static func dateRange(arguments: [String: Any], defaultDaysForward: Int) -> (Date, Date) {
        let start =
            parseDateArg(arguments, keys: ["start", "start_date", "from", "begin"])
            ?? Date().addingTimeInterval(-3600)
        let end =
            parseDateArg(arguments, keys: ["end", "end_date", "to", "until"])
            ?? start.addingTimeInterval(Double(defaultDaysForward * 86400))
        return (min(start, end), max(start, end))
    }

    private static func parseDateArg(_ args: [String: Any], keys: [String]) -> Date? {
        for k in keys {
            guard let v = args[k] else { continue }
            if let n = v as? NSNumber {
                let t = n.doubleValue
                if t > 1e12 { return Date(timeIntervalSince1970: t / 1000.0) }
                return Date(timeIntervalSince1970: t)
            }
            if let s = v as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { continue }
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = iso.date(from: t) { return d }
                iso.formatOptions = [.withInternetDateTime]
                if let d = iso.date(from: t) { return d }
            }
        }
        return nil
    }
}
