# Next tasks — three tracks

Actionable backlog for **GrizzyClaw-mac**. Pick items by track; many can ship as small PRs. Update this file when something ships (or move done items to `parity-checklist.md`).

**Reference code (Python):** `../GrizzyClaw/grizzyclaw/` — especially `gui/main_window.py`, `gui/workspace_dialog.py`, `agent/core.py`, `config.py`, `workspaces/`.

---

## Track A — Persistence & shared files

Goal: safe coexistence with the Python app, recoverable user data, and obvious export paths.

| ID | Task | Notes / acceptance |
|----|------|-------------------|
| A1 | **Export conversation** | ✅ Chat tab: “Export…” → Markdown / JSON (`ChatExportPresenter`). |
| A2 | **“New chat” without losing history** | ✅ **New chat** archives non-empty session to `{ws}_gui_user_archived_<UTC>.json`, then empty session (`SessionPersistence.archiveCurrentSessionIfNonEmpty` + `ChatSessionModel.newChatArchivingPrevious`). **Clear chat** still deletes the session file. |
| A3 | **Backup subset of `~/.grizzyclaw/`** | ✅ Menu: “Create backup of ~/.grizzyclaw…” (`GrizzyClawShell.presentBackupSavePanel`). |
| A4 | **Coexistence doc** | ✅ `docs/python-swift-coexistence.md`. |
| A5 | **Session file conflict detection** | ✅ On sync, compares session file mtime to last recorded (`UserDefaults`); info line if changed externally; **Reload from disk** button. |
| A6 | **Import session** | ✅ **Import…** → JSON (session array) or Markdown (`## User` / `## Assistant` / `## System`) via `ChatImportParser` + `ChatImportPresenter`. |

---

## Track B — Workspace editing & navigation

Goal: match Python workspace affordances that power users expect.

| ID | Task | Notes / acceptance |
|----|------|-------------------|
| B1 | **Baseline workspace** | ✅ **Set as baseline** / **Go to baseline** + menu ⌃⇧B (`WorkspaceStore` + `WorkspaceActivePersistence`). |
| B2 | **Workspace templates** | ✅ Loads `workspace_templates.json` via `WorkspaceTemplatesLoader`; toolbar **New from template…** + Template picker in new-workspace sheet; empty-state copy when no file/entries. |
| B3 | **Edit sheet parity** | ✅ `temperature`, `max_tokens`, `system_prompt` + LLM fields in `WorkspaceEditSheet`. |
| B4 | **Reorder workspaces** | ✅ Sidebar `.onMove` + `WorkspaceStore.moveWorkspace`. |
| B5 | **Duplicate workspace** | ✅ Detail **Duplicate** → `duplicateWorkspace` (new id, copied `config`, name + ` (copy)`). |

---

## Track C — Polish, errors & reliability

Goal: fewer silent failures, clearer recovery, consistent UX under load.

| ID | Task | Notes / acceptance |
|----|------|-------------------|
| C1 | **Unified error surface** | ✅ Shared `GrizzyClawStatusBanner` / `GrizzyClawInfoBanner` / `GrizzyClawStoreErrorBanner` (Chat, Workspaces, Watchers, Config load error); optional recovery line on status banner. |
| C2 | **Connection test: retry** | ✅ **Retry test** waits 400ms before re-ping (`retryConnectionTest`) for flaky localhost. |
| C3 | **Stream errors: map codes** | ✅ `LLMErrorHints`: 401/403/429/404/5xx + connection/DNS/timeout hints; stream errors via `formattedMessage`; ping failures via `formattedPingFailureMessage`. |
| C4 | **Stop / cancel feedback** | ✅ Stop sets info “Cancelled.”, clears red status; treats `URLError.cancelled` / `NSURLErrorCancelled`; `isStreaming` cleared in `defer` (no stuck spinner). |
| C5 | **Structured logging** | ✅ `GrizzyClawLog` (`os.Logger`): errors always; `debug(_:)` when `config.yaml` `debug: true` (`ConfigStore.reload` → `setDebugEnabled`). Chat send path, stores, config load. |
| C6 | **Empty & loading states** | ✅ `isReloading` + `ProgressView` on Chat / Workspaces / Watchers; Send (and connection test) disabled until workspace index + valid selection; empty copy + Watchers empty list hint. |
| C7 | **Keychain for API keys** | ✅ `GrizzyClawKeychain` + `UserConfigSecrets.mergedWithKeychain()` / `loadSecretsWithKeychain()` (Keychain overrides YAML). Config tab documents service + account names. |

---

## Suggested sequencing (all three in parallel)

1. **Quick wins:** ~~C2, C3, C4~~ *(done)*.  
2. **User-visible features:** ~~A1, B1, B3~~ *(done)*.  
3. **Heavier:** ~~A3, A4, B2, B4, C5–C7~~ *(Tracks A–C backlog cleared; follow-ups in `parity-checklist.md` if any.)*

---

## How to use this doc in issues

Copy a row into a GitHub issue: title `A1: Export conversation`, body = Notes column + link to this file.
