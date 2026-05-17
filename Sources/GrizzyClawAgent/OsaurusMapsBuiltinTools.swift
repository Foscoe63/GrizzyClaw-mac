import Foundation
import GrizzyClawCore

enum OsaurusMapsBuiltinTools {
    static func result(tool: String, arguments: [String: Any]) async -> String {
        let composite = "osaurus.maps.\(tool)"
        switch tool {
        case "maps_search_locations":
            return await searchLocations(composite: composite, arguments: arguments)
        case "maps_get_directions":
            return directions(composite: composite, arguments: arguments)
        case "maps_get_current_location":
            return currentLocationFromArguments(composite: composite, arguments: arguments)
        case "maps_save_location", "maps_drop_pin", "maps_list_guides", "maps_add_to_guide",
            "maps_create_guide":
            return ToolEnvelope.failure(
                tool: composite,
                kind: "not_available_builtin",
                message:
                    "This Apple Maps action is not implemented inside Grizzy. Use `maps_search_locations` for geocoding and open the returned Apple Maps links on device.",
                retryable: false
            )
        default:
            return ToolEnvelope.failure(
                tool: composite,
                kind: "unknown_tool",
                message: "Unknown osaurus.maps tool `\(tool)`."
            )
        }
    }

    /// Built-in maps does not read live GPS. Callers may pass coordinates from another source (e.g. user input).
    private static func currentLocationFromArguments(composite: String, arguments: [String: Any]) -> String {
        let latStr =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["latitude", "lat"]) ?? ""
        let lonStr =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["longitude", "lon", "lng", "long"])
            ?? ""
        let latTrim = latStr.trimmingCharacters(in: .whitespacesAndNewlines)
        let lonTrim = lonStr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !latTrim.isEmpty, !lonTrim.isEmpty,
              let lat = Double(latTrim),
              let lon = Double(lonTrim),
              (-90 ... 90).contains(lat),
              (-180 ... 180).contains(lon)
        else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "missing_args",
                message:
                    "Built-in maps cannot read device GPS. Pass `latitude` and `longitude` (decimal degrees), or use `maps_search_locations` with a place query.",
                retryable: false
            )
        }
        var appleComp = URLComponents(string: "https://maps.apple.com/")!
        appleComp.queryItems = [
            URLQueryItem(name: "ll", value: "\(lat),\(lon)"),
            URLQueryItem(name: "q", value: "Location"),
        ]
        let link = appleComp.url?.absoluteString ?? ""
        return ToolEnvelope.success(
            tool: composite,
            result: [
                "latitude": latTrim,
                "longitude": lonTrim,
                "apple_maps_url": link,
                "note": "Coordinates came from tool arguments, not live GPS.",
            ])
    }

    private static func searchLocations(composite: String, arguments: [String: Any]) async -> String {
        let q =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["query", "q", "text", "address"])
            ?? ""
        guard !q.isEmpty else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Pass `query` (place or address).",
                field: "query"
            )
        }
        var comp = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        comp.queryItems = [
            URLQueryItem(name: "q", value: q),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "8"),
        ]
        guard let url = comp.url else {
            return ToolEnvelope.failure(tool: composite, kind: "invalid_url", message: "Bad geocoder URL.")
        }
        guard case .allowed(let safe) = GrizzyOutboundHTTPURLPolicy.validateAgentHTTPURL(url.absoluteString)
        else {
            return ToolEnvelope.failure(tool: composite, kind: "invalid_url", message: "Bad geocoder URL.")
        }
        do {
            let res = try await OsaurusBuiltinHTTPClient.perform(
                url: safe,
                method: "GET",
                headers: [
                    "User-Agent": "GrizzyClawAgent/1.0 (contact: support@grizzyclaw.invalid)",
                    "Accept-Language": "en",
                ],
                body: nil,
                maxBodyBytes: 2 * 1024 * 1024
            )
            guard let arr = try? JSONSerialization.jsonObject(with: res.body) as? [[String: Any]] else {
                return ToolEnvelope.failure(
                    tool: composite,
                    kind: "parse_error",
                    message: "Unexpected geocoder response.",
                    retryable: true
                )
            }
            let mapped = arr.map { row -> [String: Any] in
                let lat = row["lat"] as? String ?? ""
                let lon = row["lon"] as? String ?? ""
                let name = row["display_name"] as? String ?? ""
                var appleComp = URLComponents(string: "https://maps.apple.com/")!
                appleComp.queryItems = [
                    URLQueryItem(name: "ll", value: "\(lat),\(lon)"),
                    URLQueryItem(name: "q", value: name),
                ]
                let apple = appleComp.url?.absoluteString ?? ""
                return [
                    "name": name,
                    "latitude": lat,
                    "longitude": lon,
                    "apple_maps_url": apple,
                    "raw": row,
                ]
            }
            return ToolEnvelope.success(tool: composite, result: ["query": q, "results": mapped])
        } catch {
            return ToolEnvelope.fromError(error, tool: composite)
        }
    }

    private static func directions(composite: String, arguments: [String: Any]) -> String {
        let from =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["from", "origin", "start"])
            ?? ""
        let to =
            OsaurusBuiltinToolArguments.string(from: arguments, keys: ["to", "destination", "end"])
            ?? ""
        guard !to.isEmpty else {
            return ToolEnvelope.failure(
                tool: composite,
                kind: "invalid_args",
                message: "Pass `to` (destination address or place name). `from` is optional.",
                field: "to"
            )
        }
        var comp = URLComponents(string: "https://maps.apple.com/")!
        var items: [URLQueryItem] = [URLQueryItem(name: "daddr", value: to)]
        if !from.isEmpty {
            items.append(URLQueryItem(name: "saddr", value: from))
        }
        comp.queryItems = items
        let link = comp.url?.absoluteString ?? ""
        return ToolEnvelope.success(
            tool: composite,
            result: [
                "apple_maps_directions_url": link,
                "note":
                    "Open this URL on your iPhone, iPad, or Mac to start turn-by-turn in Apple Maps.",
            ])
    }
}
