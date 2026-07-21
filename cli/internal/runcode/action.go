package runcode

import (
	"encoding/json"
	"fmt"
	"strings"
)

// Confirmation describes the fresh Godot event that acknowledges an action.
type Confirmation struct {
	Event     string            `json:"event"`
	Filters   map[string]string `json:"filters,omitempty"`
	TimeoutMS int               `json:"timeoutMs"`
}

// ActionOptions configures one browser-local click or drag operation.
type ActionOptions struct {
	Action       string        `json:"action"`
	Key          string        `json:"key"`
	ToKey        string        `json:"toKey,omitempty"`
	To           *Point        `json:"to,omitempty"`
	Force        bool          `json:"force,omitempty"`
	Confirm      *Confirmation `json:"confirm,omitempty"`
	Retries      int           `json:"retries"`
	RetryDelayMS int           `json:"retryDelayMs"`
	Steps        int           `json:"steps"`
}

// Point is a page-space Playwright mouse coordinate.
type Point struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

// RenderAction renders a self-contained playwright-cli run-code function.
func RenderAction(options ActionOptions) (string, error) {
	if options.Action != "click" && options.Action != "drag" {
		return "", fmt.Errorf("unsupported action %q", options.Action)
	}
	if strings.TrimSpace(options.Key) == "" {
		return "", fmt.Errorf("element key is required")
	}
	if options.Action == "drag" && options.ToKey == "" && options.To == nil {
		return "", fmt.Errorf("drag requires a destination key or point")
	}
	if options.Action == "drag" && options.ToKey != "" && options.To != nil {
		return "", fmt.Errorf("drag accepts only one destination")
	}
	if options.Retries < 0 {
		return "", fmt.Errorf("retries cannot be negative")
	}
	if options.Retries > 0 && options.Confirm == nil {
		return "", fmt.Errorf("retries require --expect-event confirmation")
	}
	if options.RetryDelayMS <= 0 {
		options.RetryDelayMS = 50
	}
	if options.Steps <= 0 {
		options.Steps = 6
	}
	if options.Confirm != nil && options.Confirm.TimeoutMS <= 0 {
		options.Confirm.TimeoutMS = 1000
	}

	payload, err := json.Marshal(options)
	if err != nil {
		return "", fmt.Errorf("marshal action options: %w", err)
	}
	return strings.Replace(actionTemplate, "__GDPW_OPTIONS__", string(payload), 1), nil
}

// ShellCommand wraps run-code for the documented `gdpw ... | sh` workflow.
func ShellCommand(code string) string {
	return "playwright-cli run-code " + quotePOSIX(code)
}

func quotePOSIX(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\"'\"'") + "'"
}

const actionTemplate = `async page => {
  const options = __GDPW_OPTIONS__;
  const registryName = "__gdpwActionConfirmations";

  const prepare = async attempt => page.evaluate(({ options, attempt, registryName }) => {
    const elements = window.godotElements || {};
    const viewport = window.godotElementsViewport || null;
    const canvas = document.querySelector("canvas");
    if (!canvas) throw new Error("Godot canvas not found");

    const resolve = key => {
      const element = elements[key];
      if (!element) throw new Error("gd-playwright element not found: " + key);
      if (!element.visible && !options.force) throw new Error("gd-playwright element is not visible: " + key);
      const rect = canvas.getBoundingClientRect();
      const scaleX = viewport && viewport.width ? rect.width / viewport.width : 1;
      const scaleY = viewport && viewport.height ? rect.height / viewport.height : 1;
      return {
        x: Math.round(rect.x + element.x * scaleX),
        y: Math.round(rect.y + element.y * scaleY)
      };
    };

    const from = resolve(options.key);
    const to = options.toKey ? resolve(options.toKey) : options.to || null;
    let token = null;
    if (options.confirm) {
      token = "gdpw-" + Date.now() + "-" + attempt + "-" + Math.random();
      const registry = window[registryName] = window[registryName] || {};
      const record = { event: null, listener: null };
      record.listener = browserEvent => {
        const detail = browserEvent.detail || {};
        if (detail.event !== options.confirm.event) return;
        const data = detail.data || {};
        for (const [key, expected] of Object.entries(options.confirm.filters || {})) {
          if (String(data[key]) !== expected) return;
        }
        record.event = detail;
      };
      registry[token] = record;
      window.addEventListener("godot-event", record.listener);
    }
    return { from, to, token };
  }, { options, attempt, registryName });

  const cleanup = async token => {
    if (!token) return;
    await page.evaluate(({ token, registryName }) => {
      const registry = window[registryName] || {};
      const record = registry[token];
      if (record && record.listener) window.removeEventListener("godot-event", record.listener);
      delete registry[token];
    }, { token, registryName });
  };

  const waitForConfirmation = async token => {
    if (!token) return null;
    const handle = await page.waitForFunction(
      ({ token, registryName }) => {
        const record = (window[registryName] || {})[token];
        return record && record.event ? record.event : null;
      },
      { token, registryName },
      { timeout: options.confirm.timeoutMs }
    );
    const event = await handle.jsonValue();
    await handle.dispose();
    return event;
  };

  let lastError = null;
  for (let attempt = 0; attempt <= options.retries; attempt++) {
    let prepared = null;
    let mouseDown = false;
    try {
      prepared = await prepare(attempt);
      await page.mouse.move(prepared.from.x, prepared.from.y);
      await page.mouse.down();
      mouseDown = true;
      if (options.action === "drag") {
        await page.mouse.move(prepared.to.x, prepared.to.y, { steps: options.steps });
      }
      await page.mouse.up();
      mouseDown = false;
      const event = await waitForConfirmation(prepared.token);
      return { action: options.action, key: options.key, attempt: attempt + 1, event };
    } catch (error) {
      lastError = error;
      if (mouseDown) {
        try { await page.mouse.up(); } catch (_) {}
      }
      if (attempt < options.retries) await page.waitForTimeout(options.retryDelayMs);
    } finally {
      if (prepared) await cleanup(prepared.token);
    }
  }
  const message = lastError && lastError.message ? lastError.message : String(lastError || "unknown error");
  throw new Error("gd-playwright action failed: " + message);
}`
