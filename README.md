# gd-playwright

Playwright tooling for Godot web exports.

This repo contains the Godot addon that emits test metadata from a web export, the read-only `gdpw` CLI that queries that metadata and generates Playwright actions, and JavaScript helpers for controlling active games from a persistent Playwright process.

Use it when browser-based tests need stable names like `start_button` instead of hardcoded screen coordinates.

## Packages

- `gd/`: Godot addon that exposes browser events, element positions, viewport state, and test state.
- `cli/`: Go `gdpw` command-line helper for querying exported games through CDP.
- `js/`: dependency-free Playwright helpers for live element resolution, confirmed actions, and retries.

## Install The Godot Addon

### Via gdam

```sh
gdam install @aviorstudio/gd-playwright
```

### Manual

Copy `gd/addon/` into `res://addons/@aviorstudio_gd-playwright/` and enable `GD Playwright Client` in `Project Settings -> Plugins`.

The plugin installs an autoload named `PlaywrightService`. You can also add `autoload.gd` manually as an autoload with that name.

## Godot Quick Start

```gdscript
const PlaywrightServiceModule = preload("res://addons/@aviorstudio_gd-playwright/src/playwright_service.gd")

func _ready() -> void:
	PlaywrightService.configure(PlaywrightServiceModule.PlaywrightConfig.new(true, true, true, 1000))
	PlaywrightService.emit_event("route_loaded", {"route": "home"})
	PlaywrightService.set_test_state("menu", {"route": "home"})
```

Add a visible `PlaywrightTag` child under any `Control` or `Node2D` that tests need to click or inspect:

```text
StartButton
  PlaywrightTag
    tag_key = "start_button"
```

When the web export runs with gd-playwright enabled, the tag writes center-point positions to `window.godotElements`:

```json
{
  "start_button": { "x": 360, "y": 800, "w": 280, "h": 72, "visible": true }
}
```

If your game wraps the addon service with its own autoload, set `service_path` on the helper nodes:

```text
PlaywrightTag
  tag_key = "start_button"
  service_path = "/root/MyPlaywrightService"
```

Legacy metadata tags still work:

```gdscript
button.set_meta("playwright", "start_button")
PlaywrightService.scan_scene()
```

The editor also includes tool menu actions:

- `GD Playwright: Scan Scene For Metadata`
- `GD Playwright: Convert Metadata To Tags`

Use `PlaywrightEventEmitter` when a scene should author a named event in the Inspector:

```text
HomeScreen
  RouteLoadedEvent
    script = PlaywrightEventEmitter
    event_name = "route_loaded"
    payload = { "route": "home" }
```

Game code can call the node when the event occurs:

```gdscript
$RouteLoadedEvent.emit_playwright_event({"screen": "HomeScreen"})
```

Use `PlaywrightStatePublisher` for namespaced test-observable state:

```text
GameScreen
  GameStatePublisher
    script = PlaywrightStatePublisher
    state_namespace = "game"
```

```gdscript
$GameStatePublisher.publish({
	"level": "level_01",
	"solved": false
})
```

An installable example scene is included at:

```text
res://addons/@aviorstudio_gd-playwright/examples/app_shell/playwright_example_screen.tscn
```

For runtime-created objects, use the generic service APIs:

```gdscript
PlaywrightService.register_element("unit_0", center_pos, size, true)
PlaywrightService.unregister_element("unit_0")
PlaywrightService.emit_namespaced_event("combat", "turn_started", {"turn": 1})
PlaywrightService.set_state("combat", {"turn": 1})
```

For dynamic objects, register positions manually:

```gdscript
var element_map = PlaywrightService.get_element_map()
if element_map:
	element_map.register("unit_0", center_pos, size, true)
```

Events are appended to `window.godotEvents` and dispatched as browser `CustomEvent("godot-event")` events:

```gdscript
PlaywrightService.emit_event("battle_started", {"round": 1})
```

State is exposed at `window.godotTestState.<namespace>`:

```gdscript
PlaywrightService.set_test_state("puzzle", {"moves": 4, "solved": false})
PlaywrightService.clear_test_state("puzzle")
```

## Install The CLI

Requires Go 1.24+.

```sh
go install github.com/aviorstudio/gd-playwright/cli/cmd/gdpw@latest
```

Or build from source:

```sh
cd cli
mkdir -p bin
go build -o bin/gdpw ./cmd/gdpw/
```

Or use the helper script:

```sh
cd cli
./build.sh
```

## CLI Quick Start

```sh
# Open the game in a browser.
playwright-cli open http://localhost:3000 --headed

# See what the addon exposed. gdpw discovers playwright-cli's CDP port.
gdpw list --visible

# Get coordinates for an element.
gdpw get start_button

# Click it via playwright-cli.
playwright-cli mousemove 360 640
playwright-cli mousedown
playwright-cli mouseup

# Wait for a new event.
gdpw wait route_loaded
```

