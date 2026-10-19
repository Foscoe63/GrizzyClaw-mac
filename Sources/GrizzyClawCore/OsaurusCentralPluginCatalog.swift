import Foundation

/// Metadata for plugins published in the [osaurus-tools](https://github.com/osaurus-ai/osaurus-tools) central registry.
/// GrizzyClaw-Air does not load Osaurus `.dylib` plugins; this catalog documents parity and surfaces tool names for UX.
public struct OsaurusCentralPluginInfo: Identifiable, Equatable, Sendable {
    public var id: String { pluginId }

    /// Registry id, e.g. `osaurus.notes`
    public let pluginId: String
    public let displayName: String
    public let summary: String
    public let homepageURL: URL?
    public let specJSONURL: URL
    /// Shown first — matches the fourteen “Apple / automation / search / time / vision / fetch” style integrations users see grouped in Osaurus.
    public let isPrimaryOsaurusStyle: Bool
    /// Representative tool names from `capabilities.tools` in the registry (best-effort; not exhaustive).
    public let exampleToolNames: [String]
    /// How to approximate this capability in GrizzyClaw-Air.
    public let grizzyParityNote: String

    public init(
        pluginId: String,
        displayName: String,
        summary: String,
        homepageURL: URL?,
        specJSONURL: URL,
        isPrimaryOsaurusStyle: Bool,
        exampleToolNames: [String],
        grizzyParityNote: String
    ) {
        self.pluginId = pluginId
        self.displayName = displayName
        self.summary = summary
        self.homepageURL = homepageURL
        self.specJSONURL = specJSONURL
        self.isPrimaryOsaurusStyle = isPrimaryOsaurusStyle
        self.exampleToolNames = exampleToolNames
        self.grizzyParityNote = grizzyParityNote
    }
}

public enum OsaurusCentralPluginCatalog {
    public static let registryBrowseURL = URL(string: "https://github.com/osaurus-ai/osaurus-tools/tree/master/plugins")!

    private static func spec(_ file: String) -> URL {
        URL(string: "https://raw.githubusercontent.com/osaurus-ai/osaurus-tools/master/plugins/\(file)")!
    }

    /// All plugins currently listed under `plugins/` in osaurus-tools (order: primary bundle first, then alphabetical among the rest).
    public static let allPlugins: [OsaurusCentralPluginInfo] = primaryBundle + extensions

    public static var primaryOsaurusStylePlugins: [OsaurusCentralPluginInfo] {
        allPlugins.filter(\.isPrimaryOsaurusStyle)
    }

