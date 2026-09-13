#!/bin/bash
set -euo pipefail
SCRIPT_DIR="${GD_TEST_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
ROOT_DIR="${GD_TEST_PROJECT_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
GODOT="${GODOT_BIN:-godot}"
TEST_TIMEOUT_SECONDS="${GD_TEST_TIMEOUT_SECONDS:-30}"
FAILURES=0
LOG_DIR=$(mktemp -d)
trap 'rm -rf "$LOG_DIR"' EXIT
shopt -s nullglob
tests=("$SCRIPT_DIR"/*_test.gd)
if [ "${#tests[@]}" -eq 0 ]; then
    echo "FAIL: no Godot *_test.gd scripts found in $SCRIPT_DIR" >&2
    exit 1
fi
for test in "${tests[@]}"; do
    echo "Running $(basename "$test")..."
    log="$LOG_DIR/$(basename "$test").log"
    stem="$(basename "$test" .gd)"
    sentinel="PASS gd-playwright $stem"
    if ! timeout --foreground --kill-after=5s "${TEST_TIMEOUT_SECONDS}s" \
        "$GODOT" --headless --path "$ROOT_DIR" --script "$test" 2>&1 | tee "$log"; then
        FAILURES=$((FAILURES + 1))
    elif grep -Eq '(^|[[:space:]])(ERROR:|SCRIPT ERROR:|FAIL:)' "$log" \
        || [ "$(grep -Fxc "$sentinel" "$log")" -ne 1 ]; then
        FAILURES=$((FAILURES + 1))
    else
        echo "ASSERTION_REACHED $stem"
    fi
done
exit $FAILURES
