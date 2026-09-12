#!/bin/bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
RUNNER="$ROOT_DIR/gd/tests/test.sh"
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
SCRIPTS="$TEMP/scripts"
mkdir -p "$SCRIPTS"

run_control() {
    name="$1"
    expected="$2"
    body="$3"
    rm -f "$SCRIPTS"/*_test.gd
    printf 'extends SceneTree\n' > "$SCRIPTS/control_test.gd"
    cat > "$TEMP/fake-godot" <<EOF
#!/bin/bash
set -euo pipefail
$body
EOF
    chmod +x "$TEMP/fake-godot"
    set +e
    output=$(GD_TEST_SCRIPT_DIR="$SCRIPTS" GD_TEST_PROJECT_DIR="$TEMP" \
        GD_TEST_TIMEOUT_SECONDS=1 GODOT_BIN="$TEMP/fake-godot" "$RUNNER" 2>&1)
    status=$?
    set -e
    if [ "$expected" = pass ] && [ "$status" -ne 0 ]; then
        printf 'control %s unexpectedly failed:\n%s\n' "$name" "$output" >&2
        exit 1
    fi
    if [ "$expected" = fail ] && [ "$status" -eq 0 ]; then
        printf 'control %s unexpectedly passed:\n%s\n' "$name" "$output" >&2
        exit 1
    fi
    printf 'CONTROL_%s %s status=%s\n' "${expected^^}" "$name" "$status"
}

run_control known_good pass 'printf "%s\n" "PASS gd-playwright control_test"'
run_control runtime_error_zero fail 'printf "%s\n" "ERROR: synthetic runtime error"; exit 0'
run_control overwritten_assertion_exit fail 'printf "%s\n" "FAIL: synthetic assertion" "PASS gd-playwright control_test"; exit 0'
run_control parse_unreachable fail 'printf "%s\n" "SCRIPT ERROR: Parse Error: synthetic"; exit 0'
run_control timeout_hang fail 'sleep 3; printf "%s\n" "PASS gd-playwright control_test"'
run_control unexpected_log_error fail 'printf "%s\n" "worker ERROR: synthetic unexpected log" "PASS gd-playwright control_test"'
run_control duplicate_sentinel fail 'printf "%s\n" "PASS gd-playwright control_test" "PASS gd-playwright control_test"'

rm -f "$SCRIPTS"/*_test.gd
set +e
missing_output=$(GD_TEST_SCRIPT_DIR="$SCRIPTS" GD_TEST_PROJECT_DIR="$TEMP" \
    GODOT_BIN="$TEMP/fake-godot" "$RUNNER" 2>&1)
missing_status=$?
set -e
if [ "$missing_status" -eq 0 ]; then
    printf 'missing-suite control unexpectedly passed:\n%s\n' "$missing_output" >&2
    exit 1
fi
printf 'CONTROL_FAIL missing_test_script status=%s\n' "$missing_status"
printf 'ASSERTION_REACHED runner_controls count=8\n'
