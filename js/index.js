const DEFAULT_TIMEOUT_MS = 5_000;
const WAITER_REGISTRY = "__gdPlaywrightEventWaiters";

let nextWaiterId = 0;

export async function resolveElement(page, key, { force = false } = {}) {
  return page.evaluate(
    ({ key, force }) => {
      const element = window.godotElements?.[key];
      if (!element) {
        throw new Error(`Godot element not found: ${key}`);
      }
      if (!force && element.visible === false) {
        throw new Error(`Godot element is not visible: ${key}`);
      }

      const canvas = document.querySelector("canvas");
      if (!canvas) {
        throw new Error("Godot canvas not found");
      }

      const rect = canvas.getBoundingClientRect();
      const viewport = window.godotElementsViewport;
      const scaleX = viewport?.width > 0 ? rect.width / viewport.width : 1;
      const scaleY = viewport?.height > 0 ? rect.height / viewport.height : 1;
      const values = [element.x, element.y, element.w, element.h, rect.x, rect.y, scaleX, scaleY];
      if (!values.every(Number.isFinite)) {
        throw new Error(`Godot element has invalid coordinates: ${key}`);
      }

      return {
        key,
        x: Math.round(rect.x + element.x * scaleX),
        y: Math.round(rect.y + element.y * scaleY),
        w: Math.round(element.w * scaleX),
        h: Math.round(element.h * scaleY),
        visible: element.visible !== false,
      };
    },
    { key: String(key), force },
  );
}

export async function waitForGodotEvent(page, eventName, { filters = {}, timeoutMs = DEFAULT_TIMEOUT_MS } = {}) {
  const waiter = await armGodotEvent(page, eventName, { filters, timeoutMs });
  return waiter.wait();
}

export async function clickElement(
  page,
  key,
  { force = false, confirm, retries = 0, retryDelayMs = 0 } = {},
) {
  return retryAction(
    page,
    confirm,
    retries,
    retryDelayMs,
    async () => {
      const element = await resolveElement(page, key, { force });
      await page.mouse.move(element.x, element.y);
      try {
        await page.mouse.down();
      } finally {
        await page.mouse.up();
      }
      return { element };
    },
  );
}

export async function dragElement(
  page,
  key,
  {
    toKey,
    to,
    force = false,
    confirm,
    retries = 0,
    retryDelayMs = 0,
    steps = 10,
  } = {},
) {
  if ((toKey === undefined) === (to === undefined)) {
    throw new TypeError("Provide exactly one of toKey or to");
  }
  if (to !== undefined && (!Number.isFinite(to?.x) || !Number.isFinite(to?.y))) {
    throw new TypeError("to must contain finite x and y page coordinates");
  }
  if (!Number.isInteger(steps) || steps < 1) {
    throw new TypeError("steps must be a positive integer");
  }

  return retryAction(
    page,
    confirm,
    retries,
    retryDelayMs,
    async () => {
      const from = await resolveElement(page, key, { force });
      const target = toKey === undefined
        ? { x: to.x, y: to.y }
        : await resolveElement(page, toKey, { force });

      await page.mouse.move(from.x, from.y);
      try {
        await page.mouse.down();
        await page.mouse.move(target.x, target.y, { steps });
      } finally {
        await page.mouse.up();
      }
      return { from, to: target };
    },
  );
}

async function retryAction(page, confirm, retries, retryDelayMs, action) {
  if (!Number.isInteger(retries) || retries < 0) {
    throw new TypeError("retries must be a non-negative integer");
  }
  if (!Number.isFinite(retryDelayMs) || retryDelayMs < 0) {
    throw new TypeError("retryDelayMs must be a non-negative number");
  }

  const confirmation = normalizeConfirmation(confirm);
  let lastError;
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    let waiter;
    try {
      // Installation is awaited so the fresh listener is active before any input.
      waiter = confirmation ? await armGodotEvent(page, confirmation.eventName, confirmation) : undefined;
      const result = await action();
      const event = waiter ? await waiter.wait() : null;
      return { ...result, event };
    } catch (error) {
      lastError = error;
      await waiter?.cancel();
      if (attempt < retries && retryDelayMs > 0) {
        await new Promise((resolve) => setTimeout(resolve, retryDelayMs));
      }
    }
  }
  throw lastError;
}

