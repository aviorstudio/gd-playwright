---
name: godot-game
description: Query and interact with a Godot web game using gdpw alongside playwright-cli. Use when testing, automating, or playing a Godot game in a browser.
---

# Godot Game Interaction with gdpw

`gdpw` is a read-only CLI that connects to a browser running a Godot web game via CDP.
It queries element positions and game events emitted by the gd-playwright addon.
Use it alongside `playwright-cli` — gdpw provides coordinates, playwright-cli performs actions.

## Prerequisites

- A Godot web game running in a browser (via `playwright-cli open <url> --headed`)
- The game must have the gd-playwright emitter addon enabled
- `gdpw` binary on PATH
- `GDPW_PORT` set to the browser's CDP port

## Setup

```bash
# Start the game in a browser
playwright-cli open http://localhost:3000 --headed

# Find the Chrome CDP port and export it
export GDPW_PORT=$(ss -tlnp | grep chrome | grep -oP ':\K[0-9]+')

# Verify connection
gdpw status
```

## Discovering Elements

The game registers interactive elements (buttons, tiles, units, cards) with string keys.

```bash
gdpw list                    # all element keys
gdpw list --visible          # only visible elements
gdpw list --filter=tile_     # keys matching a prefix
```

## Clicking Elements

Get an element's center coordinates, then click with playwright-cli:

```bash
# Get coordinates
gdpw get my_button           # → 360 640

# Click via playwright-cli
playwright-cli mousemove 360 640
playwright-cli mousedown
playwright-cli mouseup
```

For multiple elements in one call:
```bash
gdpw get element_a element_b element_c
# element_a 360 640
# element_b 480 720
# element_c 200 300
```

To output ready-to-paste playwright-cli commands:
```bash
gdpw get my_button --script
# playwright-cli mousemove 360 640
# playwright-cli mousedown
# playwright-cli mouseup
```

## Reading Game Events

The game emits events (route changes, state updates, user actions) to a browser buffer.

```bash
gdpw events                          # last 100 events
gdpw events --last=5                  # last 5
gdpw events --name=route_loaded       # filter by name
gdpw events --filter="key=value"      # filter by event data
```

## Waiting for Events

`wait` blocks until a NEW event matching the name appears (default: only events after the command starts).

```bash
gdpw wait route_loaded                        # wait for next route_loaded
gdpw wait level_complete --timeout=30000      # with custom timeout
gdpw wait score_updated --filter="score=100"  # with data filter
gdpw wait route_loaded --include-past         # also match existing events
```

## Streaming Events

Watch events in real-time:

```bash
gdpw watch                            # all events
gdpw watch --name=player_moved        # filtered
gdpw watch --quiet                    # names only
```

## Checking State

Get a snapshot of gd-playwright state (elements, viewport, latest events by type):

```bash
gdpw state
```

## Common Patterns

### Navigate → Wait → Act → Confirm

```bash
# Click a button
gdpw get menu_button                  # get coordinates
playwright-cli mousemove 360 640 && playwright-cli mousedown && playwright-cli mouseup

# Wait for navigation
gdpw wait route_loaded

# See what's available now
gdpw list --visible

# Click next element
gdpw get next_button
playwright-cli mousemove 480 720 && playwright-cli mousedown && playwright-cli mouseup
```

### Select → Move (for tile/board games)

```bash
# Click a unit/piece to select it
gdpw get element_at_pos
playwright-cli mousemove X Y && playwright-cli mousedown && playwright-cli mouseup

# Wait for selection event
gdpw wait element_selected

# Check available actions from the event data

# Click destination
gdpw get target_tile
playwright-cli mousemove X Y && playwright-cli mousedown && playwright-cli mouseup

# Confirm action
gdpw wait action_confirmed
```

### Take Screenshots

```bash
playwright-cli screenshot --filename=current-state.png
```

## Key Principles

1. **gdpw is read-only** — it never modifies browser state or calls playwright-cli
2. **All coordinates are center-point** — elements report their center, ideal for clicking
3. **`wait` defaults to fresh events** — only matches events after the command starts
4. **Invisible elements are skipped** — `get` errors on invisible elements unless `--force` is used
5. **Use `--filter` for precision** — match specific event data fields with `key=value` pairs

## Available Commands

| Command | Purpose |
|---|---|
| `get <key>` | Canvas-scaled center coordinates |
| `list` | All registered element keys |
| `status` | Connection and state info |
| `events` | Recent game events |
| `wait <name>` | Block until a new event appears |
| `watch` | Stream events in real-time |
| `state` | Aggregated state snapshot |
