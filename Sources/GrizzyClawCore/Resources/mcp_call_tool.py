#!/usr/bin/env python3
"""
Invoke a single MCP tool (stdio or streamable HTTP). Same protocol stack as GrizzyClaw Python `call_mcp_tool`.

Stdin: JSON object:
  { "mcp_file": "/path/to/grizzyclaw.json", "mcp": "server_name", "tool": "tool_name", "arguments": { ... } }

Stdout: JSON { "result": "<text>", "error": null } or { "result": null, "error": "<message>" }

If the MCP Python SDK is missing, auto-install: python3 -m pip install --user 'mcp[stdio]' httpx
(Set GRIZZYCLAW_NO_AUTO_PIP=1 to disable.)
"""
from __future__ import annotations

import asyncio
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, Optional

DEFAULT_TOOL_CALL_TIMEOUT = 60

MCP_AVAILABLE = False
STREAMABLE_HTTP_AVAILABLE = False
ClientSession = None  # type: ignore[assignment]
StdioServerParameters = None  # type: ignore[assignment]
stdio_client = None  # type: ignore[assignment]
streamable_http_client = None  # type: ignore[assignment]


def _add_user_site_to_path() -> None:
    import site

    try:
        p = site.getusersitepackages()
        if p and p not in sys.path:
            sys.path.insert(0, p)
    except Exception:
        pass


def _load_mcp_sdk() -> None:
    global MCP_AVAILABLE, STREAMABLE_HTTP_AVAILABLE
    global ClientSession, StdioServerParameters, stdio_client, streamable_http_client
    MCP_AVAILABLE = False
    STREAMABLE_HTTP_AVAILABLE = False
    try:
        from mcp import ClientSession as _CS, StdioServerParameters as _SP
        from mcp.client.stdio import stdio_client as _sc

        ClientSession, StdioServerParameters, stdio_client = _CS, _SP, _sc
        MCP_AVAILABLE = True
    except ImportError:
        pass
    try:
        from mcp.client.streamable_http import streamable_http_client as _sh

        streamable_http_client = _sh
        STREAMABLE_HTTP_AVAILABLE = True
    except ImportError:
        STREAMABLE_HTTP_AVAILABLE = False


def _maybe_pip_install_mcp_sdk() -> None:
    if os.environ.get("GRIZZYCLAW_NO_AUTO_PIP", "").strip().lower() in ("1", "true", "yes"):
        return
    if os.environ.get("_GRIZZYCLAW_MCP_PIP_TRIED") == "1":
        return
    try:
        env = os.environ.copy()
        env.setdefault("PIP_DISABLE_PIP_VERSION_CHECK", "1")
        proc = subprocess.run(
            [sys.executable, "-m", "pip", "install", "--user", "mcp[stdio]", "httpx"],
            timeout=300,
            capture_output=True,
            text=True,
            env=env,
        )
        if proc.returncode != 0:
            return
    except Exception:
        return
    script = os.path.abspath(__file__)
    nenv = os.environ.copy()
    nenv["_GRIZZYCLAW_MCP_PIP_TRIED"] = "1"
    try:
        os.execve(sys.executable, [sys.executable, script] + sys.argv[1:], nenv)
    except Exception:
        _add_user_site_to_path()


_load_mcp_sdk()
if not MCP_AVAILABLE:
    _maybe_pip_install_mcp_sdk()
    _add_user_site_to_path()
    _load_mcp_sdk()


def normalize_mcp_args(args: Any) -> list:
    if args is None:
        return []
    if isinstance(args, str):
        s = args.strip()
        if s.startswith("[") and s.endswith("]"):
            try:
                parsed = json.loads(s)
                if isinstance(parsed, list):
                    return [str(x) for x in parsed]
                return [s]
            except json.JSONDecodeError:
                return s.split() if s else []
        return s.split() if s else []
    if not isinstance(args, (list, tuple)):
        return []
    out = []
    for a in args:
        s = str(a).strip()
        if s.startswith("[") and s.endswith("]"):
            try:
                parsed = json.loads(s)
                if isinstance(parsed, list):
                    out.extend(str(x) for x in parsed)
                else:
                    out.append(s)
            except json.JSONDecodeError:
                out.append(s)
        else:
            out.append(s)
    return out


