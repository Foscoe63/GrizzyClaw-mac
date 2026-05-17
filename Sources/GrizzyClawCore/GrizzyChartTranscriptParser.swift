import Foundation

/// Detects Osaurus-style `render_chart` marker blocks inside tool transcripts or envelope `result.text`.
public enum GrizzyChartTranscriptParser: Sendable {
    public static let blockStart = "---CHART_START---\n"
    public static let blockEnd = "\n---CHART_END---"

    public enum Segment: Sendable, Equatable {
        case text(String)
        case chart(GrizzyChartSpec)
    }

    /// Prefer inner `result.text` when `raw` is a JSON ToolEnvelope (same idea as Osaurus `parseChartSpecFromResult`).
    public static func displaySource(forToolTranscript raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let t = ToolEnvelope.successText(trimmed), !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return t
        }
        return raw
    }

    /// Splits `raw` into alternating text and decoded chart specs. When no markers are present, returns a single `.text`.
    public static func segments(from raw: String) -> [Segment] {
        let source = displaySource(forToolTranscript: raw)
        guard source.range(of: Self.blockStart) != nil else {
            return source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [.text(source)]
        }

        var segments: [Segment] = []
        var searchFrom = source.startIndex

        while searchFrom < source.endIndex {
            guard let startR = source.range(of: Self.blockStart, range: searchFrom ..< source.endIndex) else {
                let tail = String(source[searchFrom...])
                if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(tail))
                }
                break
            }

            if startR.lowerBound > searchFrom {
                let prefix = String(source[searchFrom ..< startR.lowerBound])
                if !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.text(prefix))
                }
            }

            let jsonStart = startR.upperBound
            guard let endR = source.range(of: Self.blockEnd, range: jsonStart ..< source.endIndex) else {
                segments.append(.text(String(source[startR.lowerBound...])))
                break
            }

            let jsonSlice = String(source[jsonStart ..< endR.lowerBound])
            if let data = jsonSlice.data(using: .utf8),
                let spec = try? JSONDecoder().decode(GrizzyChartSpec.self, from: data)
            {
                segments.append(.chart(spec))
            } else {
                segments.append(.text(String(source[startR.lowerBound ..< endR.upperBound])))
            }

            searchFrom = endR.upperBound
        }

        return segments
    }

    public static func containsChartMarkers(_ raw: String) -> Bool {
        displaySource(forToolTranscript: raw).contains(Self.blockStart)
    }
}
