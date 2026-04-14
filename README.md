# GrizzyClaw (macOS, Swift)

Native macOS rebuild of GrizzyClaw in Swift. This repo contains the SwiftUI desktop app, shared runtime and agent modules, a headless CLI control plane, and optional Apple silicon MLX-backed local inference support.

The Swift app is a sibling to the legacy Python/PyInstaller build. They share the same user-data layout under `~/.grizzyclaw/`, but this repository ships the native macOS implementation.

## Features

### Main app

- Chat-first main window with sidebar navigation
- Workspace-aware chat sessions
- Dedicated Workspaces window
- Theme-aware SwiftUI shell and status bar
- Finder shortcuts for the shared `~/.grizzyclaw` data directory

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
- Shared-memory channels for swarm-style workspaces
- Workspace-specific provider, model, and autonomy settings
- Chat import and export helpers
- Visual canvas extraction and dedicated canvas window

### Provider and inference support

- OpenAI-compatible providers
- Anthropic support
- Ollama support
- LM Studio support
- LM Studio v1 support
- OpenRouter support
- Cursor and OpenCode Zen provider support in preferences
- Apple silicon MLX local inference support
- Hugging Face-backed MLX model download/cache handling

### Automation and orchestration

- Scheduled task persistence
- Folder watchers stored under `~/.grizzyclaw/watchers/`
- Automation trigger persistence
- Swarm setup presets and readiness helpers
- Sub-agent and swarm activity windows

### MCP and integration surfaces

- MCP server configuration and discovery
- Local MCP process control and autostart
- MCP marketplace catalog support
- Native MCP tool calling and identity resolution
- GUI MCP transcript filtering/preferences

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

## Build the Xcode App

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

## MLX Notes

On Apple silicon, you can use MLX-backed local inference with `llm_provider: mlx`. MLX models are cached under `~/.grizzyclaw/mlx_models/` by default, or you can override the model download root with `mlx_models_directory` in `~/.grizzyclaw/config.yaml` or workspace config.

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
