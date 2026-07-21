# @aviorstudio/gd-playwright

Plain-JavaScript ESM helpers for driving an active Godot web game with Playwright. The package has no runtime dependencies and leaves `gdpw` read-only: browser input is sent only through `page.mouse`.

```sh
npm install @aviorstudio/gd-playwright
```

```js
import {
  clickElement,
  dragElement,
  resolveElement,
  waitForGodotEvent,
} from "@aviorstudio/gd-playwright";

const start = await resolveElement(page, "start_button");

await clickElement(page, "start_button", {
  confirm: { eventName: "route_loaded", filters: { route: "game" } },
  retries: 1,
});

await dragElement(page, "unit", {
  toKey: "destination",
  steps: 12,
  confirm: "unit_moved",
});

await waitForGodotEvent(page, "turn_started", {
  filters: { turn: 2 },
  timeoutMs: 10_000,
});
```

## API

### `resolveElement(page, key, { force = false })`

Reads `window.godotElements`, `window.godotElementsViewport`, and the canvas rectangle when called. Returns `{ key, x, y, w, h, visible }` in Playwright page coordinates. Invisible elements reject unless `force` is true.

### `waitForGodotEvent(page, eventName, { filters = {}, timeoutMs = 5000 })`

Waits only for a new `godot-event`. Filters shallow-match fields in `event.detail.data`; expected and actual values are compared with `String(value)`. The listener is removed after a match or timeout.

### `clickElement(page, key, options)`

Options are `{ force, confirm, retries = 0, retryDelayMs = 0 }`. `confirm` is an event-name string or `{ eventName, filters, timeoutMs }`. Returns `{ element, event }`, where `event` is `null` without confirmation.

### `dragElement(page, key, options)`

Provide exactly one destination: `toKey` resolves another Godot element, while `to: { x, y }` uses Playwright page coordinates. Other options are `{ force, confirm, retries = 0, retryDelayMs = 0, steps = 10 }`. Returns `{ from, to, event }`.

Confirmed actions install a fresh event listener before input. Every retry re-resolves element and canvas coordinates. Mouse release is attempted in `finally` after mouse down.

## Test

```sh
bun test
```
