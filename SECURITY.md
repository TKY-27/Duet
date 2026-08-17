# Security Policy

Duet is local developer tooling. It still handles sensitive paths, task text, and potentially private repository names, so treat logs and config carefully.

## Supported Versions

Only the current `main` branch is supported until the first tagged release.

## Reporting a Vulnerability

Report vulnerabilities privately whenever possible.

1. If this project is hosted on GitHub and private reporting is enabled, use GitHub Security Advisories.
2. If private reporting is not enabled, open a minimal public issue asking maintainers to provide a private contact path. Do not include exploit details, tokens, private repository names, local paths, screenshots, logs, or proof-of-concept payloads.
3. If you already have a maintainer-approved private contact channel, use that channel and include reproduction steps, affected version or commit, expected impact, and any safe mitigations.

Maintainers should acknowledge private reports before asking for more detail in public. Do not request or share real credentials, customer data, private source code, or non-redacted `config/duet.secrets.json` content.

## Security Expectations

- Do not expose the Hub outside `127.0.0.1` without a reviewed authentication and threat model.
- Do not commit local config, `config/duet.secrets.json`, credentials, tokens, or real user data.
- Do not use OCR as a code transport path.
- Prefer narrow, auditable changes for authentication, permissions, process spawning, and external API integration.

## Defense-in-depth notes

- **Content-safety scanning is best-effort, not a guarantee.** The Hub rejects bus
  messages that look like source code or contain recognizable secret formats (private
  keys, AWS/GCP/GitHub/Stripe/Slack tokens, JWTs, padded base64 blobs, and `key:`-style
  assignments). These heuristics reduce accidental leakage but can be bypassed by novel
  or obfuscated formats. The real protection is architectural: agents share the repo on
  disk and exchange only natural-language coordination — never paste code or secrets into
  bus messages regardless of what the filter allows.
- **`allowNonLoopbackHost` widens the attack surface.** With it enabled the Hub accepts
  Host/Origin headers from non-loopback addresses; anyone who can reach the port and holds
  a token can drive the agents. Only enable it behind a reviewed authentication and
  network-exposure plan.
- **`allowUnsafeRepoPath` removes the repo-boundary guard.** Normally `repoPath` must be a
  Git worktree and may not be `/`, `$HOME`, the project root, or sensitive system/home
  directories. Enabling this flag lets the agents operate on arbitrary paths — only use it
  for a path you have personally vetted.