## Active Game Actions

Moving game objects should be resolved immediately before browser input. `gdpw` remains read-only: these commands print one `playwright-cli run-code` command, and Playwright performs the input when the output is executed.

```sh
# Atomic browser-local click.
gdpw get play_button --script | sh

# Retry a moving-target drag only when the expected fresh event is missing.
gdpw script drag enemy_1 \
  --to 1000,260 \
  --expect-event enemy_released \
  --filter id=1 \
  --retries 3 | sh
```

Every attempt re-reads `window.godotElements`, viewport scaling, and the canvas rectangle. Confirmation listeners are armed before input, and drag failures always attempt to release the mouse.

For sustained active-game tests, import the JavaScript helper package in a Playwright test so decisions and input stay in one process:

```js
import { dragElement } from "@aviorstudio/gd-playwright";

await dragElement(page, "enemy_1", {
  to: { x: 1000, y: 260 },
  confirm: { eventName: "enemy_released", filters: { id: 1 } },
  retries: 3,
});
```

Retries are not exactly-once delivery. Keep them disabled for non-idempotent actions unless the confirmation event uniquely identifies success.

## CLI Commands

| Command | Description |
|---|---|
| `get <key> [key2...]` | Get canvas-scaled center coordinates for elements. |
| `list` | List all registered element keys. |
| `status` | Check CDP connection and gd-playwright state. |
| `events` | Show recent game events from `window.godotEvents`. |
| `wait <event>` | Wait for a new event to appear. |
| `watch` | Stream events in real time. |
| `state` | Show aggregated state: test state, elements, viewport, and latest events by type. |
| `script click/drag` | Generate atomic Playwright actions with optional fresh-event confirmation and retries. |

`gdpw` resolves its browser connection in this order:

1. `--cdp ws://...`
2. `--port <N>`
3. `GDPW_CDP`
4. `GDPW_PORT`
5. Auto-discovery from default ports and local browser `--remote-debugging-port` process arguments

Auto-discovery checks every page target and selects the one exposing gd-playwright globals. This avoids attaching to a stale non-game tab when multiple Playwright or Chrome targets exist. Explicit `--cdp` remains available when process inspection is unavailable or the browser is remote.

## Project Settings

Settings use the `gd_playwright/` prefix:

| Setting | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | `false` | Force-enable event emission. |
| `test_mode` | bool | `false` | Enable emission and element maps in non-debug builds. |
| `log_events` | bool | `true` | Log emitted events in the browser console. |
| `event_buffer_max` | int | `1000` | Max events in `window.godotEvents`; `0` means no limit. |
| `event_buffer_trim` | int | `500` | Events kept after trimming; `0` means no trim. |

## How It Works

The Godot addon writes generic browser globals during enabled web runs:

- `window.godotElements`: element keys mapped to `{x, y, w, h, visible}` in Godot viewport space.
- `window.godotElementsViewport`: viewport information used to scale coordinates to the canvas.
- `window.godotEvents`: buffered event records emitted by game code.
- `window.godotTestState`: namespaced test state dictionaries.

`gdpw` reads those globals through CDP. It never mutates browser or game state and it never calls `playwright-cli`; it only provides data that another tool can use for input.

## Safety Notes

- Features only run in web builds when debug mode, `enabled`, or `test_mode` is active.
- Calls are safe to leave in game code because disabled features no-op.
- Do not expose private player data through test state or event payloads.
- Game-specific knowledge belongs in game docs or skills, not in `gdpw`.

## Repository Layout

- `gd/addon/`: Godot plugin source packaged for GDAM and manual installation.
- `gd/tests/`: Godot test project/scripts for addon behavior.
- `cli/`: Go `gdpw` CLI source and build scripts.
- `js/`: JavaScript Playwright helpers and tests.
- `.github/workflows/ci.yml`: runs Godot addon tests and Go CLI tests.
- `.github/workflows/release.yml`: creates addon and CLI GitHub releases.

## Versioning And Releases

This repo currently has two automated release targets:

- `gd`: uses `gd-v*` tags, verifies `gd/addon/plugin.cfg`, builds `@aviorstudio_gd-playwright.zip`, and publishes `@aviorstudio/gd-playwright` to GDAM.
- `cli`: uses `cli-v*` tags, runs Go tests, builds `gdpw` binaries for Linux, macOS, and Windows, and attaches checksums.

The implemented `js/` package does not yet have an automated release target. The release workflow is manual and must be run from `main` with a `patch`, `minor`, or `major` bump.

## Testing

Run locally with:

```sh
mise exec -- ./gd/tests/test.sh
cd cli && mise exec -- go test ./...
cd js && mise exec -- bun test
```

CI runs all three test suites.

## License

MIT
