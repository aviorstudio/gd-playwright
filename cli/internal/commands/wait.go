package commands

import (
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/aviorstudio/gd-playwright/cli/internal/cdp"
	"github.com/aviorstudio/gd-playwright/cli/internal/types"
	"github.com/spf13/cobra"
)

// NewWaitCmd creates the "wait" command.
func NewWaitCmd(connect func() (*cdp.Client, error)) *cobra.Command {
	var (
		timeout    int
		includePast bool
		since      int64
		filters    []string
	)

	cmd := &cobra.Command{
		Use:   "wait <event_name>",
		Short: "Wait for a new game event to appear",
		Long: `Polls window.godotEvents until a NEW event with the given name appears.
By default only matches events that arrive after the command starts.
Use --include-past to also match events already in the buffer.
Use --since=<timestamp> to only match events newer than a timestamp.
Use --filter=key=value to match against event data fields.`,
		Example: `  gdpw wait route_loaded
  gdpw wait turn_changed --timeout=30000
  gdpw wait turn_changed --filter="is_player_turn=true"
  gdpw wait route_loaded --include-past`,
		Args: cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			eventName := args[0]

			client, err := connect()
			if err != nil {
				return err
			}
			defer client.Close()

			// Default: only match new events (--include-past overrides)
			var sinceIndex int64
			if !includePast {
				baseline, err := getEventCount(client)
				if err == nil {
					sinceIndex = baseline
				}
			}

			parsedFilters := parseFilters(filters)

			deadline := time.Now().Add(time.Duration(timeout) * time.Millisecond)
			pollInterval := 200 * time.Millisecond

			for {
				events, err := queryMatchingEvents(client, eventName, sinceIndex, since, parsedFilters)
				if err == nil && len(events) > 0 {
					b, _ := json.MarshalIndent(events[0], "", "  ")
					fmt.Println(string(b))
					return nil
				}

				if time.Now().After(deadline) {
					return fmt.Errorf("timeout waiting for event %q after %dms", eventName, timeout)
				}

				time.Sleep(pollInterval)
			}
		},
	}

	cmd.Flags().IntVar(&timeout, "timeout", 10000, "timeout in milliseconds")
	cmd.Flags().BoolVar(&includePast, "include-past", false, "also match events already in the buffer")
	cmd.Flags().Int64Var(&since, "since", 0, "only match events with timestamp greater than this value")
	cmd.Flags().StringArrayVar(&filters, "filter", nil, "filter event data by key=value (can be repeated)")
	return cmd
}

// getEventCount returns the current length of the godotEvents array.
func getEventCount(client *cdp.Client) (int64, error) {
	js := `JSON.stringify((window.godotEvents || []).length)`
	raw, err := client.Evaluate(js)
	if err != nil {
		return 0, err
	}
	var jsonStr string
	if err := json.Unmarshal(raw, &jsonStr); err != nil {
		return 0, err
	}
	var count int64
	if err := json.Unmarshal([]byte(jsonStr), &count); err != nil {
		return 0, err
	}
	return count, nil
}

// getLatestTimestamp returns the timestamp of the most recent event.
func getLatestTimestamp(client *cdp.Client) (int64, error) {
	js := `JSON.stringify((function(){
		var evts = window.godotEvents || [];
		if (evts.length === 0) return 0;
		return evts[evts.length - 1].timestamp || 0;
	})())`
	raw, err := client.Evaluate(js)
	if err != nil {
		return 0, err
	}
	var jsonStr string
	if err := json.Unmarshal(raw, &jsonStr); err != nil {
		return 0, err
	}
	var ts int64
	if err := json.Unmarshal([]byte(jsonStr), &ts); err != nil {
		return 0, err
	}
	return ts, nil
}

// queryMatchingEvents finds events matching name, index, timestamp, and data filters.
// sinceIndex skips events before that array index (used by --fresh).
// sinceTimestamp filters by timestamp (used by --since).
func queryMatchingEvents(client *cdp.Client, eventName string, sinceIndex int64, sinceTimestamp int64, filters map[string]string) ([]types.GodotEvent, error) {
	js := fmt.Sprintf(`JSON.stringify((function() {
		var evts = window.godotEvents || [];
		var result = [];
		for (var i = %d; i < evts.length; i++) {
			var e = evts[i];
			if (e.event !== %q) continue;
			if (%d > 0 && e.timestamp <= %d) continue;
			result.push(e);
		}
		return result;
	})())`, sinceIndex, eventName, sinceTimestamp, sinceTimestamp)

	raw, err := client.Evaluate(js)
	if err != nil {
		return nil, err
	}
	var jsonStr string
	if err := json.Unmarshal(raw, &jsonStr); err != nil {
		return nil, err
	}
	var events []types.GodotEvent
	if err := json.Unmarshal([]byte(jsonStr), &events); err != nil {
		return nil, err
	}

	if len(filters) == 0 {
		return events, nil
	}

	// Apply data filters
	var matched []types.GodotEvent
	for _, e := range events {
		if matchesFilters(e.Data, filters) {
			matched = append(matched, e)
		}
	}
	return matched, nil
}

// parseFilters parses "key=value" strings into a map.
func parseFilters(raw []string) map[string]string {
	result := make(map[string]string)
	for _, f := range raw {
		parts := strings.SplitN(f, "=", 2)
		if len(parts) == 2 {
			result[parts[0]] = parts[1]
		}
	}
	return result
}

// matchesFilters checks if event data contains all filter key=value pairs.
func matchesFilters(data map[string]any, filters map[string]string) bool {
	for key, expected := range filters {
		val, ok := data[key]
		if !ok {
			return false
		}
		actual := fmt.Sprintf("%v", val)
		if actual != expected {
			return false
		}
	}
	return true
}
