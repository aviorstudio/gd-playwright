package commands

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/aviorstudio/gd-playwright/cli/internal/cdp"
	"github.com/aviorstudio/gd-playwright/cli/internal/runcode"
	"github.com/aviorstudio/gd-playwright/cli/internal/scaling"
	"github.com/aviorstudio/gd-playwright/cli/internal/types"
	"github.com/spf13/cobra"
)

// NewGetCmd creates the "get" command.
func NewGetCmd(connect func() (*cdp.Client, error)) *cobra.Command {
	var (
		jsonOutput bool
		force      bool
		script     bool
	)

	cmd := &cobra.Command{
		Use:   "get <key> [key2] [key3...]",
		Short: "Get canvas-scaled coordinates for tagged elements",
		Long: `Returns the center x y coordinates of Godot elements, scaled to canvas space.
The coordinates can be passed directly to playwright-cli mousemove.

Multiple keys can be provided to batch-query in a single CDP call.
By default, refuses to return coordinates for invisible elements (use --force to override).
Use --script to output one atomic playwright-cli run-code command per key. The
browser resolves each coordinate immediately before clicking.`,
		Example: `  gdpw get battle_button
  gdpw get tile_4_3 tile_4_2 tile_3_3
  gdpw get battle_button --json
  gdpw get hidden_element --force
  gdpw get battle_button --script`,
		Args: cobra.MinimumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			if script && !jsonOutput {
				for _, key := range args {
					code, err := runcode.RenderAction(runcode.ActionOptions{Action: "click", Key: key, Force: force})
					if err != nil {
						return err
					}
					fmt.Println(runcode.ShellCommand(code))
				}
				return nil
			}
			client, err := connect()
			if err != nil {
				return err
			}
			defer client.Close()

			// Build JS that fetches all requested keys + viewport + canvas in one call.
			keyListJS := "["
			for i, k := range args {
				if i > 0 {
					keyListJS += ","
				}
				keyListJS += fmt.Sprintf("%q", k)
			}
			keyListJS += "]"

			js := fmt.Sprintf(`JSON.stringify((function() {
				var els = window.godotElements || {};
				var keys = %s;
				var results = {};
				for (var i = 0; i < keys.length; i++) {
					results[keys[i]] = els[keys[i]] || null;
				}
				return {
					elements: results,
					vp: window.godotElementsViewport || null,
					canvas: document.querySelector('canvas') ? document.querySelector('canvas').getBoundingClientRect() : null
				};
			})())`, keyListJS)

			raw, err := client.Evaluate(js)
			if err != nil {
				return fmt.Errorf("failed to query elements: %w", err)
			}

			var jsonStr string
			if err := json.Unmarshal(raw, &jsonStr); err != nil {
				return fmt.Errorf("failed to parse outer JSON: %w", err)
			}

			var result struct {
				Elements map[string]*types.ElementEntry `json:"elements"`
				VP       *types.Viewport                `json:"vp"`
				Canvas   *types.CanvasRect              `json:"canvas"`
			}
			if err := json.Unmarshal([]byte(jsonStr), &result); err != nil {
				return fmt.Errorf("failed to parse query result: %w", err)
			}

			vp := result.VP
			if vp == nil {
				vp = &types.Viewport{Width: 720, Height: 1280}
			}
			canvas := result.Canvas
			if canvas == nil {
				canvas = &types.CanvasRect{X: 0, Y: 0, Width: vp.Width, Height: vp.Height}
			}

			// Collect errors for missing/invisible elements.
			var errors []string
			multiKey := len(args) > 1

			for _, key := range args {
				el := result.Elements[key]
				if el == nil {
					// Include available keys in error.
					availableKeys := fetchAllKeys(client)
					if len(availableKeys) > 0 {
						hint := strings.Join(availableKeys, ", ")
						if len(hint) > 200 {
							hint = hint[:200] + "..."
						}
						errors = append(errors, fmt.Sprintf("element %q not found — available: %s", key, hint))
					} else {
						errors = append(errors, fmt.Sprintf("element %q not found — run `gdpw list` to see available elements", key))
					}
					continue
				}

				if !el.Visible && !force {
					if multiKey {
						// In bulk mode, silently skip invisible elements
						continue
					}
					errors = append(errors, fmt.Sprintf("element %q is not visible (use --force to get coordinates anyway)", key))
					continue
				}

				pos := scaling.Scale(el, vp, canvas)

				if jsonOutput {
					out := map[string]any{
						"key":     key,
						"x":       pos.X,
						"y":       pos.Y,
						"w":       pos.W,
						"h":       pos.H,
						"visible": el.Visible,
					}
					b, _ := json.Marshal(out)
					fmt.Println(string(b))
				} else if multiKey {
					fmt.Printf("%s %d %d\n", key, pos.X, pos.Y)
				} else {
					fmt.Printf("%d %d\n", pos.X, pos.Y)
				}
			}

			if len(errors) > 0 {
				return fmt.Errorf("%s", strings.Join(errors, "\n"))
			}
			return nil
		},
	}

	cmd.Flags().BoolVar(&jsonOutput, "json", false, "output full position data as JSON")
	cmd.Flags().BoolVar(&force, "force", false, "return coordinates even for invisible elements")
	cmd.Flags().BoolVar(&script, "script", false, "output atomic playwright-cli run-code clicks")
	return cmd
}

// fetchAllKeys returns all registered element keys for error context.
func fetchAllKeys(client *cdp.Client) []string {
	js := `JSON.stringify(Object.keys(window.godotElements || {}).sort())`
	raw, err := client.Evaluate(js)
	if err != nil {
		return nil
	}
	var jsonStr string
	if err := json.Unmarshal(raw, &jsonStr); err != nil {
		return nil
	}
	var keys []string
	if err := json.Unmarshal([]byte(jsonStr), &keys); err != nil {
		return nil
	}
	return keys
}
