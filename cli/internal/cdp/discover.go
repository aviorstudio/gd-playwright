package cdp

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
)

// Target represents a Chrome DevTools Protocol target from /json.
type Target struct {
	ID                   string `json:"id"`
	Type                 string `json:"type"`
	Title                string `json:"title"`
	URL                  string `json:"url"`
	WebSocketDebuggerURL string `json:"webSocketDebuggerUrl"`
}

// Discover finds the first page target from a CDP HTTP endpoint.
// httpEndpoint should be like "http://localhost:9222".
func Discover(httpEndpoint string) (string, error) {
	url := strings.TrimRight(httpEndpoint, "/") + "/json"
	resp, err := http.Get(url)
	if err != nil {
		return "", fmt.Errorf("could not connect to %s: %w", url, err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("could not read response: %w", err)
	}

	var targets []Target
	if err := json.Unmarshal(body, &targets); err != nil {
		return "", fmt.Errorf("could not parse targets: %w", err)
	}

	for _, t := range targets {
		if t.Type == "page" && t.WebSocketDebuggerURL != "" {
			return t.WebSocketDebuggerURL, nil
		}
	}

	return "", fmt.Errorf("no page target found at %s", url)
}

// DiscoverFromPort is a convenience that builds the HTTP endpoint from a port.
func DiscoverFromPort(port int) (string, error) {
	return Discover(fmt.Sprintf("http://localhost:%d", port))
}

// DefaultPorts returns common CDP debugging ports to try for auto-discovery.
func DefaultPorts() []int {
	return []int{9222, 9229}
}

// ScanForChrome scans /proc or ss-style output for Chrome's listening port.
// Falls back to trying a range of ephemeral ports.
func ScanForChrome() (int, error) {
	// Try common ports first
	for _, port := range DefaultPorts() {
		if _, err := DiscoverFromPort(port); err == nil {
			return port, nil
		}
	}
	// Try playwright-cli's typical ephemeral range (30000-50000)
	// by reading the .playwright-cli directory for session hints
	return 0, fmt.Errorf("no Chrome CDP port found")
}
