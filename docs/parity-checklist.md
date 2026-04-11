# GrizzyClaw macOS (Swift) — parity with Python app

This checklist tracks feature parity between the **legacy Python / PyQt** app (`../GrizzyClaw`) and the **native Swift** app in this repository. Update statuses as you implement: `[ ]` not started · `[~]` partial · `[x]` done.

## Shell & platform

- [~] macOS 13+ app bundle (`.app`), menu bar, window lifecycle, quit handling — Xcode project + **GrizzyClaw** menu command “Open ~/.grizzyclaw in Finder” (⌘⇧J)
- [ ] Single-instance behavior (optional; match Python if applicable)
- [ ] Dock / tray icon and “hide to tray” (if product requires it)
- [x] Config path parity: `GrizzyClawPaths` mirrors `~/.grizzyclaw/` (`config.yaml`, `workspaces.json`, `watchers/`); YAML/JSON **reading** not implemented yet
- [ ] Dark / light appearance (match themes or system)

## Workspaces

- [ ] Multiple named workspaces; active workspace selection
- [ ] Baseline workspace + “return to baseline” shortcut (`Ctrl+Shift+B` equivalent)
- [ ] Workspace dialog: create, edit, delete, templates (if any)
- [ ] Per-workspace agent creation / LLM routing (match `WorkspaceManager` behavior)
- [ ] Sidebar or equivalent: quick switch between workspaces

## Chat & agent

- [ ] Main chat UI: send, stream responses, stop/cancel if supported
- [ ] Session persistence / restore (align with GUI session model)
- [ ] New chat, export conversation
- [ ] Slash commands or command palette (if exposed in Python GUI)
- [ ] Tools / MCP / execution toggles (match safety model)
- [ ] Visual canvas: screenshots, A2UI, attachments (parity with `CanvasWidget` features you care about)
- [ ] Swarm / multi-agent / sub-agents UI (if in scope)

## Folder Watchers (automation)

- [ ] List/create/edit/delete watcher definitions
- [ ] Storage compatibility with `~/.grizzyclaw/watchers/` JSON (or migration tool)
- [ ] Debounce, globs, fingerprint / convergence behavior (or delegate to a small local service)
- [ ] Enable/disable per workspace (`enable_folder_watchers` equivalent)
- [ ] Manual “run once” and reload after edits

## Other dialogs & features (from Python main window)

- [ ] Memory browser
- [ ] Scheduler
- [ ] Built-in browser dialog
- [ ] Sessions
- [ ] Usage dashboard
- [ ] Swarm activity
- [ ] Sub-agents
- [ ] Conversation history
- [ ] Settings / preferences (`Ctrl+,` equivalent)
- [ ] Telegram integration (if required for parity)

## LLM & integrations

- [ ] OpenAI-compatible, Ollama, LM Studio, Anthropic, OpenRouter, etc. (match `llm/` providers in use)
- [ ] Secure credential storage (Keychain on macOS)
- [ ] MCP client / tool discovery (if required)

## Non-goals (explicit)

Document here anything the Swift app will **not** ship in v1 (e.g. embedded local Whisper, PyInstaller-only paths).

---

**Source of truth for behavior:** `../GrizzyClaw/grizzyclaw/` (especially `gui/main_window.py`, `agent/core.py`, `workspaces/`, `automation/`).
