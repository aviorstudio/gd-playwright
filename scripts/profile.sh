#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export GODOT_BIN="$PWD/.artifacts/godot/bin/godot"
export XDG_DATA_HOME="$PWD/.artifacts/godot-data"
export PLAYWRIGHT_BROWSERS_PATH="$PWD/.artifacts/playwright"
export PLAYWRIGHT_CLI_BIN="$PWD/scripts/playwright-cli.sh"
export GD_WEB_OUTPUT_DIR="$PWD/dist/web-export-evidence"
case "${1:-}" in
install)
    mkdir -p .artifacts
    touch .artifacts/.gdignore
    test -s "$XDG_DATA_HOME/godot/export_templates/4.7.2.stable/web_release.zip"
    (cd cli && go mod download)
    npm ci --prefix tools/browser --no-audit --no-fund
    browser_args=(install chromium)
    if [[ "${CI:-false}" == true ]]; then browser_args+=(--with-deps); fi
    tools/browser/node_modules/.bin/playwright "${browser_args[@]}"
    test "$("$PLAYWRIGHT_CLI_BIN" --version)" = 0.1.18
    node -e 'const fs = require("node:fs"); const {chromium} = require("./tools/browser/node_modules/playwright"); fs.writeFileSync(".artifacts/browser-config.json", JSON.stringify({browser:{browserName:"chromium",launchOptions:{executablePath:chromium.executablePath(),headless:true,chromiumSandbox:process.getuid() !== 0}}}));'
    ;;
lint)
    test -s cli/go.mod
    test -n "$(find cli -name '*_test.go' -type f -print -quit)"
    test -s js/index.test.js
    test -s gd/package-manifest.txt
    test -n "$(find gd/tests -name '*_test.gd' -type f -print -quit)"
    formatting="$(gofmt -l cli)"
    if [[ -n "$formatting" ]]; then printf '%s\n' "$formatting"; exit 1; fi
    (cd cli && go vet ./...)
    actionlint
    shellcheck scripts/profile.sh scripts/playwright-cli.sh
    ;;
test)
    PYTHONPATH=tools python3 -m unittest -v tools/package_gd_test.py
    bash gd/tests/test_runner_test.sh
    (cd cli && go test -race -count=1 ./...)
    (cd js && bun test)
    bash gd/tests/test.sh
    ;;
build)
    mkdir -p dist .artifacts/bin
    python3 tools/package_gd.py
    python3 tools/verify_gd_package.py dist/@aviorstudio_gd-playwright.zip | tee dist/gd-package-digests.txt
    (cd cli && go build -o ../.artifacts/bin/gdpw ./cmd/gdpw)
    ;;
artifact-check)
    bash gd/tests/package_lifecycle_test.sh dist/@aviorstudio_gd-playwright.zip
    bash gd/tests/web_export_test.sh dist/@aviorstudio_gd-playwright.zip
    ;;
*) echo "usage: $0 install|lint|test|build|artifact-check" >&2; exit 2 ;;
esac
