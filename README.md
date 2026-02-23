# gd-playwright

Playwright integration with a Godot event emitter addon.

## Installation

### Via gdpm
`gdpm install @aviorstudio/gd-playwright`

### Manual
Copy this directory into `addons/@aviorstudio_gd-playwright/` and enable the plugin.

## Quick Start

```gdscript
const PlaywrightServiceModule = preload("res://addons/@aviorstudio_gd-playwright/src/playwright_service.gd")

PlaywrightService.configure(PlaywrightServiceModule.PlaywrightConfig.new(true, true, true, "[GD_PLAYWRIGHT_EVENT]", 1000, 500))
PlaywrightService.emit_event("route_loaded", {"route": "home"})
```

## API Reference

- `PlaywrightServiceModule`: event emission utilities targeting browser `window` state.
- `PlaywrightConfig`: toggles event emission behavior, log prefix, and buffer limits.
- `listener/`: JavaScript listener/runtime placeholder.

## Configuration

No required project settings. Optional defaults are resolved from plugin runtime config.

## Testing

`./tests/test.sh`

## License

MIT
