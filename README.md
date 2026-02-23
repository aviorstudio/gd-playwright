# gd-playwright

Monorepo for Playwright integration with a Godot event emitter addon.

## Installation

### Via gdpm
`gdpm install @aviorstudio/gd-playwright`

### Manual
Copy `emitter/` into `addons/@aviorstudio_gd-playwright/` and enable the plugin.

## Quick Start

```gdscript
const PlaywrightServiceModule = preload("res://addons/@aviorstudio_gd-playwright/src/playwright_service.gd")

PlaywrightService.configure(PlaywrightServiceModule.PlaywrightConfig.new(true, true, true, 1000))
PlaywrightService.emit_event("route_loaded", {"route": "home"})
```

## API Reference

- `PlaywrightServiceModule`: event emission utilities targeting browser `window` state.
- `PlaywrightConfig`: toggles event emission behavior and buffer limits.
- `emitter/`: Godot addon implementation.
- `listener/`: JavaScript listener/runtime placeholder.

## Configuration

No required project settings. Optional defaults are resolved from plugin runtime config.

## Testing

`./run_tests.sh`

## License

MIT
