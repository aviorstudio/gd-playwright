package commands

import (
	"encoding/json"
	"fmt"
	"os"
	"os/signal"
	"time"

	"github.com/aviorstudio/gd-playwright/cli/internal/cdp"
	"github.com/aviorstudio/gd-playwright/cli/internal/types"
	"github.com/spf13/cobra"
)

// NewWatchCmd creates the "watch" command.
func NewWatchCmd(connect func() (*cdp.Client, error)) *cobra.Command {
	var (
		name    string
		filters []string
		quiet   bool
	)

	cmd := &cobra.Command{
		Use:   "watch",
		Short: "Stream game events in real-time",
		Long: `Continuously polls window.godotEvents and prints new events as they arrive.
Press Ctrl+C to stop.

Use --name to filter by event type, --filter=key=value for data filtering,
--quiet to print only event names.`,
		Example: `  gdpw watch
  gdpw watch --name=unit_selected
  gdpw watch --filter="is_player_turn=true"
  gdpw watch --quiet`,
		RunE: func(cmd *cobra.Command, args []string) error {
			client, err := connect()
			if err != nil {
				return err
			}
			defer client.Close()

			parsedFilters := parseFilters(filters)

			// Get current latest timestamp as baseline — only show NEW events.
			baseline, _ := getEventCount(client)
			lastIndex := baseline

			// Handle Ctrl+C gracefully.
			sigCh := make(chan os.Signal, 1)
			signal.Notify(sigCh, os.Interrupt)

			pollInterval := 200 * time.Millisecond
			ticker := time.NewTicker(pollInterval)
			defer ticker.Stop()

			fmt.Fprintln(os.Stderr, "watching events... (Ctrl+C to stop)")

			for {
				select {
				case <-sigCh:
					fmt.Fprintln(os.Stderr, "\nstopped")
					return nil
				case <-ticker.C:
					events, newIndex, err := fetchEventsSinceIndex(client, lastIndex)
					if err != nil {
						continue
					}
					lastIndex = newIndex
					for _, e := range events {
						if name != "" && e.Event != name {
							continue
						}
						if len(parsedFilters) > 0 && !matchesFilters(e.Data, parsedFilters) {
							continue
						}
						if quiet {
							fmt.Println(e.Event)
						} else {
							b, _ := json.Marshal(e)
							fmt.Printf("[%d] %s\n", e.Timestamp, string(b))
						}
					}
				}
			}
		},
	}

	cmd.Flags().StringVar(&name, "name", "", "only show events with this name")
	cmd.Flags().StringArrayVar(&filters, "filter", nil, "filter event data by key=value (can be repeated)")
	cmd.Flags().BoolVar(&quiet, "quiet", false, "print only event names, no data")
	return cmd
}

// fetchEventsSinceIndex returns events from index onward and the new length.
func fetchEventsSinceIndex(client *cdp.Client, fromIndex int64) ([]types.GodotEvent, int64, error) {
	js := fmt.Sprintf(`JSON.stringify((function() {
		var evts = window.godotEvents || [];
		return { events: evts.slice(%d), length: evts.length };
	})())`, fromIndex)

	raw, err := client.Evaluate(js)
	if err != nil {
		return nil, fromIndex, err
	}
	var jsonStr string
	if err := json.Unmarshal(raw, &jsonStr); err != nil {
		return nil, fromIndex, err
	}
	var result struct {
		Events []types.GodotEvent `json:"events"`
		Length int64              `json:"length"`
	}
	if err := json.Unmarshal([]byte(jsonStr), &result); err != nil {
		return nil, fromIndex, err
	}
	return result.Events, result.Length, nil
}
