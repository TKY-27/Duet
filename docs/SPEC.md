# Duet Current Specification

This is the canonical specification for product and implementation details. If
this file conflicts with `AGENTS.md` or `CLAUDE.md`, this file wins for product
and implementation details; those files govern agent behaviour and repository
working rules. Interface decisions live in `docs/DESIGN.md`. Machine
measurements live in `docs/MEASUREMENTS.md`.

## Product

Duet is a macOS-only SwiftUI app plus a local TypeScript Hub. The app is what
users launch. It starts and monitors the Hub, renders a live two-agent
transcript, lets the human assign roles, and injects human messages into the
agent queues.

The two agents are official desktop products:

- Claude Desktop with Claude Code, connected to the Claude MCP endpoint
- Codex.app, connected to the Codex MCP endpoint

The agent runtimes are not modified and are not replaced by a CLI or SDK.

## Hard Rules

- Code is never transported over MCP messages, chat, or OCR.
- Agents share a repository on disk and read/write real files with their own file tools.
- Duet messages are short natural-language coordination messages.
- The Hub is one streamable HTTP process. Do not use stdio MCP: each client
  would start a separate process and state would not be shared.
- OCR is an insurance layer for screen ground truth, not the primary output channel.
- macOS is the only target.

## Protocol Revision

The Hub is built on `@modelcontextprotocol/server` v2 and serves **both**
protocol eras from the same endpoints:

- **2026-07-28** (current revision): stateless, no `initialize` handshake, no
  `Mcp-Session-Id`, `server/discover` for version selection.
- **2025-era**: served through `createMcpHandler`'s `legacy: "stateless"` mode,
  which answers each legacy request from a fresh server built by the same
  factory.

This dual-era support is not an assumption. `hub/src/mcpIntegration.test.ts`
connects a 2025-era client and a client pinned to `2026-07-28`, exercises a
round trip on each, and asserts that a modern sender reaches a legacy waiter
across the same bus. If that pinned test ever fails, the modern path has
regressed — it must not be "fixed" by removing the pin.

Deprecated in 2026-07-28 and therefore not used: Logging (Hub diagnostics go to
stderr), Sampling, and Roots. The Tasks extension is not yet usable as an
`await_reply` replacement; the v2 SDK excludes task methods from its typed
method maps.

## Hub

- `GET /health` returns only `{ ok, service }` without authentication.
- `GET /health/details` returns detailed state and requires `X-Duet-Control-Token`.
- MCP endpoint roots: `/claude` and `/codex`.
- Registration uses `Authorization: Bearer <agent-token>` on the bare roots.
  A secret-bearing path form (`/claude/<token>`) exists only for clients that
  cannot set headers.
- Control WebSocket: `/control`, authenticated with `X-Duet-Control-Token`.

`config/duet.secrets.json` is generated locally, never committed, and contains
only random per-agent MCP tokens. Control authentication is separate: Duet.app
passes an ephemeral `DUET_CONTROL_TOKEN` to the Hub process.

### Tools

- `get_briefing()`: returns `agentId`, `role`, `peer`, `task`, `repoPath`, and protocol notes.
- `send({ message, to? })`: enqueues one natural-language message to the peer.
  `to: "human"` appends an agent-to-human transcript event and does not resolve
  any `await_reply`.
- `await_reply({ holdSec? })`: holds for a peer or human message, returns
  `empty` on timeout, and sends `notifications/progress` while holding when the
  client supplied a progress token.

A progress token is `string | number`. **`0` and `""` are valid tokens**: the
hold decision tests for presence, never truthiness. The 2026-07-28 SDK client
numbers progress tokens from `0`, and a truthiness check there silently
collapses every hold to `noProgressHoldSec`. This is covered by a regression
test that sends `_meta.progressToken = 0` directly.

### State

