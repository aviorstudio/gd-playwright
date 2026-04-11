package commands

import (
	"encoding/json"
	"fmt"

	"github.com/aviorstudio/gd-playwright/cli/internal/cdp"
	"github.com/aviorstudio/gd-playwright/cli/internal/types"
	"github.com/spf13/cobra"
)

// NewEventsCmd creates the "events" command.
func NewEventsCmd(connect func() (*cdp.Client, error)) *cobra.Command {
	var (
		last    int
		name    string
		filters []string
		since   int64
	)

	cmd := &cobra.Command{
		Use:   "events",
		Short: "Show recent game events from window.godotEvents",
		Long: `Returns events emitted by gd-playwright's event bridge.
Use --last to limit count, --name to filter by event name,
--filter=key=value to match event data fields,
--since=<timestamp> to only show events after a timestamp.`,
		Example: `  gdpw events --last=5
  gdpw events --name=hand_ready --filter="is_opponent=false"
  gdpw events --since=1660000`,
		RunE: func(cmd *cobra.Command, args []string) error {
			client, err := connect()
			if err != nil {
				return err
			}
			defer client.Close()

			js := fmt.Sprintf(`JSON.stringify((window.godotEvents || []).slice(-%d))`, last)
			raw, err := client.Evaluate(js)
			if err != nil {
				return fmt.Errorf("failed to query events: %w", err)
			}

			var jsonStr string
			if err := json.Unmarshal(raw, &jsonStr); err != nil {
				return fmt.Errorf("failed to parse outer JSON: %w", err)
			}

			var events []types.GodotEvent
			if err := json.Unmarshal([]byte(jsonStr), &events); err != nil {
				return fmt.Errorf("failed to parse events: %w", err)
			}

			if name != "" {
				filtered := make([]types.GodotEvent, 0)
				for _, e := range events {
					if e.Event == name {
						filtered = append(filtered, e)
					}
				}
				events = filtered
			}

			if since > 0 {
				filtered := make([]types.GodotEvent, 0)
				for _, e := range events {
					if e.Timestamp > since {
						filtered = append(filtered, e)
					}
				}
				events = filtered
			}

			parsedFilters := parseFilters(filters)
			if len(parsedFilters) > 0 {
				filtered := make([]types.GodotEvent, 0)
				for _, e := range events {
					if matchesFilters(e.Data, parsedFilters) {
						filtered = append(filtered, e)
					}
				}
				events = filtered
			}

			if len(events) == 0 {
				fmt.Println("no events")
				return nil
			}

			b, _ := json.MarshalIndent(events, "", "  ")
			fmt.Println(string(b))
			return nil
		},
	}

	cmd.Flags().IntVar(&last, "last", 100, "number of recent events to return")
	cmd.Flags().StringVar(&name, "name", "", "filter events by name")
	cmd.Flags().StringArrayVar(&filters, "filter", nil, "filter event data by key=value (can be repeated)")
	cmd.Flags().Int64Var(&since, "since", 0, "only show events with timestamp greater than this value")
	return cmd
}
