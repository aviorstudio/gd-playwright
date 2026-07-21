package cdp

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"
)

func TestCandidatePortsIncludesEphemeralBrowserPorts(t *testing.T) {
	commandLines := []string{
		"chrome\x00--remote-debugging-port=39895\x00--user-data-dir=/tmp/profile\x00",
		"chrome --remote-debugging-port 41000 --headless",
		"chrome --remote-debugging-port=39895",
		"chrome --remote-debugging-port=invalid",
	}

	got := candidatePorts(commandLines)
	want := []int{39895, 41000, 9222, 9229}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("candidatePorts() = %v, want %v", got, want)
	}
}

func TestDiscoverPrefersFirstPageTarget(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/json" {
			http.NotFound(w, r)
			return
		}
		fmt.Fprint(w, `[
			{"id":"worker","type":"service_worker","webSocketDebuggerUrl":"ws://worker"},
			{"id":"page","type":"page","webSocketDebuggerUrl":"ws://game"}
		]`)
	}))
	defer server.Close()

	got, err := Discover(server.URL)
	if err != nil {
		t.Fatalf("Discover() error = %v", err)
	}
	if got != "ws://game" {
		t.Fatalf("Discover() = %q, want %q", got, "ws://game")
	}
}
