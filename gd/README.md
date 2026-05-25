# gd-playwright Godot Addon

Expose Godot web export events, element positions, and test state to Playwright.

Use this addon when browser-based tests need stable names like `start_button` instead of hardcoded screen coordinates.

## Installation

### Via gdpm

`gdpm install @aviorstudio/gd-playwright`

### Manual

Copy `addon/` into `res://addons/@aviorstudio_gd-playwright/` and enable the plugin.

## Enable

Enable `GD Playwright Client` in `Project Settings -> Plugins`.

The plugin installs an autoload named `PlaywrightService`. You can also add `autoload.gd` manually as an autoload with that name.

## Quick Start

```gdscript
const PlaywrightServiceModule = preload("res://addons/@aviorstudio_gd-playwright/src/playwright_service.gd")

func _ready() -> void:
	PlaywrightService.configure(PlaywrightServiceModule.PlaywrightConfig.new(true, true, true, 1000))
	PlaywrightService.emit_event("route_loaded", {"route": "home"})
	PlaywrightService.set_test_state("menu", {"route": "home"})
```

## Element Map

Tag any `Control` or `Node2D` with a Playwright key:

```gdscript
button.set_meta("playwright", "start_button")
PlaywrightService.scan_scene()
```

The addon writes center-point positions to `window.godotElements`:

```json
{
  "start_button": { "x": 360, "y": 800, "w": 280, "h": 72, "visible": true }
}
```

For dynamic objects, register positions manually:

```gdscript
var element_map = PlaywrightService.get_element_map()
if element_map:
	element_map.register("unit_0", center_pos, size, true)
```

## Events

```gdscript
PlaywrightService.emit_event("battle_started", {"round": 1})
```

Events are appended to `window.godotEvents` and dispatched as browser `CustomEvent("godot-event")` events.

## Test State

```gdscript
PlaywrightService.set_test_state("puzzle", {"moves": 4, "solved": false})
PlaywrightService.clear_test_state("puzzle")
```

State is exposed at `window.godotTestState.<namespace>`.

## Project Settings

Settings use the `gd_playwright/` prefix:

| Setting | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | `false` | Force-enable event emission |
| `test_mode` | bool | `false` | Enable emission and element maps in non-debug builds |
| `log_events` | bool | `true` | Log emitted events in the browser console |
| `event_buffer_max` | int | `1000` | Max events in `window.godotEvents`; `0` means no limit |
| `event_buffer_trim` | int | `500` | Events kept after trimming; `0` means no trim |

## Safety Notes

- Features only run in web builds when debug mode, `enabled`, or `test_mode` is active.
- Calls are safe to leave in game code because disabled features no-op.
- Do not expose private player data through test state or event payloads.

## Testing

`./tests/test.sh`

## License

MIT
