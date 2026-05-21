# GrizzyClaw (macOS, Swift)

Native macOS rebuild of GrizzyClaw in Swift. This repo contains the SwiftUI desktop app, shared runtime and agent modules, a headless CLI control plane, and optional Apple silicon MLX-backed local inference support.

The Swift app is a sibling to the legacy Python/PyInstaller build. They share the same user-data layout under `~/.grizzyclaw/`, but this repository ships the native macOS implementation.

## Features

### Main app

- Chat-first main window with sidebar navigation (Chat + **Multi-Agent** sub-tabs)
- Workspace-aware chat sessions
- Prompt caching via **Summary Mode** (summarize long chats and continue with a compact summary + recent turns)
- Dedicated Workspaces window
- Theme-aware SwiftUI shell and status bar (includes **Neon**, a colorful cyberpunk palette inspired by [Osaurus](https://github.com/jjang-ai/osaurus) Neon)
- Finder shortcuts for the shared `~/.grizzyclaw` data directory

### Prompt caching (Summary Mode)

The chat composer includes controls to reduce context size for long-running sessions:

- **Summarize chat**: generates a compact summary of the current chat transcript (no tool calls).
- **Use summary**: when enabled, subsequent sends include the summary as a `.system` message plus a small tail window of recent messages (instead of sending the entire chat history).
- **Clear summary**: clears the cached summary and turns off Summary Mode so you can go back to normal chat behavior.

### Dedicated windows and tools

- Workspaces
- Memory
- Scheduled Tasks
- Browser Automation
- Sessions
- Conversation History
- Usage & Performance
- Swarm Activity
- Sub-agents
- Watchers
- Automation Triggers
- Preferences
- Visual Canvas

### Workspace and agent features

- Persistent workspace selection and active workspace tracking
- Workspace templates and built-in template catalog
- Workspace memory stored in SQLite
- **Swarm** leader + specialist workspaces, inter-agent channels, and optional shared memory (see [Swarm and multi-agent](#swarm-and-multi-agent))
- **Sub-agents** — background `SPAWN_SUBAGENT` runs with depth/timeout limits per workspace
- Workspace-specific provider, model, and autonomy settings
- Global ClawHub skill defaults in `config.yaml` with per-workspace/per-agent `enabled_skills` overrides
- Specialist templates can ship their own skill sets (for example research or personal agents)
- Chat import and export helpers
- Visual canvas extraction and dedicated canvas window

### Provider and inference support

- OpenAI-compatible providers
- Anthropic support
- Ollama support
- LM Studio support (OpenAI-compat and native v1)
- **[oMLX](https://github.com/jundot/omlx)** — OpenAI-compatible MLX server (`omlx_url`, default `http://localhost:8000/v1`)
- **[vMLX](https://github.com/jjang-ai/vmlx)** — OpenAI-compatible MLX server (`vmlx_url`, default `http://localhost:8000/v1`; model id often `local`)
- OpenRouter, Cursor, and OpenCode Zen provider support in preferences
- Apple silicon **bundled MLX** inference (`llm_provider: mlx`) with Hugging Face model download/cache under `~/.grizzyclaw/mlx_models/`
- Workspace **Refresh model list** probes the configured provider (including oMLX/vMLX on the LAN)

### Automation and orchestration

- Scheduled task persistence
- Folder watchers stored under `~/.grizzyclaw/watchers/`
- Automation trigger persistence
- Swarm setup wizard, readiness checks, **Swarm activity** log, and **Sub-agents** monitor (daemon gateway; see [Swarm and multi-agent](#swarm-and-multi-agent))

### MCP and integration surfaces

- MCP server configuration and discovery (including Bonjour browse in Preferences)
- Local MCP process control and autostart
- MCP marketplace catalog support
- Native MCP tool calling and identity resolution
- GUI MCP transcript filtering/preferences
- Bundled **Osaurus** plugin manifests and built-in skills (registry parity; native time/reminders tools where supported)
- In-process **`grizzyclaw_air`** tool catalog in the workspace **Tools** tab (Air parity for workspace chat)

### Diagnostics and control plane

- `doctor` runtime report
- Loopback HTTP control plane
- `GET /health`
- `GET /doctor`
- Launch diagnostics logging

## Project Structure

| Path | Role |
|---|---|
| `Package.swift` | SwiftPM manifest for the GUI app, CLI, shared libraries, and tests |
| `Sources/GrizzyClawCore/` | Paths, config loading, workspace persistence, MCP runtime, local HTTP control plane, memory DB access, watcher/task/trigger persistence |
| `Sources/GrizzyClawAgent/` | Chat pipeline, prompt augmentation, transcript filtering, tool-call parsing/validation, provider stream clients |
| `Sources/GrizzyClawMLX/` | MLX stream client, MLX model cache, Hugging Face model integration |
| `Sources/GrizzyClawUI/` | SwiftUI app shell, chat UI, workspaces UI, browser/memory/scheduler windows, preferences, watchers, usage dashboard, visual canvas |
| `Sources/RunGrizzy/` | SwiftPM GUI entrypoint for `swift run GrizzyClaw` |
| `Sources/GrizzyClawCLI/` | Headless CLI for diagnostics and the localhost control plane |
| `App/MacHost/` | Thin Xcode app host entrypoint |
| `Tests/GrizzyClawCoreTests/` | Core/runtime test target |
| `Tests/GrizzyClawAgentTests/` | Agent and prompt/tooling test target |
| `docs/` | Xcode/SPM notes, migration roadmap, parity checklist, coexistence notes, next tasks |

## Requirements

- macOS 14+
- Xcode 15+ recommended
- Swift toolchain compatible with `swift-tools-version: 6.1`

## Build and Run

### SwiftPM GUI app

```bash
cd GrizzyClaw-mac
swift build
swift run GrizzyClaw
```

`swift run GrizzyClaw` launches the SwiftUI app using `Sources/RunGrizzy/RunGrizzyEntry.swift`.

### Tests

```bash
swift test
```

Current test targets include:

- `GrizzyClawCoreTests`
- `GrizzyClawAgentTests`

## CLI Diagnostics and Control Plane

GrizzyClaw includes a small loopback HTTP control plane and a `doctor` report for runtime inspection.

### Print health JSON

```bash
swift run GrizzyClawCLI doctor
swift run GrizzyClawCLI doctor --pretty
```

### Serve localhost control endpoints

```bash
swift run GrizzyClawCLI serve
swift run GrizzyClawCLI serve --port 18765 --bind 127.0.0.1
```

Endpoints:

- `GET /health`
- `GET /doctor`

Press `Enter` to stop the server.

## Swarm and multi-agent

GrizzyClaw supports coordinating multiple agents: a **Leader** that delegates work to **specialists**, optional **consensus** synthesis, **shared memory** on a channel, and **sub-agents** for parallel background runs. Configuration lives in `workspaces.json` per workspace; the macOS app provides setup, editing, and monitoring UIs aligned with the Python desktop app.

### Concepts

| Piece | What it does |
|-------|----------------|
| **Leader** | Primary workspace on a swarm channel. Can `@mention` specialists (e.g. `@code_assistant`, `@research_assistant`) to hand off subtasks. |
| **Specialists** | Focused workspaces (planning, coding, lint, test, research, personal, etc.) on the same **inter-agent channel**. |
| **Inter-agent channel** | Named lane (default `default`). Only workspaces with inter-agent enabled and the same channel can message each other. |
| **Shared memory** | When enabled, workspaces on the same channel share a memory database for swarm context. |
| **Auto-delegate** | Leader policy: `@slug` lines in the leader’s reply are executed automatically. |
| **Consensus** | After specialists respond, the leader is called again to merge replies into one answer. |
| **Sub-agents** | Tool-driven background runs (`SPAWN_SUBAGENT`) for parallel or nested work—not the same as @mention swarm delegation, but configurable on the same **Swarm** workspace tab. |

Delegation uses workspace slugs derived from display names (e.g. **Planning Assistant** → `@planning_assistant`). Specialist system prompts come from bundled `swarm_workspace_templates.json` (parity with Python `WORKSPACE_TEMPLATES`).

### Swarm setup (Preferences → Swarm Setup)

One-shot wizard to create or update Leader + specialist workspaces:

- **Presets:** Software factory, Personal assistant, Hybrid (each with its own specialist checklist; Leader is always included).
- **Specialists (examples):** Planning, Code, Linting Pro, Testing Pro, Research, Personal — toggled per preset.
- **Inter-agent channel** — shared channel name for the whole swarm.
- **Apply / update system prompts** — optional refresh of `system_prompt` from templates when applying.
- **Leader policy:** auto-delegate on `@mentions`, consensus synthesis.
- **Readiness** — whether a Leader exists on the channel and how many specialists are configured.
- **Copy test prompt** — sample delegation lines for smoke-testing the roster.

Use **Apply setup** to write workspaces into `~/.grizzyclaw/workspaces.json`.

### Per-workspace swarm settings (Workspaces → Edit → Swarm)

Fine-grained control for any agent:

- **Inter-agent messaging** — allow `@workspace` / `@slug` delegation to and from other agents.
- **Inter-agent channel** — must match peers (empty = `default`).
- **Shared memory** — share memory DB with other agents on the same channel.
- **Leader: auto-delegate** — run `@mentions` from leader replies automatically.
- **Leader: consensus** — synthesize specialist replies into one leader answer.
- **Sub-agents** — enable `SPAWN_SUBAGENT`, max spawn depth (1–5), max children per parent (1–20), default run timeout (seconds or no timeout).

New workspaces from the default template can start with inter-agent and leader-oriented prompts enabled; specialists are assigned roles such as `leader`, `specialist_planning`, `specialist_coding`, etc.

### Monitoring and control

| Window | Menu / sidebar | Purpose |
|--------|----------------|---------|
| **Swarm activity** | View → Swarm activity… / sidebar | Recent swarm events (delegations, claims, consensus). Refreshes from the **daemon gateway**. |
| **Sub-agents** | View → Sub-agents… / sidebar | Active and completed `SPAWN_SUBAGENT` runs across workspaces; **Kill selected**; auto-refresh every 2s while open. |

Both windows need the GrizzyClaw **daemon** reachable (Unix socket `~/.grizzyclaw/daemon.sock`). If the gateway requires auth, set **Gateway Auth Token** under **Preferences → Integrations** (`gateway_auth_token` in `config.yaml`).

Manage the daemon from **Preferences → Daemon** (status, start/stop).

### Main window chat vs orchestration

The main chat pane has two sub-tabs:

- **Chat** — streaming conversation with the active workspace’s LLM (tools, MCP, Summary Mode, etc.).
- **Multi-Agent** — informational placeholder in the native Swift UI; full delegate/specialist/swarm orchestration is driven by the **daemon** and leader workspace behavior (same data model as the Python app), not a separate in-pane multi-agent stream.

Use **Swarm Setup** plus a Leader workspace on your channel for real multi-agent workflows; use **Swarm activity** and **Sub-agents** to observe runs.

## Build the Xcode App

The GrizzyClaw Mac app icon lives in `App/MacHost/Assets.xcassets` (`AppIcon` set, sourced from the bundled claw artwork).

1. Open `GrizzyClawMac.xcodeproj`
2. Select the `GrizzyClawMac` scheme
3. Run with `Cmd+R`

Command-line build:

```bash
cd GrizzyClaw-mac
xcodebuild -project GrizzyClawMac.xcodeproj -scheme GrizzyClawMac -configuration Debug build
```

For more Xcode-specific details, see `docs/xcode-app-target.md`.

## Runtime Data Layout

The app uses the shared GrizzyClaw data root:

- `~/.grizzyclaw/config.yaml`
- `~/.grizzyclaw/workspaces.json`
- `~/.grizzyclaw/sessions/`
- `~/.grizzyclaw/workspace_templates.json`
- `~/.grizzyclaw/skill_marketplace.json`
- `~/.grizzyclaw/skills.json`
- `~/.grizzyclaw/watchers/`
- `~/.grizzyclaw/scheduled_tasks.json`
- `~/.grizzyclaw/triggers.json`
- `~/.grizzyclaw/daemon.sock`
- `~/.grizzyclaw/daemon_stderr.log`
- `~/.grizzyclaw/mlx_models/`
- Per-workspace `swarm_role`, `inter_agent_channel`, `use_shared_memory`, and sub-agent limits in `workspaces.json` (see [Swarm and multi-agent](#swarm-and-multi-agent))

`config.yaml` now acts as the source of truth for global/default ClawHub skills. A workspace only writes `enabled_skills` in `workspaces.json` when that agent should override the global defaults.

## Preferences Surface

The Preferences window currently includes these sections:

- General
- LLM Providers
- Telegram
- WhatsApp
- Appearance
- Daemon
- Prompts_Rules
- ClawHub
- MCP Servers
- Swarm Setup
- Security
- Integrations

The ClawHub preferences pane manages global/default `enabled_skills`. The workspace editor Skills tab can inherit those defaults or save an explicit override for a specific workspace/agent.

**Swarm Setup** configures Leader + specialist rosters and channels. **Integrations** includes an optional **Gateway Auth Token** for swarm/sub-agent gateway APIs when the daemon requires it.

## MLX Notes

On Apple silicon, you can use MLX-backed local inference with `llm_provider: mlx`. MLX models are cached under `~/.grizzyclaw/mlx_models/` by default, or you can override the model download root with `mlx_models_directory` in `~/.grizzyclaw/config.yaml` or workspace config.

### oMLX and vMLX (OpenAI-compatible HTTP)

Both providers speak the OpenAI `/v1` API. Configure them under **Preferences → LLM Providers** or per-workspace in the editor (**LLM** and **Custom provider URLs**).

| Key | Purpose |
|-----|---------|
| `omlx_url` / `vmlx_url` | Base URL including `/v1` (default `http://localhost:8000/v1`) |
| `omlx_model` / `vmlx_model` | Model id returned by the server’s `GET /v1/models` |
| `omlx_api_key` / `vmlx_api_key` | Optional Bearer token when the server requires auth |

**This Mac:** use `http://localhost:8000/v1` (or another port if you changed it).

**Another Mac on your network:** set the URL to `http://<lan-ip>:<port>/v1`. The remote server must listen on all interfaces, not only localhost — for example:

```bash
# vMLX on the machine that runs inference
vmlx serve --host 0.0.0.0 --port 8000
```

Use a different port for vMLX if oMLX already uses 8000 (e.g. `vmlx serve --port 8001`). GrizzyClaw normalizes schemeless hosts as `http://` and uses the local-network session for model discovery and chat.

macOS may prompt for **Local Network** access the first time you reach a LAN server; the app’s Info.plist includes `NSLocalNetworkUsageDescription` for LLM and MCP traffic.

## Documentation

- `docs/parity-checklist.md`
- `docs/xcode-app-target.md`
- `docs/swift-migration-roadmap.md`
- `docs/python-swift-coexistence.md`
- `docs/next-tasks.md`

## Relationship to the Python App

- This repo is the native Swift/macOS implementation.
- The Python app remains separate.
- Both use the same `~/.grizzyclaw/` data layout for compatibility.
- Bundle ID for the Xcode target is currently `com.grizzyclaw.macos`; change it before store distribution or notarization.