def _get_expanded_env() -> Dict[str, str]:
    env = os.environ.copy()
    current = env.get("PATH", "")
    extra = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin",
        str(Path.home() / ".local" / "bin"),
        str(Path.home() / ".cargo" / "bin"),
        "/usr/bin",
        "/bin",
    ]
    for p in extra:
        if os.path.isdir(p) and p not in current:
            current = f"{p}:{current}"
    env["PATH"] = current
    return env


def _env_for_server(config: Dict[str, Any]) -> Dict[str, str]:
    env = _get_expanded_env()
    server_env = config.get("env") or {}
    if isinstance(server_env, dict):
        for k, v in server_env.items():
            env[str(k)] = str(v)
    return env


def _load_server_config(mcp_file: Path, mcp_name: str) -> Optional[Dict[str, Any]]:
    if not mcp_file.exists():
        return None
    try:
        with open(mcp_file, "r") as f:
            data = json.load(f)
        servers = data.get("mcpServers", {})
        if mcp_name in servers:
            return servers.get(mcp_name)

        def _strip_bracket_suffix(raw: str) -> str:
            s = (raw or "").strip()
            i = s.find("[")
            return s[:i].strip() if i >= 0 else s

        def _canonical_server_name(raw: str, known: list[str]) -> str:
            cur = _strip_bracket_suffix(raw)
            if not cur:
                return cur
            known_set = set(known)
            for _ in range(8):
                if cur in known_set:
                    return cur
                ci = [k for k in known if k.lower() == cur.lower()]
                if len(ci) == 1:
                    return ci[0]
                lower = cur.lower()
                if lower.startswith("user-"):
                    cur = cur[5:]
                    continue
                if lower in ("web-search", "google-search", "search"):
                    cur = "ddg-search"
                    continue
                hyphen = cur.replace("_", "-")
                if hyphen != cur:
                    cur = hyphen
                    continue
                break
            return _strip_bracket_suffix(raw)

        known = list(servers.keys())
        canon = _canonical_server_name(mcp_name, known)
        for key, value in servers.items():
            if _canonical_server_name(key, known) == canon:
                return value
        return None
    except Exception:
        return None


def _get_mcp_url(config: Dict[str, Any]) -> str:
    url = config.get("url", "").rstrip("/")
    if not url:
        return ""
    if url.endswith("/mcp") or url.endswith("/mcp/"):
        return url.rstrip("/")
    return f"{url.rstrip('/')}/mcp"


async def _call_tool_http(config: Dict[str, Any], tool_name: str, arguments: Dict[str, Any]) -> str:
    if not STREAMABLE_HTTP_AVAILABLE:
        return "**❌ Remote MCP requires streamable HTTP support.** Run: python3 -m pip install --user 'mcp[stdio]' httpx (auto-install may have failed)."
    mcp_url = _get_mcp_url(config)
    if not mcp_url:
        return "**❌ Invalid URL in MCP server config.**"
    headers = config.get("headers") or {}
    if isinstance(headers, str):
        try:
            headers = json.loads(headers) if headers else {}
        except json.JSONDecodeError:
            headers = {}
    try:
        import httpx

        t_override = 0
        try:
            t_override = int(config.get("timeout_s", 0) or 0)
        except Exception:
            t_override = 0
        effective_timeout = max(5, min(300, t_override or 30))

        async with httpx.AsyncClient(
            headers=headers,
            timeout=httpx.Timeout(float(effective_timeout)),
        ) as http_client:
            async with streamable_http_client(mcp_url, http_client=http_client) as (
                read,
                write,
                _,
            ):
                async with ClientSession(read, write) as session:
                    await session.initialize()
                    result = await session.call_tool(tool_name, arguments)

                    if getattr(result, "isError", False):
                        err_parts = []
                        for c in result.content:
                            if hasattr(c, "text"):
                                err_parts.append(c.text)
                        return f"**❌ Tool error:** {' '.join(err_parts) or 'Unknown error'}"

                    parts = []
                    for content in result.content:
                        if hasattr(content, "text"):
                            parts.append(content.text)
                    return "\n".join(parts) if parts else "(No output)"
    except Exception as e:
        return f"**❌ HTTP MCP tool error:** {e}"


