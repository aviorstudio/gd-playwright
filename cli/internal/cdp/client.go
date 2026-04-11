package cdp

import (
	"encoding/json"
	"fmt"
	"sync"

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

// ConnectFromPort discovers the page target and connects via CDP.
func ConnectFromPort(port int) (*Client, error) {
	wsURL, err := DiscoverFromPort(port)
	if err != nil {
		return nil, err
	}
	return Connect(wsURL)
}

// AutoConnect tries default CDP ports and returns the first successful connection.
func AutoConnect() (*Client, error) {
	for _, port := range DefaultPorts() {
		wsURL, err := DiscoverFromPort(port)
		if err != nil {
			continue
		}
		client, err := Connect(wsURL)
		if err != nil {
			continue
		}
		return client, nil
	}
	return nil, fmt.Errorf("could not auto-discover browser on ports %v", DefaultPorts())
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
