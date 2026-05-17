import Foundation

/// OpenAI-style tool schemas for Osaurus `ToolRegistry` built-ins, exposed on the synthetic `grizzyclaw` MCP server.
public enum OsaurusParityToolDescriptors {
    public static let tools: [MCPToolsDiscoveryResult.InternalTool] = [
        .init(
            server: "grizzyclaw",
            name: "todo",
            description:
                "Write or replace the current task checklist (markdown with `- [ ]` / `- [x]` items). Use for multi-step tasks.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "markdown": .object([
                        "type": .string("string"),
                        "description": .string("Full markdown checklist; each line starts with `- [ ]` or `- [x]`."),
                    ]),
                ]),
                "required": .array([.string("markdown")]),
            ])
        ),
        .init(
            server: "grizzyclaw",
            name: "complete",
            description:
                "End the current task with a one-paragraph summary. Include WHAT you did and HOW you verified it (command, file, URL). Vague one-word summaries are rejected.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "summary": .object([
                        "type": .string("string"),
                        "description": .string(
                            "What you did + how you verified, in one paragraph (minimum ~30 meaningful characters). Not a placeholder like \"done\"."
                        ),
                    ]),
                ]),
                "required": .array([.string("summary")]),
            ])
        ),
        .init(
            server: "grizzyclaw",
            name: "clarify",
            description:
                "Pause and ask the user a blocking question when guessing would likely be wrong. For finite choices (≤6 short labels), pass `options` so the user can tap an answer.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "question": .object([
                        "type": .string("string"),
                        "description": .string("Specific, concrete question (avoid vague \"what would you like?\")."),
                    ]),
                    "options": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Optional ≤6 choices, each ≤80 chars; shown in the transcript."),
                    ]),
                    "allowMultiple": .object([
                        "type": .string("boolean"),
                        "description": .string("When true with `options`, user may pick more than one. Default false."),
                    ]),
                ]),
                "required": .array([.string("question")]),
            ])
        ),
        .init(
            server: "grizzyclaw",
            name: "share_artifact",
            description:
                "Surface a deliverable to the user. In GrizzyClaw-Air, inline content is echoed back; file paths are not rendered as cards yet.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "path": .object(["type": .string("string")]),
                    "content": .object(["type": .string("string")]),
                    "filename": .object(["type": .string("string")]),
                    "description": .object(["type": .string("string")]),
                ]),
                "required": .array([]),
            ])
        ),
        .init(
            server: "grizzyclaw",
            name: "render_chart",
            description:
                "Build chart data from tabular input (CSV/TSV/JSON array of objects). Returns the same ---CHART_START--- JSON block as Osaurus for UI layers that parse it; otherwise the model can read the spec from the transcript.",
            inputSchema: .object([
                "type": .string("object"),
                "required": .array([.string("data"), .string("chartType"), .string("series")]),
                "properties": .object([
                    "data": .object([
                        "type": .string("string"),
                        "description": .string("Raw file content (CSV, TSV, or JSON array of objects)."),
                    ]),
                    "format": .object([
                        "type": .string("string"),
                        "description": .string("File format: csv, tsv, or json."),
                        "enum": .array([.string("csv"), .string("tsv"), .string("json")]),
                    ]),
                    "chartType": .object([
                        "type": .string("string"),
                        "description": .string("Chart type (strict enum)."),
                        "enum": .array([
                            .string("column"), .string("bar"), .string("line"), .string("spline"),
                            .string("area"), .string("areaspline"), .string("pie"), .string("scatter"),
                            .string("bubble"), .string("gauge"), .string("waterfall"), .string("boxplot"),
                        ]),
                    ]),
                    "xColumn": .object([
                        "type": .string("string"),
                        "description": .string("Column name for x-axis labels / categories."),
                    ]),
                    "series": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Column names to plot as numeric series."),
                    ]),
                    "title": .object([
                        "type": .string("string"),
                        "description": .string("Chart title."),
                    ]),
                    "tooltipSuffix": .object([
                        "type": .string("string"),
                        "description": .string("Unit suffix for tooltips (e.g. USD, %, ms)."),
                    ]),
                ]),
            ])
        ),
        .init(
            server: "grizzyclaw",
            name: "methods_save",
            description:
                "Create a reusable method (procedure) from text. Persists to local JSON in the Grizzy user data directory.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "name": .object(["type": .string("string")]),
                    "description": .object(["type": .string("string")]),
                    "trigger_text": .object(["type": .string("string")]),
                    "body": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("name"), .string("description"), .string("body")]),
            ])
        ),
        .init(
            server: "grizzyclaw",
            name: "methods_report",
            description: "Report whether a saved method helped (loaded/succeeded/failed).",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "method_id": .object(["type": .string("string")]),
                    "outcome": .object([
                        "type": .string("string"),
                        "enum": .array([.string("loaded"), .string("succeeded"), .string("failed")]),
                    ]),
                    "notes": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("method_id"), .string("outcome")]),
            ])
        ),
        .init(
            server: "grizzyclaw",
            name: "memory_search_working",
            description: "Search locally pinned working-memory facts (JSON store under ~/.grizzyclaw/osaurus_parity/).",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "query": .object(["type": .string("string")]),
                    "top_k": .object(["type": .string("integer")]),
                ]),
                "required": .array([.string("query")]),
            ])
        ),
        .init(
            server: "grizzyclaw",
            name: "memory_search_conversations",
            description: "Search saved chat transcripts (assistant/user turns) for the current machine.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "query": .object(["type": .string("string")]),
                    "top_k": .object(["type": .string("integer")]),
                ]),
                "required": .array([.string("query")]),
            ])
        ),
        .init(
            server: "grizzyclaw",
            name: "memory_search_summaries",
            description: "Search assistant turns in transcripts as a lightweight stand-in for episodic summaries.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "query": .object(["type": .string("string")]),
                    "top_k": .object(["type": .string("integer")]),
                ]),
                "required": .array([.string("query")]),
            ])
        ),
        .init(
            server: "grizzyclaw",
            name: "memory_search_graph",
            description: "Graph memory search (stub): returns an empty adjacency list until a graph store exists.",
            inputSchema: .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "query": .object(["type": .string("string")]),
                    "top_k": .object(["type": .string("integer")]),
                ]),
                "required": .array([.string("query")]),
            ])
        ),
        .init(
            server: "grizzyclaw",
            name: "spawn_subagent",
            description:
                "Run a sub-agent and wait (Osaurus swarm). Not implemented in GrizzyClaw-Air; returns a structured not_supported message.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "prompt": .object(["type": .string("string")]),
                    "title": .object(["type": .string("string")]),
                    "mode": .object([
                        "type": .string("string"),
                        "enum": .array([.string("chat"), .string("work")]),
                    ]),
                ]),
                "required": .array([.string("prompt")]),
            ])
        ),
    ]
}
