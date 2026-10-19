import Foundation

/// Series payload for `render_chart` — same shape as Osaurus `ChartSeries` JSON.
public struct GrizzyChartSeries: Codable, Equatable, Sendable {
    public var name: String
    public var data: [Double?]
}

/// Chart card payload — same fields Osaurus `ChartSpec` encodes for inline chart UI.
public struct GrizzyChartSpec: Codable, Equatable, Sendable {
    public var chartType: String
    public var title: String?
    public var categories: [String]?
    public var series: [GrizzyChartSeries]
    public var tooltipSuffix: String?
    public var note: String?

    public static let validChartTypes: Set<String> = [
        "column", "bar", "line", "spline", "area", "areaspline",
        "pie", "scatter", "bubble", "gauge", "waterfall", "boxplot",
    ]

    public init(
        chartType: String,
        title: String? = nil,
        categories: [String]? = nil,
        series: [GrizzyChartSeries],
        tooltipSuffix: String? = nil,
        note: String? = nil
    ) {
        self.chartType = chartType
        self.title = title
        self.categories = categories
        self.series = series
        self.tooltipSuffix = tooltipSuffix
        self.note = note
    }
}

/// Port of Osaurus `RenderChartTool` logic — no HTTP; produces the same `---CHART_START---` marker block in the success `text` field.
public enum OsaurusRenderChartParity {
    private static let maxRows = 500

    private static var chartTypeList: String {
        GrizzyChartSpec.validChartTypes.sorted().joined(separator: ", ")
    }

