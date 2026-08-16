# Changelog

All notable changes to this project are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Fixed

- **`await_reply` could silently collapse its hold to `noProgressHoldSec`.**
  The hold decision tested the MCP progress token for truthiness, but a progress
  token is `string | number`, so `0` is a valid token. The 2026-07-28 SDK client
  numbers progress tokens from `0`, which meant a configured 180-second hold
  became 50 seconds — agents dropped out of the waiting loop far more often than
  intended. The check now tests for presence. Covered by a regression test that
  sends `_meta.progressToken = 0` directly, so it does not depend on how any
  client numbers its tokens.
- **Both agents were reported as stalled on every fresh launch.** Stall
  detection did not distinguish "silent" from "never connected", so 120 seconds
  after startup Duet warned about agents the user had not wired up yet. An agent
  that has never reached the hub is now reported absent, not stalled.

### Added

- Dual protocol-era support: the hub serves both the 2026-07-28 MCP revision and
  the 2025-era protocol from the same endpoints. Verified by tests that connect a
  2025-era client and a client pinned to `2026-07-28` and assert a message
  crosses between them on one bus.
- Agent presence tracking (`hub/src/presence.ts`) and a `presence` control
  event, distinguishing "never connected" from "connected" from "gone quiet".
  Presence is evaluated while the room is stopped, so setup can be verified
  before pressing Start.
- Read-only Git status (`hub/src/git.ts`) and a `repo` control event: branch,
  short HEAD, ahead/behind, and changed files with line counts. This replaces a
  hardcoded `"local"` branch label that had never shown real data.
- Append-only session history (`hub/src/store.ts`) as JSONL under
  `~/Library/Application Support/Duet`, with an index, Markdown export, and the
  `listSessions` / `newSession` / `loadSession` control commands. History
  disables itself with a reported reason if the data directory is unwritable,
  rather than preventing the hub from starting.
- `refreshRepo` control command.
- `npm run license:generate`, which regenerates `THIRD_PARTY_LICENSES.md` from
  the lockfile so the inventory cannot drift by hand-editing.
- `docs/DESIGN.md`, recording the interface principles and what they replaced.
- `README.ja.md`: the README is now one document per language instead of
  alternating paragraphs.

### Changed

- Hub migrated from `@modelcontextprotocol/sdk` v1 to `@modelcontextprotocol/server` v2.
  Because 2026-07-28 removed protocol sessions, all session plumbing is gone:
  `hub/src/server.ts` dropped the transport map, session-id routing, idle
  transport pruning, and the initialize-request branch.
- Production dependency advisories went from 10 (7 high, 1 moderate, 2 low) to 2
  low. The remaining two are pre-existing, via `express` → `body-parser`.
- The Node adapter is local (`hub/src/nodeHttpBridge.ts`) rather than
  `@modelcontextprotocol/node`, which depends on `@hono/node-server` and pulled
  Hono — an entire web framework Duet does not use, and its advisory stream —
  into production dependencies.
- Session transcripts are written synchronously. A buffered stream lost the last
  messages exactly when Duet.app terminated the hub.
- CI gates `npm audit` at `--audit-level=high` and reports the full advisory list
  separately. The previous unfiltered step failed on any advisory in any
  transitive dependency and was therefore permanently red.
- CI runs the hub suite on Node 22 and 24.
- Minimum Node is 22 (was 20, though 22 was already what CI tested).
- `docs/SPEC.md` rewritten against the current implementation; machine
  measurements moved to `docs/MEASUREMENTS.md`.
- `redactControlEvent` now switches exhaustively with no `default`, so adding a
  control event fails the build until its redaction is decided.

### Removed

- `docs/BUILD_PROMPTS.md`, a historical prompt log that documented itself as
  superseded.
- Config keys `maxTransports` and `idleTransportTtlSec`. They are still accepted
  and ignored with a warning, since they shipped in the example config, but they
  no longer mean anything: there are no long-lived transports to cap.
