# Duet Current Specification

This is the current canonical specification for product and implementation details. If this file conflicts with `AGENTS.md` or `CLAUDE.md`, this file wins for product and implementation details. `AGENTS.md` and `CLAUDE.md` govern agent behavior and repository working rules.

## Product

Duet is a macOS-only SwiftUI app plus a local TypeScript Hub. The app is what users launch. It starts and monitors the Hub, renders a live two-agent transcript, lets the human assign roles, and injects human messages into the agent queues.

The two agents are official desktop products:

- Claude Desktop with Claude Code, connected to the Claude MCP endpoint
- Codex.app, connected to the Codex MCP endpoint

The agent runtimes are not modified and are not replaced by a CLI or SDK.

## Hard Rules

- Code is never transported over MCP messages, chat, or OCR.
- Agents share a repository on disk and read/write real files with their own file tools.
- Duet messages are short natural-language coordination messages.
- The Hub is one streamable HTTP process. Do not use stdio MCP because each client would start a separate process and state would not be shared.
- OCR is an insurance layer for screen-ground-truth, not the primary output channel.
- macOS is the only target.

## Phase 1 Hub

The Hub is a strict TypeScript Node service with:

- `GET /health` returns only `{ ok, service }` without authentication.
- `GET /health/details` returns detailed state and requires `X-Duet-Control-Token`.
- streamable HTTP MCP endpoint roots:
  - `/claude`
  - `/codex`
- production registration should use `Authorization: Bearer <agent-token>` on the bare endpoint roots when the MCP client supports custom headers:
  - Claude Code: register HTTP directly with
    `claude mcp add-json duet '{"type":"http","url":"http://127.0.0.1:8765/claude","headers":{"Authorization":"Bearer <token>"}}' -s user`
  - Codex: register `~/.codex/config.toml` with `[mcp_servers.duet]`, `url = "http://127.0.0.1:8765/codex"`, and
    `bearer_token_env_var = "DUET_CODEX_MCP_TOKEN"`
- Claude Desktop connector UI and `claude_desktop_config.json` remote-URL shapes are not the normal local Duet registration path.
- fallback registration uses per-agent secret-bearing endpoint URLs derived from `config/duet.secrets.json` only when the client cannot set headers:
  - Claude: `/claude/<claude-mcp-token>`
  - Codex: `/codex/<codex-mcp-token>`
- control WebSocket:
  - `/control`

`config/duet.secrets.json` is generated locally, is never committed, and contains only random per-agent MCP tokens. Control WebSocket authentication is separate: Duet.app passes an ephemeral `DUET_CONTROL_TOKEN` to the Hub process and then connects to `/control` with `X-Duet-Control-Token`.

State is process-local:

- per-agent queues
- roles and tasks
- transcript
- pending `await_reply` waiters
- running/stopped status for GUI display
- per-agent last activity timestamps and stall observation state

Tools:

- `get_briefing()`: returns `agentId`, `role`, `peer`, `task`, `repoPath`, and protocol notes.
- `send({ message, to? })`: enqueues one natural-language message to the peer by default. `to:"human"` appends an
  agent-to-human transcript event for the GUI and does not resolve any `await_reply`.
- `await_reply({ holdSec? })`: waits for a peer or human message, returns `empty` on timeout, and sends progress notifications when a progress token is present.

Security properties:

- bind to loopback by default
- reject non-loopback `Host` and `Origin` values unless explicitly opted in for a reviewed test setup
- cap queue, waiter, transcript, transport, payload, control connection, and request rates
- do not put source code, secrets, API keys, personal data, or raw repository contents into MCP coordination messages, role text, task text, logs, or verbose events
- keep repository work inside `repoPath`; by default `repoPath` must resolve to an existing Git worktree and must not be root, home, system, sensitive home, or the Duet source checkout itself

Control commands:

- `setRoles`
- `injectHuman`
- `start`
- `stop`

Control events:

- `snapshot`
- `message`
- `rolesUpdated`
- `status`
- `stall`
- `error`

Phase 4b stall observation is deliberately limited to measurement and GUI
warning display. The Hub records each agent's last activity when that agent
calls `await_reply`, sends with `send`, or receives a message through a resolved
waiter. An agent is considered possibly stalled only when
`now - lastActivityAt > stallThresholdSec` and that agent has no active
`await_reply` waiter. The Hub emits a `stall` control event only when the
per-agent state changes between normal and stalled, and snapshots include the
current per-agent stall state for GUI reconnection. This phase does not open
URLs, run AppleScript, type keystrokes, submit prompts, or otherwise wake
external apps.

## Phase 2 SwiftUI App

The app is a SwiftPM macOS executable target named `Duet`.

Responsibilities:

- launch `node hub/dist/server.js`
- stop the Hub process when the app exits
- connect to `ws://127.0.0.1:8765/control` with the per-run control token in `X-Duet-Control-Token`
- render the live transcript
- update role/task assignments
- inject human messages to Claude, Codex, or both
- expose start/stop and connection state

UI follows the existing Claude Design output:

- compact macOS command-center window
- left role/session panel
- central transcript
- bottom human injection bar
- dark, light, and terminal themes

## Phase 3 OCR Preconditions

These values were measured on this machine on 2026-06-01 before implementing
the OCR insurance layer. They are implementation preconditions, not proof that
OCR capture quality or OCR accuracy is ready.