    public static func execute(tool: String, arguments: [String: Any]) -> String {
        let dataRaw = (arguments["data"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !dataRaw.isEmpty else {
            return ToolEnvelope.failure(
                tool: tool,
                kind: "invalid_args",
                message: "Missing required argument `data`.",
                field: "data",
                expected: "raw file content (CSV / TSV / JSON array of objects)",
                retryable: false
            )
        }

        let chartType = resolveChartType(from: arguments)
        guard let chartType else {
            return ToolEnvelope.failure(
                tool: tool,
                kind: "invalid_args",
                message: "Missing required argument `chartType`.",
                field: "chartType",
                expected: "one of \(chartTypeList)",
                retryable: false
            )
        }

        guard GrizzyChartSpec.validChartTypes.contains(chartType) else {
            return ToolEnvelope.failure(
                tool: tool,
                kind: "invalid_args",
                message: "Unknown `chartType`: `\(chartType)`. Use one of: \(chartTypeList).",
                field: "chartType",
                expected: "one of \(chartTypeList)",
                retryable: false
            )
        }

        guard let seriesCols = OsaurusArgumentCoercion.stringArray(arguments["series"])
            ?? parseStringArrayFromJSON(arguments["series"]),
            !seriesCols.isEmpty
        else {
            return ToolEnvelope.failure(
                tool: tool,
                kind: "invalid_args",
                message: "Missing required argument `series` (array of column names).",
                field: "series",
                expected: "non-empty array of column-name strings",
                retryable: false
            )
        }

        let format = ((arguments["format"] as? String) ?? "csv").lowercased()
        let xColumn = arguments["xColumn"] as? String
        let title = arguments["title"] as? String
        let tipSuffix = arguments["tooltipSuffix"] as? String

        let headers: [String]
        let rows: [[String]]
        do {
            switch format {
            case "json":
                (headers, rows) = try parseJSON(dataRaw)
            case "tsv":
                (headers, rows) = parseDelimited(dataRaw, separator: "\t")
            default:
                (headers, rows) = parseDelimited(dataRaw, separator: ",")
            }
        } catch {
            return ToolEnvelope.failure(
                tool: tool,
                kind: "execution_error",
                message: error.localizedDescription,
                retryable: true
            )
        }

        guard !headers.isEmpty else {
            return ToolEnvelope.failure(
                tool: tool,
                kind: "execution_error",
                message: "Could not parse any columns from the provided data.",
                retryable: true
            )
        }

        var missingColumns: [String] = []
        for col in seriesCols where !headers.contains(col) {
            missingColumns.append(col)
        }
        if let x = xColumn, !headers.contains(x) {
            missingColumns.append(x)
        }
        if !missingColumns.isEmpty {
            return ToolEnvelope.failure(
                tool: tool,
                kind: "invalid_args",
                message:
                    "Column(s) not found: \(missingColumns.joined(separator: ", ")). "
                    + "Available columns: \(headers.joined(separator: ", ")).",
                field: missingColumns.contains(where: { seriesCols.contains($0) }) ? "series" : "xColumn",
                expected: "column name(s) present in the parsed headers",
                retryable: false
            )
        }

        var note: String? = nil
        var dataRows = rows
        if rows.count > maxRows {
            dataRows = downsample(rows, to: maxRows)
            note = "Downsampled from \(rows.count) to \(maxRows) rows for rendering"
        }

        var categories: [String]? = nil
        if let xCol = xColumn, let xIdx = headers.firstIndex(of: xCol) {
            categories = dataRows.map { row in xIdx < row.count ? row[xIdx] : "" }
        }

        var chartSeries: [GrizzyChartSeries] = []
        var skippedColumns: [String] = []

        for col in seriesCols {
            guard let idx = headers.firstIndex(of: col) else { continue }
            let data: [Double?] = dataRows.map { row in
                idx < row.count ? Double(row[idx].trimmingCharacters(in: .whitespaces)) : nil
            }
            if data.allSatisfy({ $0 == nil }) {
                skippedColumns.append(col)
                continue
            }
            chartSeries.append(GrizzyChartSeries(name: col, data: data))
        }

        if !skippedColumns.isEmpty {
            let skipNote = "Column(s) '\(skippedColumns.joined(separator: ", "))' had no numeric data and were skipped"
            note = note.map { $0 + "; " + skipNote } ?? skipNote
        }

        if chartSeries.isEmpty {
            return ToolEnvelope.failure(
                tool: tool,
                kind: "execution_error",
                message: "No numeric series could be extracted from the specified columns.",
                retryable: true
            )
        }

        let spec = GrizzyChartSpec(
            chartType: chartType,
            title: title,
            categories: categories,
            series: chartSeries,
            tooltipSuffix: tipSuffix,
            note: note
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let jsonData = try? encoder.encode(spec),
            let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            return ToolEnvelope.failure(
                tool: tool,
                kind: "execution_error",
                message: "Failed to encode chart specification.",
                retryable: false
            )
        }

        let marker = "---CHART_START---\n\(jsonString)\n---CHART_END---"
        var warnings: [String]? = nil
        if let n = note, !n.isEmpty { warnings = [n] }
        return ToolEnvelope.success(tool: tool, text: marker, warnings: warnings)
    }

    // MARK: - chartType resolution (incl. nested `properties` confusion)

    private static func resolveChartType(from args: [String: Any]) -> String? {
        if let ct = args["chartType"] as? String, !ct.isEmpty {
            return ct
        }
        if let props = args["properties"] as? [String: Any],
            let ct = props["chartType"] as? String, !ct.isEmpty
        {
            return ct
        }
        if let propsStr = args["properties"] as? String,
            let data = propsStr.data(using: .utf8),
            let props = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let ct = props["chartType"] as? String, !ct.isEmpty
        {
            return ct
        }
        return nil
    }

    // MARK: - Parsing

    private static func parseDelimited(_ raw: String, separator: Character) -> ([String], [[String]]) {
        var lines = raw.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return ([], []) }
        let headers = lines.removeFirst()
            .components(separatedBy: String(separator))
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let rows = lines.map {
            $0.components(separatedBy: String(separator))
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return (headers, rows)
    }

    private static func parseJSON(_ raw: String) throws -> ([String], [[String]]) {
        guard let data = raw.data(using: .utf8),
            let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let first = array.first
        else {
            throw NSError(
                domain: "OsaurusRenderChartParity",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "JSON must be an array of objects"]
            )
        }
        let headers = Array(first.keys).sorted()
        let rows: [[String]] = array.map { obj in headers.map { key in "\(obj[key] ?? "")" } }
        return (headers, rows)
    }

    private static func downsample(_ rows: [[String]], to maxCount: Int) -> [[String]] {
        guard rows.count > maxCount else { return rows }
        let step = Double(rows.count) / Double(maxCount)
        return (0 ..< maxCount).map { i in rows[Int(Double(i) * step)] }
    }

    private static func parseStringArrayFromJSON(_ value: Any?) -> [String]? {
        guard let str = value as? String,
            let data = str.data(using: .utf8),
            let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return nil }
        return arr.isEmpty ? nil : arr
    }
}
