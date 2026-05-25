# gdpw — Godot Playwright CLI

Read-only companion CLI for [playwright-cli](https://github.com/microsoft/playwright-cli). Connects to a browser running a Godot web game and queries element positions and events emitted by the [gd-playwright](../gd/addon/) emitter addon.

`gdpw` provides coordinates and game state. `playwright-cli` performs clicks and inputs. The two tools connect to the same browser independently via CDP.

## Install

Requires Go 1.24+.

```bash
go install github.com/aviorstudio/gd-playwright/cli/cmd/gdpw@latest
```

Or build from source:

```bash
cd cli
mkdir -p bin
go build -o bin/gdpw ./cmd/gdpw/
```

Or use the helper script:

```bash
cd cli
./build.sh
```

## Quick Start

```bash
# Open the game in a browser
playwright-cli open http://localhost:3000 --headed

# Find the Chrome CDP port
export GDPW_PORT=$(ss -tlnp | grep chrome | grep -oP ':\K[0-9]+')

# See what's on screen
gdpw list --visible

# Get coordinates for an element
gdpw get start_button        # → 360 640

# Click it via playwright-cli
playwright-cli mousemove 360 640
playwright-cli mousedown
playwright-cli mouseup

# Wait for a new event
gdpw wait route_loaded
```

## Commands

| Command | Description |
|---|---|
| `get <key> [key2...]` | Get canvas-scaled center coordinates for elements |
| `list` | List all registered element keys |
| `status` | Check CDP connection and gd-playwright state |
| `events` | Show recent game events from `window.godotEvents` |
| `wait <event>` | Wait for a new event to appear (polls until match or timeout) |
| `watch` | Stream events in real-time (Ctrl+C to stop) |
| `state` | Show aggregated state: elements, viewport, latest events by type |

### `get`

```bash
gdpw get start_button              # → 360 640
gdpw get hex_3_2 hex_4_3            # bulk query, one line per key
gdpw get start_button --json        # full position + size + visibility
gdpw get start_button --script      # outputs playwright-cli click commands
gdpw get invisible_el --force       # return coords even if not visible
```

- By default, errors on invisible elements (silent skip in bulk mode).
- Shows available keys in error messages when an element is not found.

### `list`

```bash
gdpw list                   # all keys, one per line
gdpw list --visible          # only visible elements
gdpw list --filter=tile_     # prefix filter
gdpw list --json             # full element map as JSON
```

### `events`

```bash
gdpw events                          # last 100 events
gdpw events --last=5                  # last 5
gdpw events --name=score_updated        # filter by event name
gdpw events --filter="key=value"     # filter by event data field
gdpw events --since=123456           # only events after timestamp
```

### `wait`

```bash
gdpw wait route_loaded                           # waits for NEW event (default)
gdpw wait level_loaded --timeout=30000           # custom timeout
gdpw wait level_loaded --filter="key=value"      # match event data
gdpw wait route_loaded --include-past            # also match existing events
```

By default, `wait` only matches events that arrive **after** the command starts. Use `--include-past` to match events already in the buffer.

### `watch`

```bash
gdpw watch                            # stream all events
gdpw watch --name=player_moved       # filter by name
gdpw watch --filter="key=value"       # filter by data
gdpw watch --quiet                    # event names only
```

### `state`

```bash
gdpw state                            # element counts, viewport, latest event per type
```

### `status`

```bash
gdpw status                           # connection, element count, event count, viewport
```

## Connection

`gdpw` connects to the browser via CDP (Chrome DevTools Protocol). Connection is resolved in this order:

1. `--cdp ws://...` flag
2. `--port <N>` flag
3. `GDPW_CDP` environment variable
4. `GDPW_PORT` environment variable
5. Auto-discovery on default ports (9222, 9229)

Set `GDPW_PORT` to avoid passing `--port` on every command:

```bash
export GDPW_PORT=36879
gdpw list             # no --port needed
```

## How It Works

`gdpw` reads two browser globals set by the gd-playwright emitter addon:

- `window.godotElements` — map of element keys to `{x, y, w, h, visible}` (center coordinates in Godot viewport space)
- `window.godotEvents` — array of `{event, timestamp, data}` objects

Coordinates are scaled from Godot viewport space to canvas pixel space using the canvas bounding rect and `window.godotElementsViewport`.

`gdpw` never modifies browser state. It never calls `playwright-cli`. It's purely read-only.

## Architecture

```
gdpw (read-only queries)          playwright-cli (browser control)
     │                                  │
     │   CDP websocket                  │
     ├──────────────────────┐           │
     │                      ▼           ▼
     │               ┌──────────────────┐
     └──────────────►│ Browser          │
                     │ ┌──────────┐     │
                     │ │ Godot    │     │
                     │ │ <canvas> │     │
                     │ │          │     │
                     │ │ window.  │     │
                     │ │ godotEl* │     │
                     │ └──────────┘     │
                     └──────────────────┘
```

## Game-Agnostic

`gdpw` knows nothing about any specific game. It reads generic element positions and events. Game-specific knowledge (menu structure, card play flow, board coordinates) belongs in SKILL files or game documentation, not in the CLI.
