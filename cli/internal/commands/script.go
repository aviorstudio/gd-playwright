package commands

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/aviorstudio/gd-playwright/cli/internal/runcode"
	"github.com/spf13/cobra"
)

type scriptFlags struct {
	force       bool
	expectEvent string
	filters     []string
	timeout     int
	retries     int
	retryDelay  int
}

// NewScriptCmd creates browser-local Playwright action scripts without
// dispatching input from gdpw itself.
func NewScriptCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "script",
		Short: "Generate atomic playwright-cli actions for live Godot elements",
		Long:  "Generates one playwright-cli run-code command that resolves element coordinates immediately before input. Pipe the output to a shell to execute it.",
	}
	cmd.AddCommand(newClickScriptCmd())
	cmd.AddCommand(newDragScriptCmd())
	return cmd
}

func newClickScriptCmd() *cobra.Command {
	var flags scriptFlags
	cmd := &cobra.Command{
		Use:   "click <key>",
		Short: "Generate an atomic click action",
		Example: `  gdpw script click play_button | sh
  gdpw script click moving_target --expect-event target_clicked --retries 2 | sh`,
		Args: cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			options, err := flags.options("click", args[0])
			if err != nil {
				return err
			}
			return printAction(options)
		},
	}
	flags.bind(cmd)
	return cmd
}

func newDragScriptCmd() *cobra.Command {
	var flags scriptFlags
	var to string
	var toKey string
	var steps int
	cmd := &cobra.Command{
		Use:   "drag <key>",
		Short: "Generate an atomic drag action",
		Example: `  gdpw script drag enemy_1 --to 1000,260 --expect-event enemy_released --filter id=1 --retries 3 | sh
  gdpw script drag tile_1 --to-key tile_4 | sh`,
		Args: cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			options, err := flags.options("drag", args[0])
			if err != nil {
				return err
			}
			options.Steps = steps
			switch {
			case to != "" && toKey != "":
				return fmt.Errorf("use either --to or --to-key, not both")
			case toKey != "":
				options.ToKey = toKey
			case to != "":
				point, err := parsePoint(to)
				if err != nil {
					return err
				}
				options.To = &point
			default:
				return fmt.Errorf("drag requires --to x,y or --to-key key")
			}
			return printAction(options)
		},
	}
	flags.bind(cmd)
	cmd.Flags().StringVar(&to, "to", "", "page-space destination as x,y")
	cmd.Flags().StringVar(&toKey, "to-key", "", "destination gd-playwright element key")
	cmd.Flags().IntVar(&steps, "steps", 6, "intermediate mouse-move steps")
	return cmd
}

func (flags *scriptFlags) bind(cmd *cobra.Command) {
	cmd.Flags().BoolVar(&flags.force, "force", false, "allow invisible elements")
	cmd.Flags().StringVar(&flags.expectEvent, "expect-event", "", "fresh Godot event that confirms the action")
	cmd.Flags().StringArrayVar(&flags.filters, "filter", nil, "confirmation event data filter as key=value")
	cmd.Flags().IntVar(&flags.timeout, "timeout", 1000, "confirmation timeout per attempt in milliseconds")
	cmd.Flags().IntVar(&flags.retries, "retries", 0, "additional attempts after a missing confirmation")
	cmd.Flags().IntVar(&flags.retryDelay, "retry-delay", 50, "delay between attempts in milliseconds")
}

func (flags scriptFlags) options(action string, key string) (runcode.ActionOptions, error) {
	options := runcode.ActionOptions{
		Action:       action,
		Key:          key,
		Force:        flags.force,
		Retries:      flags.retries,
		RetryDelayMS: flags.retryDelay,
	}
	if flags.expectEvent == "" {
		if len(flags.filters) > 0 {
			return options, fmt.Errorf("--filter requires --expect-event")
		}
		if flags.retries > 0 {
			return options, fmt.Errorf("--retries requires --expect-event")
		}
		return options, nil
	}
	options.Confirm = &runcode.Confirmation{
		Event:     flags.expectEvent,
		Filters:   parseFilters(flags.filters),
		TimeoutMS: flags.timeout,
	}
	return options, nil
}

func parsePoint(value string) (runcode.Point, error) {
	parts := strings.Split(value, ",")
	if len(parts) != 2 {
		return runcode.Point{}, fmt.Errorf("invalid --to %q: expected x,y", value)
	}
	x, err := strconv.ParseFloat(strings.TrimSpace(parts[0]), 64)
	if err != nil {
		return runcode.Point{}, fmt.Errorf("invalid --to x coordinate %q", parts[0])
	}
	y, err := strconv.ParseFloat(strings.TrimSpace(parts[1]), 64)
	if err != nil {
		return runcode.Point{}, fmt.Errorf("invalid --to y coordinate %q", parts[1])
	}
	return runcode.Point{X: x, Y: y}, nil
}

func printAction(options runcode.ActionOptions) error {
	code, err := runcode.RenderAction(options)
	if err != nil {
		return err
	}
	fmt.Println(runcode.ShellCommand(code))
	return nil
}