function normalizeConfirmation(confirm) {
  if (confirm === undefined || confirm === false || confirm === null) {
    return null;
  }
  if (typeof confirm === "string") {
    return { eventName: confirm, filters: {}, timeoutMs: DEFAULT_TIMEOUT_MS };
  }
  if (typeof confirm !== "object" || typeof confirm.eventName !== "string") {
    throw new TypeError("confirm must be an event name or { eventName, filters, timeoutMs }");
  }
  return {
    eventName: confirm.eventName,
    filters: confirm.filters ?? {},
    timeoutMs: confirm.timeoutMs ?? DEFAULT_TIMEOUT_MS,
  };
}

async function armGodotEvent(page, eventName, { filters = {}, timeoutMs = DEFAULT_TIMEOUT_MS } = {}) {
  if (typeof eventName !== "string" || eventName.length === 0) {
    throw new TypeError("eventName must be a non-empty string");
  }
  if (filters === null || typeof filters !== "object" || Array.isArray(filters)) {
    throw new TypeError("filters must be an object");
  }
  if (!Number.isFinite(timeoutMs) || timeoutMs < 0) {
    throw new TypeError("timeoutMs must be a non-negative number");
  }

  const id = `${Date.now()}-${nextWaiterId += 1}`;
  await page.evaluate(
    ({ id, eventName, filters, timeoutMs, registryKey }) => {
      const registry = window[registryKey] ?? new Map();
      window[registryKey] = registry;

      let settled = false;
      let timer;
      let resolveResult;
      const promise = new Promise((resolve) => {
        resolveResult = resolve;
      });
      const cleanup = () => {
        window.removeEventListener("godot-event", onEvent);
        clearTimeout(timer);
      };
      const settle = (result) => {
        if (settled) return;
        settled = true;
        cleanup();
        resolveResult(result);
      };
      const onEvent = (event) => {
        const detail = event.detail;
        const data = detail?.data ?? {};
        const matches = detail?.event === eventName
          && Object.entries(filters).every(([key, expected]) => String(data[key]) === String(expected));
        if (matches) {
          settle({ ok: true, event: detail });
        }
      };

      window.addEventListener("godot-event", onEvent);
      timer = setTimeout(
        () => settle({ ok: false, message: `Timed out waiting for Godot event: ${eventName}` }),
        timeoutMs,
      );
      registry.set(id, {
        promise,
        cancel: () => settle({ ok: false, message: `Canceled Godot event wait: ${eventName}` }),
      });
    },
    { id, eventName, filters, timeoutMs, registryKey: WAITER_REGISTRY },
  );

  return {
    wait: async () => page.evaluate(
      async ({ id, registryKey }) => {
        const registry = window[registryKey];
        const waiter = registry?.get(id);
        if (!waiter) {
          throw new Error("Godot event waiter is no longer available");
        }
        const result = await waiter.promise;
        registry.delete(id);
        if (registry.size === 0) {
          delete window[registryKey];
        }
        if (!result.ok) {
          throw new Error(result.message);
        }
        return result.event;
      },
      { id, registryKey: WAITER_REGISTRY },
    ),
    cancel: async () => {
      try {
        await page.evaluate(
          ({ id, registryKey }) => {
            const registry = window[registryKey];
            const waiter = registry?.get(id);
            waiter?.cancel();
            registry?.delete(id);
            if (registry?.size === 0) {
              delete window[registryKey];
            }
          },
          { id, registryKey: WAITER_REGISTRY },
        );
      } catch {
        // A closed page has already discarded its listeners.
      }
    },
  };
}
