#!/bin/bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
GODOT="${GODOT_BIN:-godot}"
FAILURES=0
LOG_DIR=$(mktemp -d)
trap 'rm -rf "$LOG_DIR"' EXIT
for test in "$SCRIPT_DIR"/*_test.gd; do
    echo "Running $(basename "$test")..."
    log="$LOG_DIR/$(basename "$test").log"
    if ! "$GODOT" --headless --path "$ROOT_DIR" --script "$test" 2>&1 | tee "$log"; then
        FAILURES=$((FAILURES + 1))
    elif grep -Eq '^(ERROR:|SCRIPT ERROR:|FAIL:)' "$log" || ! grep -q '^PASS gd-playwright ' "$log"; then
        FAILURES=$((FAILURES + 1))
    fi
done
exit $FAILURES