Installed application paths were checked with:

- `ls /Applications | grep -i -E "codex|claude"` -> `Claude.app`, `Codex.app`

Bundle identifiers were measured from the installed application bundles:

- `mdls -name kMDItemCFBundleIdentifier /Applications/Codex.app` ->
  `com.openai.codex`
- `mdls -name kMDItemCFBundleIdentifier /Applications/Claude.app` ->
  `com.anthropic.claudefordesktop`

The sandboxed `mdls` invocation reported the existing paths as not found, so the
same `mdls` commands were rerun outside the sandbox. `plutil -extract
CFBundleIdentifier raw .../Contents/Info.plist` returned the same identifiers.

ScreenCaptureKit window enumeration was probed with a temporary Swift snippet
under `tools/` that only called `SCShareableContent` and logged
`SCWindow.owningApplication.bundleIdentifier`; it did not capture images, run
Vision OCR, save screenshots, send messages, or update the GUI. The temporary
probe file was not retained in the repository. The snippet was compiled with:

- `swiftc -module-cache-path .build/module-cache -o
  .build/scshareable-window-list tools/scshareable-window-list.swift`

In this command execution context, `CGPreflightScreenCaptureAccess()` returned
`false`, and the probe printed:

- `screenCaptureAccess=false`
- `SCShareableContent enumeration skipped: Screen Recording permission is not
  granted for this executable context.`

An earlier run without the preflight check produced no output and was stopped,
which is consistent with a Screen Recording permission or TCC wait in this
context. Because Screen Recording permission was not granted here,
`SCShareableContent` has not yet confirmed live Codex or Claude windows by
bundle identifier on this machine. Phase 3 must keep an explicit permission
preflight path and rerun window enumeration after Screen Recording is granted to
the executable context that performs OCR.

As a fallback candidate only, a `CGWindowListCopyWindowInfo` plus
`NSRunningApplication(processIdentifier:)` probe was also compiled and run
without capture. In this same command execution context it returned
`totalOnScreenWindowCount=0`, so it did not confirm Codex or Claude windows.
If ScreenCaptureKit cannot identify windows by
`owningApplication.bundleIdentifier` after permission is granted, the next
fallback to evaluate is process-id mapping from ScreenCaptureKit or
CoreGraphics window metadata to `NSRunningApplication`, then filtering by the
measured bundle identifiers above.

## Phase 4 Wakeup Preconditions

These values were measured on this machine on 2026-06-02 before implementing
any wake-up automation. They are implementation preconditions, not a shipped
wake-up feature.

Claude URL scheme registration:

- `plutil -p /Applications/Claude.app/Contents/Info.plist | rg -n -C 8
  "CFBundleURLTypes|CFBundleURLSchemes|claude|CFBundleIdentifier"` confirmed
  `CFBundleIdentifier = "com.anthropic.claudefordesktop"` and
  `CFBundleURLSchemes = ["claude"]`.
- Launch Services also reported Claude as a handler for `claude:` through
  `lsregister -dump | rg -n -C 4
  "bindings:.*claude:|scheme: claude|claude://|com\\.anthropic\\.claudefordesktop|Claude\\.app"`.

Claude prompt injection:

- The tested command was
  `/usr/bin/open 'claude://code/new?q=ping%20from%20duet%20wakeup%20test'`.
- After opening Claude and recapturing the screen, the text
  `ping from duet wakeup test` was present in the Claude Code input field.
- It was not submitted automatically. The prompt remained a draft in the input
  field, and no assistant response or running state appeared.
- Therefore Phase 4 must treat Claude URL prompt injection as input-only on this
  machine and must use an explicit Return/Enter completion step if it needs to
  submit the prompt.
- No Accessibility or Automation permission prompt appeared for opening the
  `claude://` URL itself.
- The exact tested URL form is `claude://code/new?q=<url-encoded-prompt>`.
  Continuing an existing Claude Code session through a session-specific
  `claude://` URL was not confirmed and must remain unknown until separately
  measured or documented.

Codex AppleScript prompt injection:

- `osascript -e 'tell application "Codex" to activate' -e 'delay 1' -e
  'tell application "System Events" to keystroke "ping from duet wakeup test"'`
  activated Codex and typed into the active chat input field.
- It did not submit automatically. The send arrow remained available, so
  Return/Enter or an equivalent send action is required to submit.
- In this Japanese input-source environment, direct `keystroke` text was
  transformed by IME candidate handling and did not reliably preserve the exact
  ASCII prompt. Phase 4 should not rely on direct text keystrokes for exact
  prompt injection without first controlling the input source or using a
  separately verified paste path.
- `swift -e 'import ApplicationServices; print(AXIsProcessTrusted())'`
  returned `true` in this command execution context, and the AppleScript command
  succeeded without a new TCC prompt. Denied Accessibility or Automation
  behavior was not measured and remains unknown.
- A later `ping from duet wakeup test` shown as a sent Codex message followed
  user interaction during the experiment interruption, so it is not evidence
  that AppleScript injection alone submits the prompt.

## Not Yet Complete

These are intentionally outside the shipped Phase 1-2 implementation:

- ScreenCaptureKit + Vision OCR insurance layer
- wake-up automation for stalled agents
- session rollover
- worktree orchestration
- fully automated free-dialogue game flows

They should be implemented in small reviewed phases and must preserve the hard rules above.
