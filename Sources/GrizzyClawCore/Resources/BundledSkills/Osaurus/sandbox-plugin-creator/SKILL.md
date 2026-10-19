---
name: Sandbox Plugin Creator
description: Create new sandbox plugins when you need an integration or capability that does not exist yet (Osaurus-oriented; sandbox execution is not available in GrizzyClaw-Air).
version: 1.0.0
author: Osaurus
category: development
keywords: plugin, integration, sandbox, tools
grizzy_skill_id: osaurus-sandbox-plugin-creator
default_enabled: true
---

# Sandbox Plugin Creator

You can create new tools for yourself by writing sandbox plugins.
A sandbox plugin is a JSON recipe with helper scripts that run in your sandbox.

## When to Use

When you need to connect to, integrate with, or use a service that you don't
currently have tools for, AND the service has an API you can call from Python
or Node.js.

## Steps

### 1. Check if tools already exist

Use `capabilities_search` first. If matching tools exist, use them instead.

### 2. Check and prompt for secrets

Most APIs need an API key or token.

```
sandbox_secret_check(key: "SERVICE_API_KEY")
```

If the secret doesn't exist, prompt the user to provide it:

```
sandbox_secret_set(
    key: "SERVICE_API_KEY",
    description: "API key for the service",
    instructions: "Go to https://example.com/settings → API Keys → Create new key → copy the value"
)
```

If you already have the secret value (e.g. from user input or Host API), pass it directly:

```
sandbox_secret_set(
    key: "SERVICE_API_KEY",
    description: "API key for the service",
    instructions: "...",
    value: "sk-the-actual-key"
)
```

### 3. Create the plugin directory and files

Use `sandbox_write_file` to create files under `plugins/{service-name}/`:

```
plugins/{service-name}/
  ├── plugin.json
  └── scripts/
        ├── action1.py
        ├── action2.py
        └── ...
```

Write the scripts FIRST, then plugin.json. When you call
`sandbox_plugin_register`, all files in the directory are automatically
packaged for installation and persistence — you do NOT need to inline
file contents in plugin.json.

### 4. Write plugin.json

The plugin.json follows the SandboxPlugin schema:

```json
{
  "name": "Service Name",
  "description": "What this integration does",
  "dependencies": ["python3", "py3-pip"],
  "setup": "pip install service-sdk",
  "secrets": ["SERVICE_API_KEY"],
  "permissions": {
    "network": "api.service.com"
  },
  "tools": [
    {
      "id": "list_items",
      "description": "List all items from the service",
      "parameters": {},
      "run": "python3 scripts/list_items.py"
    },
    {
      "id": "get_item",
      "description": "Get a specific item by ID",
      "parameters": {
        "item_id": {
          "type": "string",
          "description": "The item ID to retrieve"
        }
      },
      "run": "python3 scripts/get_item.py"
    }
  ]
}
```

Key fields:
- `dependencies`: Alpine system packages (installed via `apk add`)
- `setup`: Shell command for pip/npm installs (runs as your user). Setup
  AND every tool's `run` command are validated against the network
  allowlist (Alpine repos, PyPI, npm, GitHub, crates.io). A `curl`
  to any other host fails registration with a clear error.
- `secrets`: Array of secret names the plugin needs (values come from Keychain).
  Registration fails up-front if a declared secret has no value yet —
  call `sandbox_secret_set` first.
- `permissions.network`: Comma-separated API domains the scripts need to reach.
  The values `outbound` and `none`, plus any list with malformed
  domains, collapse to `none`. List the exact API hostnames you need.
- `permissions.inference` is forced to `false` for agent-authored plugins.
- `tools`: Array of tool definitions with `id`, `description`, `parameters`, and `run` command
- Do NOT add a `files` field — scripts in the directory are collected automatically.
  Binary files in the directory are rejected — either remove them or
  regenerate them in `setup`.

### 5. Write the scripts

Each tool's `run` command executes a script. Script rules:

- **Parameters** are available as `$PARAM_{NAME}` environment variables (uppercased)
- **Secrets** are available as environment variables using their key name (e.g. `$SERVICE_API_KEY`)
- **Output** goes to stdout as JSON
- **Errors** go to stderr
- Exit 0 on success, non-zero on failure
- Handle missing parameters gracefully with clear error messages

Example script:

```python
#!/usr/bin/env python3
import os, json, sys

api_key = os.environ.get("SERVICE_API_KEY")
if not api_key:
    print(json.dumps({"error": "SERVICE_API_KEY not configured"}))
    sys.exit(1)

item_id = os.environ.get("PARAM_ITEM_ID", "")

try:
    # Call the API
    result = call_api(api_key, item_id)
    print(json.dumps(result, indent=2))
except Exception as e:
    print(json.dumps({"error": str(e)}), file=sys.stderr)
    sys.exit(1)
```

### 6. Register the plugin

Call `sandbox_plugin_register` with the plugin directory name:

```
sandbox_plugin_register(plugin_id: "service-name")
```

This installs dependencies, runs setup, registers tools, and makes them
available immediately. The plugin is also saved to the library for
persistence and sharing.

### 7. Test and confirm

Call one of the newly registered tools to verify it works.
If it fails, read the stderr, fix the script, and re-register.

Tell the user what tools are now available and give a quick example
of what they can do.

## Guidelines

- Keep tools focused — one action per tool, not a mega-tool
- Use well-maintained Python/Node libraries when available
- Always validate that required parameters are present
- Return structured JSON, not raw text
- Include pagination support for list operations
- Default to read operations first; only add write operations if asked
- Tool names are auto-prefixed with the plugin ID (e.g. `notion_list_databases`)