async def _call_tool_stdio(config: Dict[str, Any], tool_name: str, arguments: Dict[str, Any]) -> str:
    if not MCP_AVAILABLE:
        return "**❌ MCP stdio client not available.** Run: python3 -m pip install --user 'mcp[stdio]' httpx (auto-install may have failed)."
    cmd = config.get("command", "")
    args_list = normalize_mcp_args(config.get("args", []))
    if not cmd:
        return "**❌ No command in MCP server config.**"
    server_params = StdioServerParameters(
        command=cmd,
        args=args_list,
        env=_env_for_server(config),
    )
    try:
        async with stdio_client(server_params) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                result = await session.call_tool(tool_name, arguments)

                if getattr(result, "isError", False):
                    err_parts = []
                    for c in result.content:
                        if hasattr(c, "text"):
                            err_parts.append(c.text)
                    err_txt = " ".join(err_parts) or "Unknown error"
                    return f"**❌ Tool error:** {err_txt}"

                parts = []
                for content in result.content:
                    if hasattr(content, "text"):
                        parts.append(content.text)
                return "\n".join(parts) if parts else "(No output)"
    except Exception as e:
        return f"**❌ Stdio MCP tool error:** {e}"


async def run_call(mcp_file: Path, mcp_name: str, tool_name: str, arguments: Dict[str, Any]) -> str:
    config = _load_server_config(mcp_file, mcp_name)
    if not config:
        return f"**❌ MCP server '{mcp_name}' not found in {mcp_file}.**"
    if config.get("enabled", True) is False:
        return f"**❌ MCP server '{mcp_name}' is disabled in the JSON file.**"

    t_override = 0
    try:
        t_override = int(config.get("timeout_s", 0) or 0)
    except Exception:
        t_override = 0
    timeout = max(5, min(300, t_override or DEFAULT_TOOL_CALL_TIMEOUT))

    if "url" in config:
        return await asyncio.wait_for(_call_tool_http(config, tool_name, arguments), timeout=timeout)
    return await asyncio.wait_for(_call_tool_stdio(config, tool_name, arguments), timeout=timeout)


async def main_async() -> int:
    raw = sys.stdin.read()
    if not raw.strip():
        print(json.dumps({"result": None, "error": "empty stdin"}))
        return 2
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        print(json.dumps({"result": None, "error": f"invalid JSON stdin: {e}"}))
        return 2

    mcp_file_s = payload.get("mcp_file") or ""
    mcp_name = (payload.get("mcp") or "").strip()
    tool_name = (payload.get("tool") or "").strip()
    arguments = payload.get("arguments") if isinstance(payload.get("arguments"), dict) else {}

    if not mcp_file_s or not mcp_name or not tool_name:
        print(json.dumps({"result": None, "error": "missing mcp_file, mcp, or tool"}))
        return 2

    mcp_file = Path(mcp_file_s).expanduser()
    try:
        out = await run_call(mcp_file, mcp_name, tool_name, arguments)
        print(json.dumps({"result": out, "error": None}))
        return 0
    except asyncio.TimeoutError:
        print(json.dumps({"result": None, "error": f"timeout calling {mcp_name}.{tool_name}"}))
        return 1
    except Exception as e:
        print(json.dumps({"result": None, "error": str(e)}))
        return 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main_async()))
