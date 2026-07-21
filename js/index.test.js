import { describe, expect, test } from "bun:test";
import {
  clickElement,
  dragElement,
  resolveElement,
  waitForGodotEvent,
} from "./index.js";

class FakeWindow extends EventTarget {
  listenerCount = 0;

  addEventListener(type, listener, options) {
    if (type === "godot-event") this.listenerCount += 1;
    super.addEventListener(type, listener, options);
  }

  removeEventListener(type, listener, options) {
    if (type === "godot-event") this.listenerCount -= 1;
    super.removeEventListener(type, listener, options);
  }

  emit(event, data = {}) {
    this.dispatchEvent(new CustomEvent("godot-event", {
      detail: { event, timestamp: Date.now(), data },
    }));
  }
}

class FakeMouse {
  moves = [];
  downs = 0;
  ups = 0;
  onMove;
  onUp;

  async move(x, y, options) {
    this.moves.push({ x, y, options });
    await this.onMove?.(x, y, options, this.moves.length);
  }

  async down() {
    this.downs += 1;
  }

  async up() {
    this.ups += 1;
    await this.onUp?.(this.ups);
  }
}

class FakePage {
  constructor({ elements, viewport, rect }) {
    this.window = new FakeWindow();
    this.window.godotElements = elements;
    this.window.godotElementsViewport = viewport;
    this.document = {
      querySelector: (selector) => selector === "canvas"
        ? { getBoundingClientRect: () => ({ ...rect }) }
        : null,
    };
    this.mouse = new FakeMouse();
  }

  async evaluate(callback, argument) {
    globalThis.window = this.window;
    globalThis.document = this.document;
    return callback(argument);
  }
}

function makePage() {
  return new FakePage({
    elements: {
      button: { x: 100, y: 50, w: 20, h: 10, visible: true },
      target: { x: 150, y: 75, w: 20, h: 10, visible: true },
    },
    viewport: { width: 200, height: 100 },
    rect: { x: 10, y: 20, width: 400, height: 200 },
  });
}

describe("resolveElement", () => {
  test("scales current viewport coordinates into page canvas coordinates", async () => {
    const page = makePage();

    expect(await resolveElement(page, "button")).toEqual({
      key: "button",
      x: 210,
      y: 120,
      w: 40,
      h: 20,
      visible: true,
    });
  });

  test("requires visibility unless forced", async () => {
    const page = makePage();
    page.window.godotElements.button.visible = false;

    await expect(resolveElement(page, "button")).rejects.toThrow("not visible");
    expect((await resolveElement(page, "button", { force: true })).visible).toBe(false);
  });
});

describe("events and actions", () => {
  test("waits for a fresh event and shallow-matches filter values as strings", async () => {
    const page = makePage();
    page.window.emit("ready", { round: 2 });

    const waiting = waitForGodotEvent(page, "ready", {
      filters: { round: "2" },
      timeoutMs: 50,
    });
    await Promise.resolve();
    page.window.emit("ready", { round: 2 });

    expect((await waiting).data).toEqual({ round: 2 });
    expect(page.window.listenerCount).toBe(0);
  });

  test("re-resolves a moving target on retry and confirms the successful input", async () => {
    const page = makePage();
    page.mouse.onUp = (attempt) => {
      if (attempt === 1) {
        page.window.godotElements.button.x = 125;
      } else {
        page.window.emit("button_pressed", { attempt });
      }
    };

    const result = await clickElement(page, "button", {
      confirm: {
        eventName: "button_pressed",
        filters: { attempt: "2" },
        timeoutMs: 5,
      },
      retries: 1,
    });

    expect(page.mouse.moves).toEqual([
      { x: 210, y: 120, options: undefined },
      { x: 260, y: 120, options: undefined },
    ]);
    expect(result.element.x).toBe(260);
    expect(result.event.data).toEqual({ attempt: 2 });
    expect(page.window.listenerCount).toBe(0);
  });

  test("releases the mouse and cancels confirmation when a drag fails", async () => {
    const page = makePage();
    page.mouse.onMove = (_x, _y, _options, moveNumber) => {
      if (moveNumber === 2) throw new Error("drag interrupted");
    };

    await expect(dragElement(page, "button", {
      toKey: "target",
      confirm: "dragged",
    })).rejects.toThrow("drag interrupted");

    expect(page.mouse.downs).toBe(1);
    expect(page.mouse.ups).toBe(1);
    expect(page.window.listenerCount).toBe(0);
    expect(page.window.__gdPlaywrightEventWaiters).toBeUndefined();
  });
});