Process-local: per-agent queues, roles and tasks, the in-memory transcript
window, pending `await_reply` waiters, running/stopped status, and observation
state (see below). Full history is on disk (see Sessions).

### Observation

`hub/src/presence.ts` answers two separate questions from one signal, the
timestamp of each agent's last MCP tool call:

- **presence** — has this agent ever reached the Hub, and recently enough to
  still count as connected? Used by the setup flow to distinguish a
  half-configured client from a working one. Evaluated whether or not the room
  is running.
- **stall** — is a *previously seen* agent silent while holding no
  `await_reply`? That combination means it has fallen out of the waiting loop.

An agent that has never contacted the Hub is reported **absent, not stalled**.
The earlier implementation reported both agents as stalled 120 seconds after
launch even when neither had ever connected, which produced a false warning on
every fresh start.

Observation is measurement only. Nothing here opens URLs, sends keystrokes, or
wakes an external app.

### Repository status

`hub/src/git.ts` reads the shared repository so the window can show what
actually changed on disk. It is read-only and takes no input into Git
arguments: every command is a fixed argument list, and `repoPath` — already
validated as a Git worktree at config load — is used only as the working
directory. Failures degrade the status strip rather than affecting the Hub.

Reported: branch (or `detached`), short HEAD, ahead/behind, and changed files
with added/removed line counts, capped at 200 files.

### Sessions

`hub/src/store.ts` records every message to an append-only JSONL file under
`~/Library/Application Support/Duet/sessions/`, with a `sessions.json` index.
`DUET_DATA_DIR` overrides the root.

JSONL rather than SQLite: the write pattern is append-only, a session is a few
hundred short messages, and a text file is readable, greppable, diffable, and
exportable with no schema migration and no native module.

Writes are synchronous. Coordination messages arrive at human speed, so the
cost is irrelevant, and a buffered stream loses the final messages exactly when
Duet.app terminates the Hub. Files and the index are written `0600`.

**Persistence is a convenience, not a precondition.** If the data directory is
unwritable, history disables itself, reports a reason, and the Hub keeps
running with an in-memory transcript.

### Security properties

- Bind to loopback by default; reject non-loopback `Host`/`Origin` without explicit opt-in.
- Cap queue, waiter, transcript, payload, control-connection, and request rates.
- Keep source code, secrets, API keys, personal data, and raw repository
  contents out of MCP messages, role text, task text, logs, and verbose events.
- `repoPath` must resolve to an existing Git worktree and must not be root,
  home, a system path, a sensitive home path, or the Duet checkout itself.
- Session ids are server-minted UUIDs and are validated both at the control
  schema and in the store, so a crafted id cannot read outside the sessions
  directory.
- `redactControlEvent` switches exhaustively over `ControlEvent` with no
  `default`, so a new event variant fails the build rather than shipping
  unredacted.

### Control commands

`setRoles`, `injectHuman`, `start`, `stop`, `listSessions`, `newSession`,
`loadSession`, `refreshRepo`.

### Control events

`snapshot`, `message`, `rolesUpdated`, `status`, `stall`, `presence`, `repo`,
`sessions`, `sessionTranscript`, `error`.

## SwiftUI App

A SwiftPM macOS executable target named `Duet`, targeting macOS 26.

Responsibilities:

- launch `node hub/dist/server.js` and stop it when the app exits
- connect to `ws://127.0.0.1:<port>/control` with the per-run control token
- render the live transcript, repository status, presence, and stalls
- update role/task assignments and inject human messages
- expose start/stop and connection state
- guide first-time setup to a verified connection

Interface structure and the reasoning behind it are in `docs/DESIGN.md`.

## Not Yet Complete

Intentionally outside the shipped implementation:

- ScreenCaptureKit + Vision OCR insurance layer
- wake-up automation for stalled agents
- session rollover on context exhaustion
- worktree orchestration
- fully automated free-dialogue game flows

They should be implemented in small reviewed phases and must preserve the hard
rules above.
