#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p bin
cargo build --release --locked
cp "${CARGO_TARGET_DIR:-target}/release/gdpw" bin/gdpw

echo "Built $SCRIPT_DIR/bin/gdpw"
