# Contributing

Duet follows small, reviewable changes. Prefer clear names and straightforward control flow over clever abstractions.

## Local Checks

```bash
cd hub
npm install
npm test
```

```bash
swift build --package-path app
```

```bash
./script/build_and_run.sh --verify
```

## Rules

- Keep unrelated refactors out of feature patches.
- Do not commit `config/duet.config.json`, `config/duet.secrets.json`, secrets, real user data, or screenshots with private content.
- Validate external input with Zod on the Hub side.
- Keep the Hub bound to localhost by default.
- Do not add claims such as "audited", "certified", or "fully compliant" without evidence.
- Preserve the core design rule: code stays on disk; Duet messages are coordination only.
