# Python app and Swift UI sharing `~/.grizzyclaw`

Both the Python desktop app and the **GrizzyClaw** macOS Swift UI read and write the same user data directory:

- **`config.yaml`** — merged on load; either app may save changes.
- **`workspaces.json`** — `active_workspace_id` and `baseline_workspace_id` are updated by the Swift UI when you select a workspace or set a baseline. Reload the Python app to pick up changes.
- **`sessions/`** — chat history JSON per workspace uses the same naming convention as the Python `AgentCore` session files (`{workspaceId}_gui_user.json`). The Swift Chat tab also writes **`{workspaceId}_gui_user_archived_<timestamp>.json`** when you use **New chat** (the active file is moved aside, then replaced with an empty session).
- **Import / export** — Swift can **Export…** / **Import…** transcripts (JSON array or Markdown with `## User` / `## Assistant` / `## System`). Imports overwrite the current workspace’s session file when persistence is on.
- **External edits** — If another process changes the session file on disk, the Swift app detects a newer modification time on sync and shows an informational line; use **Reload from disk** to re-read.

**Safe practice:** Avoid running heavy writes from both apps at the exact same moment. For backups, use **Create backup of ~/.grizzyclaw…** in the Swift app menu (or copy the folder in Finder) before risky edits.

Secrets (API keys) typically live in **`secrets.yaml`** (or provider env vars); including them in a zip backup can be convenient for restore but increases exposure—store archives accordingly.
