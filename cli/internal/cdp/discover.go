package cdp

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"
)

var discoveryHTTPClient = &http.Client{Timeout: 500 * time.Millisecond}
var remoteDebuggingPortPattern = regexp.MustCompile(`(?:^|[\x00\s])--remote-debugging-port(?:=|[\x00\s]+)([0-9]+)(?:[\x00\s]|$)`)

// Target represents a Chrome DevTools Protocol target from /json.
type Target struct {
	ID                   string `json:"id"`
	Type                 string `json:"type"`
	Title                string `json:"title"`
	URL                  string `json:"url"`
	WebSocketDebuggerURL string `json:"webSocketDebuggerUrl"`
}

// DiscoverTargets returns the CDP targets exposed by an HTTP endpoint.
// httpEndpoint should be like "http://localhost:9222".
func DiscoverTargets(httpEndpoint string) ([]Target, error) {
	url := strings.TrimRight(httpEndpoint, "/") + "/json"
	resp, err := discoveryHTTPClient.Get(url)
	if err != nil {
		return nil, fmt.Errorf("could not connect to %s: %w", url, err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("could not read response: %w", err)
	}

	var targets []Target
	if err := json.Unmarshal(body, &targets); err != nil {
		return nil, fmt.Errorf("could not parse targets: %w", err)
	}
	return targets, nil
}

// Discover finds the first page target from a CDP HTTP endpoint.
func Discover(httpEndpoint string) (string, error) {
	targets, err := DiscoverTargets(httpEndpoint)
	if err != nil {
		return "", err
	}

	for _, t := range targets {
		if t.Type == "page" && t.WebSocketDebuggerURL != "" {
			return t.WebSocketDebuggerURL, nil
		}
	}

	return "", fmt.Errorf("no page target found at %s", httpEndpoint)
}

// DiscoverFromPort is a convenience that builds the HTTP endpoint from a port.
func DiscoverFromPort(port int) (string, error) {
	return Discover(fmt.Sprintf("http://localhost:%d", port))
}

// DefaultPorts returns common CDP debugging ports to try for auto-discovery.
func DefaultPorts() []int {
	return []int{9222, 9229}
}

// CandidatePorts returns newest process-discovered CDP ports followed by the
// conventional fallback ports.
func CandidatePorts() []int {
	return candidatePorts(browserProcessCommandLines())
}

func candidatePorts(commandLines []string) []int {
	ports := remoteDebuggingPorts(commandLines)
	ports = append(ports, DefaultPorts()...)

	seen := make(map[int]bool, len(ports))
	unique := make([]int, 0, len(ports))
	for _, port := range ports {
		if port <= 0 || port > 65535 || seen[port] {
			continue
		}
		seen[port] = true
		unique = append(unique, port)
	}
	return unique
}

func remoteDebuggingPorts(commandLines []string) []int {
	var ports []int
	for _, commandLine := range commandLines {
		matches := remoteDebuggingPortPattern.FindAllStringSubmatch(commandLine, -1)
		for _, match := range matches {
			port, err := strconv.Atoi(match[1])
			if err == nil && port > 0 && port <= 65535 {
				ports = append(ports, port)
			}
		}
	}
	return ports
}

func browserProcessCommandLines() []string {
	switch runtime.GOOS {
	case "linux":
		entries, err := os.ReadDir("/proc")
		if err != nil {
			return nil
		}
		type processCommandLine struct {
			pid     int
			command string
		}
		var processes []processCommandLine
		for _, entry := range entries {
			if !entry.IsDir() {
				continue
			}
			pid, err := strconv.Atoi(entry.Name())
			if err != nil {
				continue
			}
			data, err := os.ReadFile(filepath.Join("/proc", entry.Name(), "cmdline"))
			if err == nil && len(data) > 0 {
				processes = append(processes, processCommandLine{pid: pid, command: string(data)})
			}
		}
		sort.Slice(processes, func(i, j int) bool { return processes[i].pid > processes[j].pid })
		commandLines := make([]string, 0, len(processes))
		for _, process := range processes {
			commandLines = append(commandLines, process.command)
		}
		return commandLines
	case "darwin":
		return reverseStrings(processCommandOutput("ps", "-ax", "-o", "pid=,command="))
	case "windows":
		return processCommandOutput("powershell", "-NoProfile", "-Command", "Get-CimInstance Win32_Process | Sort-Object ProcessId -Descending | Select-Object -ExpandProperty CommandLine")
	default:
		return nil
	}
}

func reverseStrings(values []string) []string {
	for left, right := 0, len(values)-1; left < right; left, right = left+1, right-1 {
		values[left], values[right] = values[right], values[left]
	}
	return values
}

func processCommandOutput(name string, args ...string) []string {
	output, err := exec.Command(name, args...).Output()
	if err != nil {
		return nil
	}
	return strings.Split(string(output), "\n")
}

// ScanForChrome finds the first local port exposing CDP page targets.
func ScanForChrome() (int, error) {
	ports := CandidatePorts()
	for _, port := range ports {
		if _, err := DiscoverFromPort(port); err == nil {
			return port, nil
		}
	}
	return 0, fmt.Errorf("no Chrome CDP port found among candidates %v", ports)
}
