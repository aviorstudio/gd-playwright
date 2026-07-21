package runcode

import (
	"strings"
	"testing"
)

func TestRenderActionEmbedsAtomicDragOptions(t *testing.T) {
	code, err := RenderAction(ActionOptions{
		Action: "drag",
		Key:    "enemy_1",
		To:     &Point{X: 1000, Y: 260},
		Confirm: &Confirmation{
			Event:     "enemy_released",
			Filters:   map[string]string{"id": "1"},
			TimeoutMS: 750,
		},
		Retries: 2,
		Steps:   8,
	})
	if err != nil {
		t.Fatalf("RenderAction() error = %v", err)
	}
	for _, expected := range []string{
		`"action":"drag"`, `"key":"enemy_1"`, `"x":1000`,
		`"event":"enemy_released"`, `"id":"1"`, `"retries":2`,
		`const prepare = async attempt => page.evaluate`,
		`window.addEventListener("godot-event"`,
		`if (mouseDown)`,
	} {
		if !strings.Contains(code, expected) {
			t.Errorf("rendered action missing %q", expected)
		}
	}
}

func TestRenderActionRequiresConfirmationForRetries(t *testing.T) {
	_, err := RenderAction(ActionOptions{Action: "click", Key: "play_button", Retries: 1})
	if err == nil {
		t.Fatal("RenderAction() should reject retries without confirmation")
	}
}

func TestRenderActionIncludesZeroRetryDefault(t *testing.T) {
	code, err := RenderAction(ActionOptions{Action: "click", Key: "play_button"})
	if err != nil {
		t.Fatalf("RenderAction() error = %v", err)
	}
	if !strings.Contains(code, `"retries":0`) {
		t.Fatal("rendered action must include the zero retry default")
	}
}

func TestShellCommandQuotesSingleQuotes(t *testing.T) {
	got := ShellCommand("async page => page.locator('canvas')")
	if !strings.Contains(got, `'"'"'canvas'"'"'`) {
		t.Fatalf("ShellCommand() did not quote embedded apostrophes: %s", got)
	}
}
