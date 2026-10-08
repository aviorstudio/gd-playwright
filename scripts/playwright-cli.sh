#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cli="$root/tools/browser/node_modules/.bin/playwright-cli"
# Use the installed pinned Chromium for the export fixtures, not ambient Chrome.
for argument in "$@"; do
    if [[ "$argument" == open ]]; then
        exec "$cli" "$@" --config "$root/.artifacts/browser-config.json"
    fi
done
exec "$cli" "$@"
