# gd-playwright (emitter)

Game-agnostic Playwright bridge for Godot 4 web exports.

- Package: `@aviorstudio/gd-playwright` (subdir `emitter/`)
- Godot: `4.x` (tested on `4.4`)

## Install

Place this folder under `res://addons/<addon-dir>/` (for example `res://addons/@aviorstudio_gd-playwright/`).

- With `gdpm`: install/link the `emitter/` directory into your project's `addons/`.
- Manually: copy or symlink `emitter/` into `res://addons/<addon-dir>/`.

## Enable

Enable the plugin (`Project Settings -> Plugins -> GD Playwright Client`) to install an autoload named `PlaywrightService`.

Alternatively, add `autoload.gd` as an autoload named `PlaywrightService`.

## Files

- `plugin.cfg` / `plugin.gd`: editor plugin that installs the `PlaywrightService` autoload.
- `autoload.gd`: autoload entrypoint (extends `src/playwright_service.gd`).
- `src/playwright_service.gd`: event emitter implementation.

## Usage

Emit an event from Godot (web exports only):

```gdscript
PlaywrightService.emit_event("route_loaded", {"route": "home"})
```

In the browser, the addon appends events to `window.godotEvents` and dispatches `CustomEvent('godot-event')` with the event payload.

Each event payload is shaped like:

```json
{ "event": "route_loaded", "timestamp": 123456, "data": { "route": "home" } }
```

## Configuration

Project settings (prefix: `gd_playwright/`):

- `enabled` (bool, default `false`): force-enable event emission.
- `test_mode` (bool, default `false`): emit `service_ready` on startup and enable emission in non-debug builds.
- `log_events` (bool, default `true`): log emitted events via `console.log`.
- `event_buffer_max` (int, default `1000`): maximum number of events kept in `window.godotEvents` (0 disables trimming).
- `event_buffer_trim` (int, default `500`): number of events kept after trimming (0 disables trimming).

## Notes

- The bridge no-ops when not running a web build (`OS.has_feature("web") == false`).
- This addon intentionally provides only a generic event bridge; keep game-specific test helpers in your game project, not in this plugin.
