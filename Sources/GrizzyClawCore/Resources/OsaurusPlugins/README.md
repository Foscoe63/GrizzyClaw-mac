# Osaurus plugin manifests (bundled)

JSON files in this directory are copied from the upstream
[osaurus-tools `plugins/`](https://github.com/osaurus-ai/osaurus-tools/tree/master/plugins)
(MIT). They describe **Osaurus central-registry** plugins (tool names, descriptions, release artifacts).

GrizzyClaw-Air registers each manifest’s `capabilities.tools` as synthetic MCP servers named
`plugin_id` (for example `osaurus.time`) so models see the same surface area as the registry.
Native `.dylib` plugins are **not** executed from these zips; `osaurus.time` is implemented in Swift,
and other families return guidance to use MCP / Osaurus on a Mac where appropriate.
