<!-- Generated from private documentation source. Do not edit directly. Source SHA256: 3d46396eb71df9b3fb6768f2a432a6b2335ecac3c8d10f5af3122aabe7906f69 -->

# gd-playwright

Playwright tooling for Godot web exports.

This repository contains the Godot addon that emits test metadata from a web export. The [gd-playwright-cli CLI](https://github.com/aviorstudio/gd-playwright-cli) and [JavaScript helpers](https://github.com/aviorstudio/gd-playwright-js) are separate companion repositories.

Use it when browser-based tests need stable names like `start_button` instead of hardcoded screen coordinates.

## Packages

- `addon/`: Godot addon that exposes browser events, element positions, viewport state, and test state.
- [`gd-playwright-cli`](https://github.com/aviorstudio/gd-playwright-cli): Rust `gd-playwright-cli` helper for querying exported games through CDP.
- [`gd-playwright-js`](https://github.com/aviorstudio/gd-playwright-js): dependency-free Playwright helpers for live element resolution, confirmed actions, and retries.

## Install The Godot Addon

### Via gdam

```sh
gdam install @aviorstudio/gd-playwright
```

### Manual

Copy `addon/` into `res://addons/@aviorstudio_gd-playwright/` and enable `gd-playwright` in `Project Settings -> Plugins`.

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

- `gd-playwright: Scan Scene For Metadata`
- `gd-playwright: Convert Metadata To Tags`

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

Linux and macOS, x86_64 or arm64:

```sh
curl -fsSL https://raw.githubusercontent.com/aviorstudio/gd-playwright-cli/main/scripts/install.sh | sh
```

The installer selects a published `cli-v` release, verifies the archive checksum and installs `gd-playwright-cli` into `~/.local/bin`. Rust is not required to run the release binary. Use `--version` or `--install-dir` through `sh -s --` for a specific release or destination.

Build the CLI from source in [gd-playwright-cli](https://github.com/aviorstudio/gd-playwright-cli), following that repository’s README.

## CLI Quick Start

```sh
# Open the game in a browser.
playwright-cli open http://localhost:3000 --headed

# See what the addon exposed. gd-playwright-cli discovers playwright-cli's CDP port.
gd-playwright-cli list --visible

# Get coordinates for an element.
gd-playwright-cli get start_button

# Click it via playwright-cli.
playwright-cli mousemove 360 640
playwright-cli mousedown
playwright-cli mouseup

# Wait for a new event.
gd-playwright-cli wait route_loaded
```

## Active Game Actions

Moving game objects should be resolved immediately before browser input. `gd-playwright-cli` remains read-only: these commands print one `playwright-cli run-code` command, and Playwright performs the input when the output is executed.

```sh
# Atomic browser-local click.
gd-playwright-cli get play_button --script | sh

# Retry a moving-target drag only when the expected fresh event is missing.
gd-playwright-cli script drag enemy_1 \
  --to 1000,260 \
  --expect-event enemy_released \
  --filter id=1 \
  --retries 3 | sh
```

Every attempt re-reads `window.godotElements`, viewport scaling, and the canvas rectangle. Confirmation listeners are armed before input, and drag failures always attempt to release the mouse.

For sustained active-game tests, install the [JavaScript helper package](https://github.com/aviorstudio/gd-playwright-js) and import it in a Playwright test so decisions and input stay in one process:

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

`gd-playwright-cli` resolves its browser connection in this order:

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

`gd-playwright-cli` reads those globals through CDP. It never mutates browser or game state and it never calls `playwright-cli`; it only provides data that another tool can use for input.

## Safety Notes

- Debug web builds retain the existing `enabled`/`test_mode` behavior. Ordinary release exports never create gd-playwright browser globals, even when those settings are enabled.
- Production diagnostics require a separate export preset with the custom feature `gd_playwright_diagnostics`. Configure `PlaywrightConfig` with a `PlaywrightPayloadPolicy`: exact element keys and prefixes, event-name to allowed-field rules, and state-namespace to allowed-field rules. Empty or missing rules deny publication.
- Diagnostic release payloads must contain only JSON-safe values. Known credential-like keys (including `token`, `password`, `secret`, cookies, session values, API keys, and private keys) are rejected recursively. This is a bounded guard, not a confidentiality or exhaustive secret-detection guarantee; games remain responsible for publishing only non-sensitive diagnostic data.
- Validation walks each accepted payload once, handles primitive leaves without per-value frame dictionaries, and reuses repeated key classifications only for that publication. Element publication reuses internal wire views only while each entry's public fields remain unchanged; it still serializes a fresh full-map payload before publication. Enabled browser publication also reuses one fixed receiver per owner. These are internal safeguards only: publication remains synchronous, events retain order/detail, and element updates still replace the full map at the existing cadence.
- Calls are safe to leave in game code because disabled features no-op.
- Do not expose private player data through test state or event payloads.
- Game-specific knowledge belongs in game docs or skills, not in `gd-playwright-cli`.

Example diagnostic release configuration:

```gdscript
var policy := PlaywrightServiceModule.PlaywrightPayloadPolicy.new(
	PackedStringArray(["start_button"]),
	PackedStringArray(["unit_"]),
	{"route_loaded": PackedStringArray(["route"])},
	{"fixture": PackedStringArray(["route", "ready"])}
)
PlaywrightService.configure(
	PlaywrightServiceModule.PlaywrightConfig.new(true, true, false, 100, 50, policy)
)
```


## License

See `LICENSE`.

## Contributor checks

Install [mise](https://mise.jdx.dev/) and GNU Make, then run:

```sh
make setup
make build
make test
```

`mise.toml` pins SDK versions. `cookbook.toml` declares the addon package and its real tests; the generated Make entrypoint uses an exact shared cookbook revision from `nicodes/tools`. Setup installs the pinned editor, export templates and applicable dependencies. Build creates and verifies the closed addon archive; tests run source checks, native assertions, security checks and the declared packaged integration or browser checks. Packaged tests require the current verified build. Test commands do not run setup or rebuild the addon.

`make help` lists the available commands. Use `make test:lint`, `make test:unit`, `make test:integration` or `make test:security` for an individual group, `make fmt` for formatting, and `make clean` for declared generated files. Build and test evidence stays in `.artifacts/verification`.

`make test:e2e` runs the browser acceptance gate using the caller-local, locked Playwright SDK and pinned Chromium installed by `make setup`.

## Finite machine commands

Use a leading `--json` for finite queries, status, events, waiting and generated scripts, such as `gd-playwright-cli --json status` or `gd-playwright-cli --json script click menuButton`. Machine stdout contains one complete JSON document; diagnostics use stderr and failures exit nonzero. A single successful `get` keeps its coordinate object. Multi-key `get` returns one object containing `elements`, `errors` and `ok`; empty event results are `[]`.

`watch` retains its event stream and rejects `--json` before connecting. Connection selection remains explicit `--cdp`/`--port`, environment values, then local discovery. Script generation remains offline and does not execute browser input.
