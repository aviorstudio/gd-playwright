package types

// ElementEntry matches the JSON shape emitted by gd-playwright's ElementMapService.
// x/y are center coordinates in Godot viewport space.
type ElementEntry struct {
	X       float64 `json:"x"`
	Y       float64 `json:"y"`
	W       float64 `json:"w"`
	H       float64 `json:"h"`
	Visible bool    `json:"visible"`
}

// Viewport is the Godot viewport dimensions from window.godotElementsViewport.
type Viewport struct {
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

// CanvasRect is the browser canvas bounding client rect.
type CanvasRect struct {
	X      float64 `json:"x"`
	Y      float64 `json:"y"`
	Width  float64 `json:"width"`
	Height float64 `json:"height"`
}

// GodotEvent matches the JSON shape emitted by gd-playwright to window.godotEvents.
type GodotEvent struct {
	Event     string         `json:"event"`
	Timestamp int64          `json:"timestamp"`
	Data      map[string]any `json:"data"`
}

// ElementQuery is the combined result of querying element, viewport, and canvas.
type ElementQuery struct {
	Element *ElementEntry `json:"el"`
	VP      *Viewport     `json:"vp"`
	Canvas  *CanvasRect   `json:"canvas"`
}

// StatusInfo is the result of a status check.
type StatusInfo struct {
	Connected     bool `json:"connected"`
	ElementCount  int  `json:"element_count"`
	EventCount    int  `json:"event_count"`
	HasViewport   bool `json:"has_viewport"`
}
