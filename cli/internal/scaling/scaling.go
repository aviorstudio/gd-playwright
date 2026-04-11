package scaling

import (
	"math"

	"github.com/aviorstudio/gd-playwright/cli/internal/types"
)

// ScaledPosition is a canvas-space position with integer coordinates.
type ScaledPosition struct {
	X int `json:"x"`
	Y int `json:"y"`
	W int `json:"w"`
	H int `json:"h"`
}

// Scale converts a Godot viewport element position to canvas pixel coordinates.
// This mirrors the logic in GodotElementMap.ts _getScale().
func Scale(el *types.ElementEntry, vp *types.Viewport, canvas *types.CanvasRect) ScaledPosition {
	if vp.Width == 0 || vp.Height == 0 {
		return ScaledPosition{
			X: int(math.Round(el.X)),
			Y: int(math.Round(el.Y)),
			W: int(math.Round(el.W)),
			H: int(math.Round(el.H)),
		}
	}

	scaleX := canvas.Width / vp.Width
	scaleY := canvas.Height / vp.Height

	return ScaledPosition{
		X: int(math.Round(canvas.X + el.X*scaleX)),
		Y: int(math.Round(canvas.Y + el.Y*scaleY)),
		W: int(math.Round(el.W * scaleX)),
		H: int(math.Round(el.H * scaleY)),
	}
}
