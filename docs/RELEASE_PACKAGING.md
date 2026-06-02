# Release Packaging Notes

Duet is currently ready for source-first OSS use. Binary distribution is a separate release-packaging track.

Current development bundle:

- `script/build_and_run.sh` creates `dist/Duet.app` for local development.
- The bundle is unsigned, not notarized, and expects to run from a source checkout because Hub code and local config live beside the repo.
- `--verify` launches the staged app bundle, verifies the app icon metadata, checks Hub `/health`, and connects to the control WebSocket.

Before publishing downloadable binaries:

1. Decide whether Hub JavaScript and default assets are embedded in `Duet.app` or installed beside it.
2. Add a first-run config flow that creates or selects `config/duet.config.json` without requiring a source checkout.
3. Sign the app with a Developer ID certificate.
4. Harden runtime settings and entitlements deliberately; do not add broad entitlements without a matching feature need.
5. Notarize and staple the artifact.
6. Re-run Hub tests, Swift tests, license scan, secret scan, shellcheck, Hub smoke, and a manual macOS UI pass on a clean account.

Do not describe a development bundle as signed, notarized, release-ready, audited, or hardened until those steps are actually completed.
