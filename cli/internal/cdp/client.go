package cdp

import (
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// Client is a CDP websocket client for evaluating JS in a browser page.
type Client struct {
	conn *websocket.Conn
	mu   sync.Mutex
	id   int
}

// cdpRequest is the JSON-RPC request sent over CDP.
type cdpRequest struct {
	ID     int            `json:"id"`
	Method string         `json:"method"`
	Params map[string]any `json:"params"`
}

// cdpResponse is the JSON-RPC response received from CDP.
type cdpResponse struct {
	ID     int `json:"id"`
	Result struct {
		Result struct {
			Type  string          `json:"type"`
			Value json.RawMessage `json:"value"`
		} `json:"result"`
		ExceptionDetails *struct {
			Text string `json:"text"`
		} `json:"exceptionDetails"`
	} `json:"result"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error"`
}

// Connect opens a CDP websocket connection to the given debugger URL.
func Connect(wsURL string) (*Client, error) {
	conn, _, err := websocket.DefaultDialer.Dial(wsURL, nil)
	if err != nil {
		return nil, fmt.Errorf("could not connect to %s: %w", wsURL, err)
	}
	return &Client{conn: conn}, nil
}

// ConnectFromPort prefers the page exposing gd-playwright state. It falls back
// to the first page so status can still report that a loading game is not ready.
func ConnectFromPort(port int) (*Client, error) {
	targets, err := DiscoverTargets(fmt.Sprintf("http://localhost:%d", port))
	if err != nil {
		return nil, err
	}
	if client := connectMatchingTarget(targets); client != nil {
		return client, nil
	}
	for _, target := range targets {
		if target.Type == "page" && target.WebSocketDebuggerURL != "" {
			return Connect(target.WebSocketDebuggerURL)
		}
	}
	return nil, fmt.Errorf("no page target found on port %d", port)
}

// AutoConnect checks default and process-discovered CDP ports, returning the
// page that actually exposes gd-playwright state.
func AutoConnect() (*Client, error) {
	ports := CandidatePorts()
	const readinessAttempts = 30
	for attempt := 0; attempt < readinessAttempts; attempt++ {
		waitingForPage := false
		for _, port := range ports {
			targets, err := DiscoverTargets(fmt.Sprintf("http://localhost:%d", port))
			if err != nil {
				continue
			}
			if client := connectMatchingTarget(targets); client != nil {
				return client, nil
			}
			// Candidate ports are newest-first. Give the newest live browser time
			// to finish loading Godot before considering an older session.
			if hasPageTarget(targets) {
				waitingForPage = true
				break
			}
		}
		if !waitingForPage {
			break
		}
		if attempt < readinessAttempts-1 {
			time.Sleep(100 * time.Millisecond)
		}
	}

	// If the newest browser was unrelated, look for a ready game in older
	// sessions before reporting failure.
	for _, port := range ports {
		targets, err := DiscoverTargets(fmt.Sprintf("http://localhost:%d", port))
		if err == nil {
			if client := connectMatchingTarget(targets); client != nil {
				return client, nil
			}
		}
	}
	return nil, fmt.Errorf("could not auto-discover a gd-playwright page on ports %v", ports)
}

func hasPageTarget(targets []Target) bool {
	for _, target := range targets {
		if target.Type == "page" && target.WebSocketDebuggerURL != "" {
			return true
		}
	}
	return false
}

func connectMatchingTarget(targets []Target) *Client {
	for _, target := range targets {
		if target.Type != "page" || target.WebSocketDebuggerURL == "" {
			continue
		}
		client, err := Connect(target.WebSocketDebuggerURL)
		if err != nil {
			continue
		}
		var ready bool
		err = client.EvaluateJSON(`window.godotElements != null || window.godotEvents != null || window.godotTestState != null`, &ready)
		if err == nil && ready {
			return client
		}
		client.Close()
	}
	return nil
}

// Evaluate runs a JavaScript expression in the page and returns the raw JSON result.
func (c *Client) Evaluate(js string) (json.RawMessage, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.id++
	req := cdpRequest{
		ID:     c.id,
		Method: "Runtime.evaluate",
		Params: map[string]any{
			"expression":    js,
			"returnByValue": true,
		},
	}

	if err := c.conn.WriteJSON(req); err != nil {
		return nil, fmt.Errorf("failed to send evaluate request: %w", err)
	}

	// Read responses until we get the one matching our request ID.
	for {
		_, msg, err := c.conn.ReadMessage()
		if err != nil {
			return nil, fmt.Errorf("failed to read response: %w", err)
		}

		var resp cdpResponse
		if err := json.Unmarshal(msg, &resp); err != nil {
			continue // skip non-JSON or event messages
		}

		if resp.ID != c.id {
			continue // skip events and responses for other requests
		}

		if resp.Error != nil {
			return nil, fmt.Errorf("CDP error: %s", resp.Error.Message)
		}

		if resp.Result.ExceptionDetails != nil {
			return nil, fmt.Errorf("JS exception: %s", resp.Result.ExceptionDetails.Text)
		}

		return resp.Result.Result.Value, nil
	}
}

// EvaluateJSON runs a JS expression and unmarshals the result into dst.
func (c *Client) EvaluateJSON(js string, dst any) error {
	raw, err := c.Evaluate(js)
	if err != nil {
		return err
	}
	if len(raw) == 0 || string(raw) == "null" {
		return fmt.Errorf("expression returned null")
	}
	return json.Unmarshal(raw, dst)
}

// Close closes the CDP websocket connection.
func (c *Client) Close() error {
	return c.conn.Close()
}
