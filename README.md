# Duet

Duet is a macOS-only OSS control room for two official desktop agents: Claude Desktop with Claude Code and Codex.app. It runs a local TypeScript Hub that both apps connect to over streamable HTTP MCP, plus a SwiftUI app that starts the Hub, watches the room, assigns roles, and injects human messages.

The important constraint is simple: **code does not travel through chat, OCR, or the message bus**. Claude and Codex work on the same repository on disk. Duet carries only short natural-language coordination messages such as "please review `src/auth.ts`".

## Status

This repository currently implements the Phase 1-2 MVP plus Phase 4b stall observation:

- TypeScript Hub with `/claude`, `/codex`, `/control`, and `/health`
- MCP tools: `get_briefing`, `send`, and `await_reply`
- Long-polling `await_reply` with progress notifications when the client provides a progress token
- SwiftUI macOS app that launches the Hub, connects to `/control`, displays the live transcript, updates roles, and injects human messages
- Stall observation and GUI warning display when an agent appears inactive without an active `await_reply` waiter
- Project-local Run action for the Codex desktop app

Phase 3 OCR, Phase 4c wake-up automation, session rollover, and worktree orchestration are intentionally documented but not shipped as completed features yet.

## Requirements

- macOS 14 or newer
- Node.js 20 or newer
- Swift toolchain with SwiftPM
- Claude Desktop and Codex.app for a real two-agent run

## Build

```bash
cd hub
npm install
npm run build
npm test
```

```bash
swift build --package-path app
```

Or use the project entrypoint:

```bash
./script/build_and_run.sh --verify
```

The script builds the Hub, builds the SwiftPM app, stages `dist/Duet.app`, launches it as a real app bundle, verifies the app icon metadata, checks Hub `/health`, and connects to the control WebSocket. The staged development bundle is unsigned, not notarized, and expects to run from this source checkout; expect normal local-development Gatekeeper behavior until a release signing/notarization flow exists. See `docs/RELEASE_PACKAGING.md`.

## Configuration

Copy the example and edit it for the shared repository the agents should work on:

```bash
cp config/duet.config.example.json config/duet.config.json
```

`config/duet.config.json` is gitignored because it can contain local paths and task text.
Duet.app does not fall back to the example file at runtime; if the local config is missing, it starts in an error state and does not launch the Hub.

```json
{
  "host": "127.0.0.1",
  "port": 8765,
  "repoPath": "/ABSOLUTE/PATH/TO/SHARED/REPOSITORY",
  "holdSec": 50,
  "noProgressHoldSec": 25,
  "progressIntervalSec": 20,
  "roles": {
    "claude": { "role": "implementer", "task": "Implement the change." },
    "codex": { "role": "reviewer", "task": "Review the changed files from disk." }
  }
}
```

The Hub is bound to loopback by default. Do not use a non-loopback `host` unless you also have a reviewed authentication and network exposure plan. If Node.js is not in a standard absolute path, set `DUET_NODE_PATH` to a Node 20+ executable before launching Duet.

On Hub startup, `config/duet.secrets.json` is created if missing. It is local-only, gitignored, and contains random per-agent MCP tokens:

```json
{
  "version": 1,
  "mcpTokens": {
    "claude": "<generated-token>",
    "codex": "<generated-token>"
  }
}
```

Keep this file private. To rotate these tokens, stop Duet, delete `config/duet.secrets.json`, start Duet again, and update the agent MCP registrations with the new bearer token values or fallback URLs.

## MCP Registration

The Hub exposes two agent-specific MCP route roots. Register these bare roots when the client can send an
`Authorization: Bearer <token>` header:

- Claude: `http://127.0.0.1:8765/claude`
- Codex: `http://127.0.0.1:8765/codex`

If a client cannot set MCP HTTP headers, register the secret-bearing fallback URL:

- Claude: `http://127.0.0.1:8765/claude/<claude-token>`
- Codex: `http://127.0.0.1:8765/codex/<codex-token>`

