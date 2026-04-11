package commands

import (
	"encoding/json"
	"fmt"

	"github.com/aviorstudio/gd-playwright/cli/internal/cdp"
	"github.com/aviorstudio/gd-playwright/cli/internal/types"
	"github.com/spf13/cobra"
)

// NewStatusCmd creates the "status" command.
func NewStatusCmd(connect func() (*cdp.Client, error)) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "status",
		Short: "Check connection status and game state",
		Long:  "Verifies CDP connection to the browser and reports gd-playwright state:\nelement count (total/visible), event count, and viewport info.",
		RunE: func(cmd *cobra.Command, args []string) error {
			client, err := connect()
			if err != nil {
				fmt.Println("connected: false")
				fmt.Printf("error: %s\n", err)
				fmt.Println("\nhint: set GDPW_PORT=<port> or pass --port=<port>")
				return nil
			}
			defer client.Close()

			js := `JSON.stringify((function() {
				var els = window.godotElements || {};
				var allKeys = Object.keys(els);
				var visibleCount = allKeys.filter(function(k) { return els[k].visible; }).length;
				return {
					element_count: allKeys.length,
					visible_count: visibleCount,
					event_count: (window.godotEvents || []).length,
					has_viewport: window.godotElementsViewport != null,
					viewport: window.godotElementsViewport || null
				};
			})())`

			raw, err := client.Evaluate(js)
			if err != nil {
				fmt.Println("connected: true")
				fmt.Println("gd-playwright: not ready")
				return nil
			}

			var jsonStr string
			if err := json.Unmarshal(raw, &jsonStr); err != nil {
				fmt.Println("connected: true")
				fmt.Println("gd-playwright: parse error")
				return nil
			}

			var info struct {
				types.StatusInfo
				VisibleCount int             `json:"visible_count"`
				Viewport     *types.Viewport `json:"viewport"`
			}
			if err := json.Unmarshal([]byte(jsonStr), &info); err != nil {
				fmt.Println("connected: true")
				fmt.Println("gd-playwright: parse error")
				return nil
			}

			fmt.Println("connected: true")
			fmt.Printf("elements: %d (%d visible)\n", info.ElementCount, info.VisibleCount)
			fmt.Printf("events: %d\n", info.EventCount)
			if info.Viewport != nil {
				fmt.Printf("viewport: %dx%d\n", int(info.Viewport.Width), int(info.Viewport.Height))
			} else {
				fmt.Println("viewport: not set")
			}

			return nil
		},
	}

	return cmd
}
