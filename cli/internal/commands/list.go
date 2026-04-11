package commands

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"github.com/aviorstudio/gd-playwright/cli/internal/cdp"
	"github.com/aviorstudio/gd-playwright/cli/internal/types"
	"github.com/spf13/cobra"
)

// NewListCmd creates the "list" command.
func NewListCmd(connect func() (*cdp.Client, error)) *cobra.Command {
	var (
		visibleOnly bool
		filter      string
		jsonOutput  bool
	)

	cmd := &cobra.Command{
		Use:   "list",
		Short: "List all registered element keys",
		Long:  "Returns all element keys registered by gd-playwright's ElementMapService.\nUse --visible to show only visible elements, --filter for prefix matching.",
		RunE: func(cmd *cobra.Command, args []string) error {
			client, err := connect()
			if err != nil {
				return err
			}
			defer client.Close()

			js := `JSON.stringify(window.godotElements || {})`
			raw, err := client.Evaluate(js)
			if err != nil {
				return fmt.Errorf("failed to query elements: %w", err)
			}

			var jsonStr string
			if err := json.Unmarshal(raw, &jsonStr); err != nil {
				return fmt.Errorf("failed to parse outer JSON: %w", err)
			}

			var elements map[string]types.ElementEntry
			if err := json.Unmarshal([]byte(jsonStr), &elements); err != nil {
				return fmt.Errorf("failed to parse elements: %w", err)
			}

			// Collect and sort keys.
			keys := make([]string, 0, len(elements))
			for k := range elements {
				keys = append(keys, k)
			}
			sort.Strings(keys)

			if jsonOutput {
				filtered := make(map[string]types.ElementEntry)
				for _, k := range keys {
					el := elements[k]
					if visibleOnly && !el.Visible {
						continue
					}
					if filter != "" && !strings.HasPrefix(k, filter) {
						continue
					}
					filtered[k] = el
				}
				b, _ := json.MarshalIndent(filtered, "", "  ")
				fmt.Println(string(b))
				return nil
			}

			for _, k := range keys {
				el := elements[k]
				if visibleOnly && !el.Visible {
					continue
				}
				if filter != "" && !strings.HasPrefix(k, filter) {
					continue
				}
				fmt.Println(k)
			}

			return nil
		},
	}

	cmd.Flags().BoolVar(&visibleOnly, "visible", false, "only show visible elements")
	cmd.Flags().StringVar(&filter, "filter", "", "only show keys matching this prefix")
	cmd.Flags().BoolVar(&jsonOutput, "json", false, "output full element map as JSON")
	return cmd
}
