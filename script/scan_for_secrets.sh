#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

matches="$(
  git grep -nE \
    -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' \
    -e '\bsk-[A-Za-z0-9_-]{40,}\b' \
    -e '\bgh[pousr]_[A-Za-z0-9_]{30,}\b' \
    -e '\bxox[baprs]-[A-Za-z0-9-]{30,}\b' \
    -e '\b(api[_-]?key|access[_-]?token|auth[_-]?token|password|secret)\s*[:=]\s*["'\'']?[A-Za-z0-9_./+=-]{32,}' \
    -- \
    ':!hub/package-lock.json' \
    ':!THIRD_PARTY_LICENSES.md' \
    ':!NOTICE' || true
)"

if [[ -n "$matches" ]]; then
  echo "Potential secrets found:" >&2
  echo "$matches" >&2
  exit 1
fi

echo "No high-confidence secret patterns found."
