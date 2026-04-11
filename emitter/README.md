# gd-playwright emitter

Game-agnostic Playwright bridge for Godot 4 web exports.

Provides three browser-side primitives for test automation and AI agent interaction:

- **Events** — `window.godotEvents` array + `godot-event` CustomEvent
- **Elements** — `window.godotElements` map of tagged UI element positions
- **Board State** — `window.godotBoardState` for arbitrary game state

All features are gated behind `_should_emit_events()` — nothing is exposed in production builds unless explicitly enabled.

- Package: `@aviorstudio/gd-playwright`
- Godot: `4.x` (tested on `4.4`)

## Install

Place this folder under `res://addons/<addon-dir>/` (for example `res://addons/@aviorstudio_gd-playwright/`).

- With `gdpm`: install/link this directory into your project's `addons/`.
- Manually: copy or symlink this directory into `res://addons/<addon-dir>/`.

## Enable

Enable the plugin (`Project Settings -> Plugins -> GD Playwright Client`) to install an autoload named `PlaywrightService`.

Alternatively, add `autoload.gd` as an autoload named `PlaywrightService`.

## Files

- `plugin.cfg` / `plugin.gd`: editor plugin that installs the `PlaywrightService` autoload.
- `autoload.gd`: autoload entrypoint (extends `src/playwright_service.gd`).
- `src/playwright_service.gd`: event emitter, element map, and board state bridge.
- `src/element_map_service.gd`: tracks tagged element positions for coordinate-free clicking.
- `src/playwright_tag_node.gd`: auto-attaches to nodes with `set_meta("playwright", "key")` and polls their position.

## Events

Emit an event from Godot (web exports only):

```gdscript
PlaywrightService.emit_event("route_loaded", {"route": "home"})
```

Events are appended to `window.godotEvents` and dispatched as `CustomEvent('godot-event')`:

```json
{ "event": "route_loaded", "timestamp": 123456, "data": { "route": "home" } }
```

## Element Map

Tag any Control or Node2D with a playwright key:

```gdscript
button.set_meta("playwright", "start_button")
```

Call `PlaywrightService.scan_scene()` to discover tagged nodes. Their center positions are pushed to `window.godotElements`:

```json
{
  "start_button": { "x": 360, "y": 800, "w": 280, "h": 72, "visible": true }
}
```

Coordinates are center-point in Godot viewport space. The companion CLI (`gdpw`) scales these to canvas pixel space.

For dynamically created elements (units, cards), register programmatically:

```gdscript
var element_map = PlaywrightService.get_element_map()
if element_map:
    element_map.register("unit_0", center_pos, size, true)
```

`get_element_map()` returns `null` when the service is disabled, so callers don't need their own gate checks.

## Board State

Push arbitrary game state for CLI consumption:

```gdscript
PlaywrightService.set_board_state({"turn": 4, "units": {...}})
```

This sets `window.godotBoardState` in the browser. The data shape is entirely game-specific — the emitter just ferries the dictionary to the browser as JSON.

Clear it with `PlaywrightService.clear_board_state()`.

## Configuration

Project settings (prefix: `gd_playwright/`):

| Setting | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | `false` | Force-enable event emission |
| `test_mode` | bool | `false` | Enable emission + element map in non-debug builds |
| `log_events` | bool | `true` | Log emitted events via `console.log` |
| `event_buffer_max` | int | `1000` | Max events in `window.godotEvents` (0 = no limit) |
| `event_buffer_trim` | int | `500` | Events kept after trim (0 = no trim) |

## Security / Gating

All features are gated behind `_should_emit_events()`, which returns `true` only when:

1. Running a web build (`OS.has_feature("web")`)
2. **AND** one of: `test_mode` is on, `enabled` is on, or `OS.is_debug_build()`

In production web builds with `test_mode=false` and `enabled=false`:
- No events are emitted
- `get_element_map()` returns `null`
- `set_board_state()` is a no-op
- `scan_scene()` is a no-op
- No tag nodes are created
- No JS globals are set

Game code can safely call any of these methods without guarding — they no-op when disabled.

## Notes

- This addon is intentionally game-agnostic. Keep game-specific test helpers in your game project.
- Use the companion CLI (`gdpw`) to query elements and events from the terminal.
- The element map uses center-point coordinates, not top-left.
