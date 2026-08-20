# Contributing

Duet favours small, reviewable changes, clear names, and straightforward
control flow over clever abstractions.

## Local checks

```bash
cd hub && npm ci && npm test && npm run smoke && npm run license:check
```

```bash
swift build --package-path app && swift test --package-path app
```

```bash
./script/build_and_run.sh --verify
```

## Rules

- Keep unrelated refactors out of feature patches.
- Do not commit `config/duet.config.json`, `config/duet.secrets.json`, secrets,
  real user data, or screenshots containing private content.
- Validate external input with Zod on the hub side, using `.strict()`.
- Keep the hub bound to loopback by default.
- Do not add claims such as "audited", "certified", or "fully compliant"
  without evidence.
- Preserve the core rule: code stays on disk; Duet messages are coordination
  only.

## Changing dependencies

Run `npm run license:generate` and commit the regenerated
`THIRD_PARTY_LICENSES.md`. Do not hand-edit it — `npm run license:check` in CI
verifies it against the lockfile.

Weigh transitive cost, not just the direct package. `@modelcontextprotocol/node`
was rejected for a 137-line local adapter because it would have pulled an entire
web framework, and that framework's advisory stream, into a tool that does not
use it.

## Changing control events

`redactControlEvent` in `hub/src/contentSafety.ts` switches exhaustively with no
`default` branch. Adding a `ControlEvent` variant will fail the build until you
decide how it is redacted. That is deliberate: decide, rather than letting a new
event ship unredacted.

## Changing the interface

Read [docs/DESIGN.md](docs/DESIGN.md) first. It records what the current design
replaced and why, so those decisions are not silently undone.

A successful build is not visual verification. After a rendered change, check
the result against: minimum and typical window sizes, light and dark appearance,
Reduce Motion, Reduce Transparency, Increase Contrast, enlarged system text,
full keyboard reachability, VoiceOver reading order, and both `ja` and `en`
locales. Every state — empty, connecting, waiting, stalled, disconnected,
sending, failed — is part of the design, not an afterthought.

## Reporting security issues

See [SECURITY.md](SECURITY.md). Do not open a public issue for a vulnerability.