Path tokens are supported only for clients without header support, because URLs are more likely to appear in logs, screenshots, copied configs, and shell history. Do not put these tokens in screenshots, bug reports, shell history intended for sharing, or docs examples. `DUET_CONTROL_TOKEN` is separate from the MCP tokens: Duet.app generates it per run, passes it to the Hub child process, and uses it only for `/control` WebSocket authentication via `X-Duet-Control-Token`.

Claude Code and Codex MCP configuration formats can change. These references were checked on 2026-06-01:

- [MCP Streamable HTTP transport](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports): streamable HTTP is the current HTTP transport, and local servers should bind to loopback and authenticate connections.
- [MCP authorization](https://modelcontextprotocol.io/specification/2025-03-26/basic/authorization): bearer tokens belong in the `Authorization` header, not query strings, for standard MCP auth flows.
- [Codex MCP docs](https://developers.openai.com/codex/mcp): Codex supports streamable HTTP MCP servers with `url`, bearer-token env vars, and static/env HTTP headers.
- [Codex configuration reference](https://developers.openai.com/codex/config-reference): `mcp_servers.<id>.url` is the streamable HTTP endpoint setting.
- [Claude Code MCP docs](https://code.claude.com/docs/en/mcp): Claude Code supports HTTP MCP registration through `claude mcp add-json`.

Register the Claude side in Claude Code with HTTP direct registration. Do not use the Claude Desktop connector
screen or a `claude_desktop_config.json` remote-URL shape for the normal local Duet setup.

```bash
claude mcp add-json duet '{"type":"http","url":"http://127.0.0.1:8765/claude","headers":{"Authorization":"Bearer <claude-token>"}}' -s user
```

Register the Codex side in `~/.codex/config.toml` with a bearer-token environment variable:

```toml
[mcp_servers.duet]
url = "http://127.0.0.1:8765/codex"
bearer_token_env_var = "DUET_CODEX_MCP_TOKEN"
```

Codex also supports HTTP auth settings. Prefer `bearer_token_env_var` or `env_http_headers` over embedding secrets directly in config when available.

```bash
export DUET_CODEX_MCP_TOKEN="<codex-token>"
codex mcp add duet --url http://127.0.0.1:8765/codex --bearer-token-env-var DUET_CODEX_MCP_TOKEN
```

## Agent Prompts

Use the files in `prompts/` to start each official desktop agent. The prompts tell agents to call `get_briefing`, work on files directly in `repoPath`, use `send` for coordination, keep code/secrets/PII out of messages, and keep re-arming `await_reply` after `empty`.

Japanese and English prompt variants are available. Use `prompts/claude-implementer.md` and `prompts/codex-reviewer.md` for Japanese sessions, or `prompts/claude-implementer.en.md` and `prompts/codex-reviewer.en.md` for English sessions.

## Security

- Do not commit API keys, credentials, real customer data, or local `config/duet.config.json`.
- Do not commit `config/duet.secrets.json`; it contains per-agent MCP tokens.
- Do not paste source code into Duet messages. Agents must read files from the shared repository path.
- Keep Hub bound to `127.0.0.1` unless you have a reviewed reason to expose it elsewhere.
- Hub stdout logs only event metadata by default. `DUET_VERBOSE_EVENTS=1` still redacts message bodies, tasks, paths, and secret-looking values.
- OCR is a future insurance layer for screen-ground-truth only; it is not a code transport path.

## Limitations

- Duet is macOS-only.
- Phase 3 OCR, Phase 4c wake-up automation, session rollover, and worktree orchestration are not shipped as completed features.
- The development app bundle is unsigned and not notarized.
- Duet does not guarantee that either desktop agent will keep waiting forever; prompts and `await_reply` re-arming are part of the operating protocol.
- Duet is local developer tooling, not a sandbox boundary for untrusted repositories or untrusted MCP clients.

## License

MIT. See `LICENSE`. Third-party dependency inventory is in `THIRD_PARTY_LICENSES.md`.