    /// Fourteen integrations that align with the Osaurus “built-in style” tool families (Notes, Browser, Calendar, …).
    private static let primaryBundle: [OsaurusCentralPluginInfo] = [
        .init(
            pluginId: "osaurus.notes",
            displayName: "Apple Notes",
            summary: "List, search, and create Notes.app content.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-notes"),
            specJSONURL: spec("osaurus.notes.json"),
            isPrimaryOsaurusStyle: true,
            exampleToolNames: ["search_notes", "create_note", "list_notes"],
            grizzyParityNote:
                "Add an MCP server that exposes Notes automation (e.g. macOS-use style `notes_*` tools). Native Osaurus plugin binaries are not loaded in GrizzyClaw-Air."
        ),
        .init(
            pluginId: "osaurus.browser",
            displayName: "Browser",
            summary: "Drive and inspect a web browser from the agent.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-browser"),
            specJSONURL: spec("osaurus.browser.json"),
            isPrimaryOsaurusStyle: true,
            exampleToolNames: ["browser_navigate", "browser_snapshot", "browser_click"],
            grizzyParityNote:
                "Use a Playwright/Puppeteer MCP server or a remote browser MCP in `grizzyclaw.json`. Osaurus’s native browser plugin is not embedded here."
        ),
        .init(
            pluginId: "osaurus.calendar",
            displayName: "Calendar",
            summary: "Read and manage Calendar.app events.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-calendar"),
            specJSONURL: spec("osaurus.calendar.json"),
            isPrimaryOsaurusStyle: true,
            exampleToolNames: ["calendar_list_calendars", "calendar_create_event", "calendar_find_events"],
            grizzyParityNote:
                "Configure an MCP server with Calendar tools (macuse-style `calendar_*`). Grizzy’s chat stack already prefers MCP for calendar hints when available."
        ),
        .init(
            pluginId: "osaurus.contacts",
            displayName: "Contacts",
            summary: "Search and read Contacts.app records.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-contacts"),
            specJSONURL: spec("osaurus.contacts.json"),
            isPrimaryOsaurusStyle: true,
            exampleToolNames: ["contacts_search", "contacts_get"],
            grizzyParityNote:
                "Expose Contacts via an MCP server (e.g. `contacts_search` from macOS automation MCPs). No native Contacts dylib in Grizzy."
        ),
        .init(
            pluginId: "osaurus.maps",
            displayName: "Maps",
            summary: "Search places and directions via Maps.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-maps"),
            specJSONURL: spec("osaurus.maps.json"),
            isPrimaryOsaurusStyle: true,
            exampleToolNames: ["map_search_places", "map_geocode"],
            grizzyParityNote:
                "Use MCP map search tools or HTTP geocoding APIs. Same pattern as Osaurus: agent calls structured tools, not MapKit directly from Grizzy."
        ),
        .init(
            pluginId: "osaurus.messages",
            displayName: "Messages",
            summary: "Send and search Messages.app threads.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-messages"),
            specJSONURL: spec("osaurus.messages.json"),
            isPrimaryOsaurusStyle: true,
            exampleToolNames: ["messages_send_message", "messages_search"],
            grizzyParityNote:
                "Wire `messages_*` MCP tools on Mac only (privacy-sensitive). iPad builds cannot run local stdio MCP that drives Messages."
        ),
        .init(
            pluginId: "osaurus.images",
            displayName: "Osaurus Images",
            summary: "Generate and transform images for the agent.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-images"),
            specJSONURL: spec("osaurus.images.json"),
            isPrimaryOsaurusStyle: true,
            exampleToolNames: ["images_generate", "images_edit"],
            grizzyParityNote:
                "Use GrizzyClaw MLX / HF image pipelines or an image MCP (fal, OpenAI images). Osaurus’s native image plugin is not bundled."
        ),
        .init(
            pluginId: "osaurus.mail",
            displayName: "Osaurus Mail",
            summary: "Apple Mail integration — read, archive, compose.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-mail"),
            specJSONURL: spec("osaurus.mail.json"),
            isPrimaryOsaurusStyle: true,
            exampleToolNames: ["mail_search", "mail_compose_message", "mail_move_message"],
            grizzyParityNote:
                "Parity via MCP `mail_*` tools (macuse documents these). Requires Mac + Mail.app permissions outside the sandbox."
        ),
        .init(
            pluginId: "osaurus.vision",
            displayName: "Osaurus Vision",
            summary: "Screen and image understanding for the agent.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-vision"),
            specJSONURL: spec("osaurus.vision.json"),
            isPrimaryOsaurusStyle: true,
            exampleToolNames: ["vision_analyze_image", "vision_capture_screen"],
            grizzyParityNote:
                "Use MLX vision-capable models in Grizzy or an MCP vision server. Full screen-capture parity matches Osaurus host permissions only on Mac."
        ),
        .init(
            pluginId: "osaurus.reminders",
            displayName: "Reminders",
            summary: "List and create Reminders.app items.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-reminders"),
            specJSONURL: spec("osaurus.reminders.json"),
            isPrimaryOsaurusStyle: true,
            exampleToolNames: ["reminders_list", "reminders_add"],
            grizzyParityNote:
                "MCP `reminders_*` or Grizzy’s `create_scheduled_task` for time-based automation; Reminders.app MCP is Mac-only."
        ),
        .init(
            pluginId: "osaurus.search",
            displayName: "Search",
            summary: "Web and local search helpers for agents.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-search"),
            specJSONURL: spec("osaurus.search.json"),
            isPrimaryOsaurusStyle: true,
            exampleToolNames: ["search_web", "search_codebase"],
            grizzyParityNote:
                "Add DuckDuckGo / Tavily / Exa MCP, or rely on model web browsing where enabled. Osaurus search plugin bundles multiple backends."
        ),
        .init(
            pluginId: "osaurus.time",
            displayName: "Time",
            summary: "Time zones, alarms, timers, scheduling helpers.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-time"),
            specJSONURL: spec("osaurus.time.json"),
            isPrimaryOsaurusStyle: true,
            exampleToolNames: ["time_now", "time_convert_zone"],
            grizzyParityNote:
                "Mostly replaceable with model reasoning; for strict clock APIs add a tiny MCP or use Grizzy scheduler for recurring jobs."
        ),
        .init(
            pluginId: "osaurus.macos-use",
            displayName: "macOS Use",
            summary: "Broad macOS automation surface (Calendar, Mail, Notes, …) in one plugin family.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-macos-use"),
            specJSONURL: spec("osaurus.macos-use.json"),
            isPrimaryOsaurusStyle: true,
            exampleToolNames: ["calendar_create_event", "notes_create_note", "shortcuts_run"],
            grizzyParityNote:
                "macOS only: run a local stdio MCP such as macuse in grizzyclaw.json on a Mac (there is no Macuse for iPad). On iPad, use an HTTP MCP bridge or other remote tools instead."
        ),
        .init(
            pluginId: "osaurus.fetch",
            displayName: "Fetch",
            summary: "HTTP fetch with structured extraction for agents.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-fetch"),
            specJSONURL: spec("osaurus.fetch.json"),
            isPrimaryOsaurusStyle: true,
            exampleToolNames: ["fetch_url", "fetch_extract"],
            grizzyParityNote:
                "Use `mcp_web_fetch`-style tools or any HTTP MCP; Grizzy agent loop can call MCP tools the same way as Osaurus MCP providers."
        ),
    ]

    private static let extensions: [OsaurusCentralPluginInfo] = [
        .init(
            pluginId: "osaurus.emacs",
            displayName: "Emacs",
            summary: "Remote control Emacs via RPC.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-emacs"),
            specJSONURL: spec("osaurus.emacs.json"),
            isPrimaryOsaurusStyle: false,
            exampleToolNames: ["emacs_eval", "emacs_open_file"],
            grizzyParityNote:
                "Replace with folder-scoped `run_terminal_cmd` / custom MCP if you use Emacs server; niche vs the fourteen core integrations."
        ),
        .init(
            pluginId: "osaurus.music",
            displayName: "Music",
            summary: "Control Apple Music playback and queues.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-music"),
            specJSONURL: spec("osaurus.music.json"),
            isPrimaryOsaurusStyle: false,
            exampleToolNames: ["music_play", "music_search"],
            grizzyParityNote:
                "No first-class Music MCP in Grizzy; use Shortcuts MCP, AppleScript via sandbox (Osaurus), or omit on iPad."
        ),
        .init(
            pluginId: "osaurus.pptx",
            displayName: "PowerPoint",
            summary: "Create and edit `.pptx` decks programmatically.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-pptx"),
            specJSONURL: spec("osaurus.pptx.json"),
            isPrimaryOsaurusStyle: false,
            exampleToolNames: ["pptx_create", "pptx_add_slide"],
            grizzyParityNote:
                "Use document-generation MCPs or Python in a sandbox; Osaurus PPTX plugin is not ported as a dylib."
        ),
        .init(
            pluginId: "osaurus.resend",
            displayName: "Resend",
            summary: "Transactional email via Resend API.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-resend"),
            specJSONURL: spec("osaurus.resend.json"),
            isPrimaryOsaurusStyle: false,
            exampleToolNames: ["resend_send_email"],
            grizzyParityNote:
                "Add an HTTP MCP wrapper around Resend’s REST API or call from your own backend; same security model as any API key MCP."
        ),
        .init(
            pluginId: "osaurus.telegram",
            displayName: "Telegram",
            summary: "Telegram Bot API helpers.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-telegram"),
            specJSONURL: spec("osaurus.telegram.json"),
            isPrimaryOsaurusStyle: false,
            exampleToolNames: ["telegram_send_message", "telegram_get_updates"],
            grizzyParityNote:
                "GrizzyClaw-Air already has Telegram settings and Python parity paths; prefer native Grizzy Telegram integration over the Osaurus dylib plugin."
        ),
        .init(
            pluginId: "osaurus.xlsx",
            displayName: "Excel",
            summary: "Read/write `.xlsx` spreadsheets.",
            homepageURL: URL(string: "https://github.com/osaurus-ai/osaurus-xlsx"),
            specJSONURL: spec("osaurus.xlsx.json"),
            isPrimaryOsaurusStyle: false,
            exampleToolNames: ["xlsx_read_sheet", "xlsx_write_cell"],
            grizzyParityNote:
                "Use a small Python MCP with openpyxl/pandas, or CLI-Anything skills; no bundled XLSX engine in Grizzy native agent."
        ),
    ]
}
