# gd-playwright-client

Godot-side Playwright bridge for web exports:
- Emits structured events into `window.godotEvents` and dispatches `CustomEvent('godot-event')`.
- (Optional) exposes minimal test hooks (ex: `window.testLogin(...)`) when running in test mode.

## Install

This directory is meant to be linked/copied into a Godot project's `addons/` folder (for example via `gdpm link`).

## Enable

Either:
- Enable the plugin in Godot: `Project Settings -> Plugins -> GD Playwright Client`, or
- Add `autoload.gd` as an Autoload named `PlaywrightService`.

## Notes

- The bridge no-ops when not running a web build (`OS.has_feature("web") == false`).
- Event emission is gated by `EnvService.test_mode` if an autoload named `EnvService` exists; otherwise it falls back to `OS.is_debug_build()`.
