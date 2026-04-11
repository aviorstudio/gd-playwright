package scaling

import (
	"testing"

	"github.com/aviorstudio/gd-playwright/cli/internal/types"
)

func TestScale_1to1(t *testing.T) {
	el := &types.ElementEntry{X: 360, Y: 800, W: 280, H: 72}
	vp := &types.Viewport{Width: 720, Height: 1280}
	canvas := &types.CanvasRect{X: 0, Y: 0, Width: 720, Height: 1280}

	got := Scale(el, vp, canvas)

	if got.X != 360 || got.Y != 800 {
		t.Errorf("expected 360,800 got %d,%d", got.X, got.Y)
	}
	if got.W != 280 || got.H != 72 {
		t.Errorf("expected 280x72 got %dx%d", got.W, got.H)
	}
}

func TestScale_HalfSize(t *testing.T) {
	el := &types.ElementEntry{X: 360, Y: 800, W: 280, H: 72}
	vp := &types.Viewport{Width: 720, Height: 1280}
	canvas := &types.CanvasRect{X: 0, Y: 0, Width: 360, Height: 640}

	got := Scale(el, vp, canvas)

	if got.X != 180 || got.Y != 400 {
		t.Errorf("expected 180,400 got %d,%d", got.X, got.Y)
	}
	if got.W != 140 || got.H != 36 {
		t.Errorf("expected 140x36 got %dx%d", got.W, got.H)
	}
}

func TestScale_WithOffset(t *testing.T) {
	el := &types.ElementEntry{X: 100, Y: 200, W: 50, H: 50}
	vp := &types.Viewport{Width: 720, Height: 1280}
	canvas := &types.CanvasRect{X: 10, Y: 20, Width: 720, Height: 1280}

	got := Scale(el, vp, canvas)

	if got.X != 110 || got.Y != 220 {
		t.Errorf("expected 110,220 got %d,%d", got.X, got.Y)
	}
}

func TestScale_ZeroViewport(t *testing.T) {
	el := &types.ElementEntry{X: 360, Y: 800, W: 280, H: 72}
	vp := &types.Viewport{Width: 0, Height: 0}
	canvas := &types.CanvasRect{X: 0, Y: 0, Width: 720, Height: 1280}

	got := Scale(el, vp, canvas)

	if got.X != 360 || got.Y != 800 {
		t.Errorf("expected raw passthrough 360,800 got %d,%d", got.X, got.Y)
	}
}
