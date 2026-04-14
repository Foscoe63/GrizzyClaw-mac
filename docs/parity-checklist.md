# GrizzyClaw macOS (Swift) — parity with Python app

This checklist tracks feature parity between the **legacy Python / PyQt** app (`../GrizzyClaw`) and the **native Swift** app in this repository. Update statuses as you implement: `[ ]` not started · `[~]` partial · `[x]` done.

## Shell & platform

- [~] macOS 13+ app bundle (`.app`), menu bar, window lifecycle, quit handling — Xcode project + **GrizzyClaw** menu command “Open ~/.grizzyclaw in Finder” (⌘⇧J)
- [x] Single-instance lock (`~/.grizzyclaw/grizzyclaw-mac.lock` via `flock`)
- [ ] Dock / tray icon and “hide to tray” (if product requires it)
- [~] Config path parity: `GrizzyClawPaths` mirrors `~/.grizzyclaw/`; **`config.yaml` read** (subset via `UserConfigLoader` / Config tab); **`watchers/`** CRUD in **Watchers** tab (`FolderWatcherRecord` / `WatchersPersistence`)
- [~] Dark / light appearance (`theme` → `preferredColorScheme` where Light/Dark)

## Workspaces

- [~] Multiple named workspaces; load from `workspaces.json`; **sidebar selection persists `active_workspace_id`**. **Swift: New / Edit / Delete** workspaces (full JSON save via `WorkspaceIndexLoader.save`), plus **structured LLM fields** (llm_provider, llm_model, ollama_url) in Edit sheet
- [ ] Baseline workspace + “return to baseline” shortcut (`Ctrl+Shift+B` equivalent)
- [ ] Workspace dialog: create, edit, delete, templates (if any)
- [ ] Per-workspace agent creation / LLM routing (match `WorkspaceManager` behavior)
- [~] Sidebar or equivalent: **NavigationSplitView** lists workspaces with Active / Baseline badges; reload toolbar button

## Chat & agent

- [~] Main chat UI: **`ChatPane`** + **`ChatSessionModel`**; **OpenAI-compatible SSE** (`OpenAICompatibleStreamClient`) with **`ChatParameterResolver`** + **`SessionTrim`** + **`RoutingExtras`** from `config.yaml`
- [~] Stream responses; **Stop** cancels the streaming `Task` (best-effort)
- [~] **Session persistence**: `~/.grizzyclaw/sessions/{workspaceId}_gui_user.json` (Python-compatible list JSON); honor **`session_persistence`** from config; restore on workspace switch; **Clear chat** removes file
- [ ] New chat, export conversation
- [ ] Slash commands or command palette (if exposed in Python GUI)
- [~] Tools / MCP / execution — **Config tab** explains scope; full **AgentCore** loop remains Python/Qt only
- [ ] Visual canvas: screenshots, A2UI, attachments (parity with `CanvasWidget` features you care about)
- [ ] Swarm / multi-agent / sub-agents UI (if in scope)

## Folder Watchers (automation)

- [x] List/create/edit/delete watcher definitions (**Watchers** tab, `WatcherStore`)
- [x] Storage compatibility with `~/.grizzyclaw/watchers/` JSON (same schema as Python `FolderWatcher`)
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
