# GrizzyClaw → Swift migration roadmap

Full parity with the Python tree (`grizzyclaw/`, ~hundreds of modules) is a **multi-phase** effort. Work lands in this repo under **`GrizzyClaw-mac/`**; the Python app remains the reference implementation until each area is marked done in `parity-checklist.md`.

**Concrete backlog (three tracks: persistence, workspaces, polish):** see [`next-tasks.md`](./next-tasks.md).

## Target layout (Swift)

| Swift (planned / existing) | Python source (reference) |
|----------------------------|---------------------------|
| `GrizzyClawCore` | `config.py`, `security.py`, `workspaces/`, `memory/` types, paths |
| `GrizzyClawAgent` (future package) | `agent/`, `llm/`, `safety/` |
| `GrizzyClawUI` | `gui/*` (PyQt) → SwiftUI |
| `GrizzyClawChannels` (optional) | `channels/`, `web/` |
| Executable + `App/MacHost` | `__main__.py`, `cli.py` |

## Phases

1. **Shell & data** — Paths, `workspaces.json`, `config.yaml` read, Keychain stubs. *(in progress)*
2. **Chat MVP** — Session model, OpenAI-compatible streaming client, minimal tool-less turns.
3. **Agent parity** — MCP, tools, trimming, workspace-scoped config (large; port incrementally).
4. **Dialogs** — Memory, sessions, scheduler, watchers, etc., per `parity-checklist.md`.
5. **Channels** — Telegram/web only if product requires native Swift parity.

## Rule

Port **behavior from code**, not line-by-line translation. Share on-disk formats (`config.yaml`, `workspaces.json`, SQLite) so Python and Swift can coexist during migration.
