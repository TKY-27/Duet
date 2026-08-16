# Duet

**日本語版は [README.ja.md](README.ja.md) にあります。**

Duet is a macOS control room for two agents that already live in desktop apps.

It coordinates **Claude Desktop's Claude Code** and **Codex.app** through a
local MCP hub, shows their conversation live, lets you assign roles, and lets
you interrupt at any point. You launch one SwiftUI app; it starts the hub for
you.

Plenty of projects make Claude Code CLI and Codex CLI review each other's work.
Duet is for people who would rather not live in the terminal to watch it
happen. The agents stay in their official apps. Duet is the window onto what
they are doing, and the place you step in.

![Duet demo](assets/duet-demo.gif)

> The GIF predates the current interface and will be replaced.

## The one rule that shapes everything

**Code never travels through the message bus.** Claude and Codex share the same
repository on disk and read and write real files with their own file tools. All
Duet carries is short natural-language coordination — "please review
`src/auth.ts`". Reviews happen by reading the file, not by pasting it into a
chat.

## Requirements

- macOS 26 or newer
- Node.js 22 or newer
- Swift toolchain with SwiftPM
- Claude Desktop and Codex.app, for a real two-agent run

## Build and run

```bash
cd hub && npm install && npm run build && npm test
```

```bash
swift build --package-path app
```

Or use the project entry point, which builds both, stages `dist/Duet.app`,
launches it, and checks hub health and the control WebSocket:

```bash
./script/build_and_run.sh --verify
```

To launch Duet as the always-on local room:

```bash
./script/build_and_run.sh run
```

The staged development bundle is unsigned and not notarized, and expects to run
from this source checkout. Expect normal local-development Gatekeeper
behaviour. See [docs/RELEASE_PACKAGING.md](docs/RELEASE_PACKAGING.md).

## Configuration

```bash
cp config/duet.config.example.json config/duet.config.json
```

`config/duet.config.json` is gitignored because it contains local paths and
task text. Duet does not fall back to the example at runtime: without a local
config it starts in an error state and does not launch the hub.

```json
{
  "host": "127.0.0.1",
  "port": 8765,
  "repoPath": "/ABSOLUTE/PATH/TO/SHARED/REPOSITORY",
  "holdSec": 180,
  "noProgressHoldSec": 50,
  "progressIntervalSec": 20
}
```

`holdSec` applies when the MCP client sends progress notifications;
`noProgressHoldSec` applies when it does not. The values above come from the
Phase 0 measurement path recorded in [docs/MEASUREMENTS.md](docs/MEASUREMENTS.md).

The hub binds to loopback by default. Do not set a non-loopback `host` without
a reviewed authentication and network-exposure plan. If Node is not on a
standard absolute path, set `DUET_NODE_PATH` before launching.

On startup the hub creates `config/duet.secrets.json` if missing — local-only,
gitignored, containing random per-agent MCP tokens. To rotate them: stop Duet,
delete the file, start Duet, and re-register both agents.

## Connecting the agents

The hub exposes one MCP route per agent. Register the bare route and put the
token in an `Authorization: Bearer` header.

**Claude** — register in **Claude Code** with HTTP direct registration:

```bash
claude mcp add-json duet '{"type":"http","url":"http://127.0.0.1:8765/claude","headers":{"Authorization":"Bearer <claude-token>"}}' -s user
```

```bash
claude mcp list
```

Do **not** paste this local HTTP URL into the Claude Desktop connector screen,
and do not use a `claude_desktop_config.json` remote-URL shape here. That path
assumes publicly reachable HTTPS/OAuth-style connectors and will not work.

**Codex** — in `~/.codex/config.toml`, keeping the token in an environment
variable so it stays out of config files and shell history:

```toml
[mcp_servers.duet]
url = "http://127.0.0.1:8765/codex"
bearer_token_env_var = "DUET_CODEX_MCP_TOKEN"
```

```bash
export DUET_CODEX_MCP_TOKEN="<codex-token>"
codex mcp add duet --url http://127.0.0.1:8765/codex --bearer-token-env-var DUET_CODEX_MCP_TOKEN
```

If a client cannot set MCP headers, a secret-bearing URL form
(`http://127.0.0.1:8765/claude/<token>`) exists for that client only. Prefer
headers: URLs end up in logs, screenshots, copied configs, and shell history.

`DUET_CONTROL_TOKEN` is separate from the MCP tokens. Duet.app generates it per
run for `/control` authentication only.

## A typical round trip

1. Start Duet. Confirm the hub reports connected.
2. Register both MCP endpoints as above.
3. Assign roles — for example Claude as implementer, Codex as reviewer.
4. Paste `prompts/codex-reviewer.md` into Codex first, so it enters the waiting
   loop on `await_reply`.
5. Paste `prompts/claude-implementer.md` into Claude Code. Claude edits files
   under `repoPath`, sends Codex a review request, and waits.
6. Watch the exchange. Use the input bar to interrupt with a message to Claude,
   Codex, or both — human messages are delivered as top-priority instructions.

English and Japanese prompt variants are in `prompts/`.

## Protocol support

The hub is built on the v2 MCP TypeScript SDK and serves **both** the
2026-07-28 revision and the 2025-era protocol from the same endpoints, so it
works whether or not a given desktop app has adopted the new revision. This is
verified by tests that connect a 2025-era client and a client pinned to
2026-07-28 and assert a message crosses between them.

`await_reply` is a long poll. When the client provides a progress token the hub
sends `notifications/progress` while holding, which keeps the client's
per-request timeout from firing. When it does not, the hold is capped to
`noProgressHoldSec` and the agent re-arms on `empty`.

## What is and is not implemented

Shipped: the hub with its three MCP tools and dual-era support, the control
WebSocket, presence and stall observation, read-only Git status, and
append-only session history with Markdown export.

Not shipped, though documented: ScreenCaptureKit + Vision OCR, wake-up
automation for stalled agents, session rollover, and worktree orchestration.

## Security

- Do not commit `config/duet.config.json`, `config/duet.secrets.json`, API
  keys, credentials, or real customer data.
- Do not paste source code into Duet messages. Agents read files from the
  shared repository path.
- Keep the hub on `127.0.0.1` unless you have a reviewed reason not to.
- Hub stdout logs event metadata only. `DUET_VERBOSE_EVENTS=1` still redacts
  message bodies, tasks, paths, and secret-looking values.
- Session history is written `0600` under `~/Library/Application Support/Duet`.
- Duet is local developer tooling. It is not a sandbox boundary for untrusted
  repositories or untrusted MCP clients.

Report vulnerabilities per [SECURITY.md](SECURITY.md).

## Limitations

- macOS only.
- The development app bundle is unsigned and not notarized.
- Duet does not guarantee either desktop agent keeps waiting forever; the
  prompts and `await_reply` re-arming are part of the operating protocol.

## Documentation

- [docs/SPEC.md](docs/SPEC.md) — canonical product and implementation spec
- [docs/DESIGN.md](docs/DESIGN.md) — interface principles and what they replaced
- [docs/MEASUREMENTS.md](docs/MEASUREMENTS.md) — machine measurements behind the timing and automation decisions
- [docs/RELEASE_PACKAGING.md](docs/RELEASE_PACKAGING.md) — packaging notes
- [CONTRIBUTING.md](CONTRIBUTING.md) — local checks and house rules
- [CHANGELOG.md](CHANGELOG.md)

## License

MIT. See [LICENSE](LICENSE). Third-party inventory in
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md), generated by
`npm run license:generate`.
