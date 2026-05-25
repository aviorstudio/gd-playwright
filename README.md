# gd-playwright

Monorepo for Playwright integration with a Godot event emitter addon.

## Installation

### Via gdpm
`gdpm install @aviorstudio/gd-playwright`

### Manual
Copy `gd/addon/` into `addons/@aviorstudio_gd-playwright/` and enable the plugin.

## Quick Start

```gdscript
const PlaywrightServiceModule = preload("res://addons/@aviorstudio_gd-playwright/src/playwright_service.gd")

PlaywrightService.configure(PlaywrightServiceModule.PlaywrightConfig.new(true, true, true, 1000))
PlaywrightService.emit_event("route_loaded", {"route": "home"})
PlaywrightService.set_test_state("menu", {"route": "home"})
```

## API Reference

- `PlaywrightServiceModule`: event emission utilities targeting browser `window` state.
- `PlaywrightConfig`: toggles event emission behavior and buffer limits.
- `set_test_state(namespace, state)`: exposes game-defined state at `window.godotTestState[namespace]`.
- `scan_scene()`: discovers nodes tagged with `set_meta("playwright", "key")` for coordinate-free browser tests.
- `gd/`: Godot addon package root, matching the standalone addon repo layout.
- `gd/addon/`: Godot addon implementation.
- `gd/tests/`: Godot addon tests.
- `cli/`: companion CLI for querying exported Godot web games.
- `js/`: JavaScript listener/runtime placeholder.

## Configuration

No required project settings. Optional defaults are resolved from plugin runtime config.

## Security

The emitter is intended for web test/debug builds. Do not enable test mode in production exports, and do not expose private session or player data through test state.

## Testing

`./gd/tests/test.sh`

## License

MIT
