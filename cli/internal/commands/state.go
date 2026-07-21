package commands

import (
	"encoding/json"
	"fmt"

	"github.com/aviorstudio/gd-playwright/cli/internal/cdp"
	"github.com/spf13/cobra"
)

const stateExpression = `JSON.stringify(function() {
	var events = window.godotEvents || [];
	var els = window.godotElements || {};
	var vp = window.godotElementsViewport || null;
	var state = {};

	// Live element data (always available)
	var allKeys = Object.keys(els);
	var visibleKeys = allKeys.filter(function(k) { return els[k].visible; });
	state.elements = {
		total: allKeys.length,
		visible: visibleKeys.length
	};
	state.viewport = vp;
	state.event_count = events.length;
	state.test_state = window.godotTestState || {};

	// Group latest event of each type (game-agnostic)
	var latest = {};
	for (var i = events.length - 1; i >= 0; i--) {
		var e = events[i];
		if (!latest[e.event]) {
			latest[e.event] = e;
		}
	}
	state.latest_events = latest;

	return state;
}())`

// NewStateCmd creates the "state" command.
func NewStateCmd(connect func() (*cdp.Client, error)) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "state",
		Short: "Show aggregated game state",
		Long: `Reports live gd-playwright state: element counts, viewport,
test state, event buffer size, and the latest event of each type.

This command is game-agnostic — it groups events by name and
shows the most recent of each, so any game's events are surfaced.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			client, err := connect()
			if err != nil {
				return err
			}
			defer client.Close()

			raw, err := client.Evaluate(stateExpression)
			if err != nil {
				return fmt.Errorf("failed to query state: %w", err)
			}

			var jsonStr string
			if err := json.Unmarshal(raw, &jsonStr); err != nil {
				return fmt.Errorf("failed to parse outer JSON: %w", err)
			}

			var state map[string]any
			if err := json.Unmarshal([]byte(jsonStr), &state); err != nil {
				return fmt.Errorf("failed to parse state: %w", err)
			}

			b, _ := json.MarshalIndent(state, "", "  ")
			fmt.Println(string(b))
			return nil
		},
	}

	return cmd
}
