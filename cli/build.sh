#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p bin
go build -o bin/gdpw ./cmd/gdpw/

echo "Built $SCRIPT_DIR/bin/gdpw"
