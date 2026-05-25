# gd-playwright

Playwright tooling for Godot web exports.

This is a monorepo with separate packages for the Godot addon, CLI, and JavaScript runtime helpers.

## Packages

- [`gd/`](gd/): Godot addon that exposes browser events, element positions, and test state.
- [`cli/`](cli/): `gdpw` command-line helper for querying exported games through Chrome DevTools Protocol.
- [`js/`](js/): JavaScript-side Playwright helper package.

## Quick Start

1. Install the Godot addon from [`gd/`](gd/).
2. Tag Godot nodes with `set_meta("playwright", "key")`.
3. Use [`cli/`](cli/) to list elements, read state, and wait for events from a running web export.

## Release Tags

- Godot addon: `gd-v0.0.1`
- CLI: `cli-v0.0.1`
- JavaScript package: `js-v0.0.1`

## License

MIT
