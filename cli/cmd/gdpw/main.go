package main

import (
	"fmt"
	"os"
	"strconv"

	"github.com/aviorstudio/gd-playwright/cli/internal/cdp"
	"github.com/aviorstudio/gd-playwright/cli/internal/commands"
	"github.com/spf13/cobra"
)

var version = "dev"

func main() {
	var (
		cdpEndpoint string
		port        int
	)

	rootCmd := &cobra.Command{
		Use:   "gdpw",
		Short: "Query Godot game elements and state via CDP",
		Long: `gdpw connects to a browser running a Godot web game and reads
element positions and events emitted by gd-playwright.

Use alongside playwright-cli: gdpw provides coordinates,
playwright-cli performs clicks and inputs.

Environment variables:
  GDPW_PORT  CDP port (avoids --port on every command)
  GDPW_CDP   CDP websocket endpoint (avoids --cdp on every command)

Example:
  playwright-cli open http://localhost:8060 --headed
  export GDPW_PORT=9222
  gdpw list --visible
  gdpw get battle_button        # → 360 640
  playwright-cli mousemove 360 640
  playwright-cli mousedown
  playwright-cli mouseup`,
		Version:      version,
		SilenceUsage: true,
	}

	rootCmd.PersistentFlags().StringVar(&cdpEndpoint, "cdp", "", "CDP websocket endpoint (e.g. ws://localhost:9222/devtools/page/...)")
	rootCmd.PersistentFlags().IntVar(&port, "port", 0, "CDP port to connect to (discovers page target automatically)")

	// connect returns a CDP client using flags, env vars, or auto-discovery.
	connect := func() (*cdp.Client, error) {
		// 1. Explicit --cdp flag
		if cdpEndpoint != "" {
			return cdp.Connect(cdpEndpoint)
		}
		// 2. Explicit --port flag
		if port > 0 {
			return cdp.ConnectFromPort(port)
		}
		// 3. GDPW_CDP env var
		if envCDP := os.Getenv("GDPW_CDP"); envCDP != "" {
			return cdp.Connect(envCDP)
		}
		// 4. GDPW_PORT env var
		if envPort := os.Getenv("GDPW_PORT"); envPort != "" {
			p, err := strconv.Atoi(envPort)
			if err == nil && p > 0 {
				return cdp.ConnectFromPort(p)
			}
		}
		// 5. Auto-discover from default ports
		client, err := cdp.AutoConnect()
		if err != nil {
			return nil, fmt.Errorf("could not connect to browser\n  set GDPW_PORT, pass --port, or run `playwright-cli open <url>` first\n  %w", err)
		}
		return client, nil
	}

	rootCmd.AddCommand(commands.NewGetCmd(connect))
	rootCmd.AddCommand(commands.NewListCmd(connect))
	rootCmd.AddCommand(commands.NewStatusCmd(connect))
	rootCmd.AddCommand(commands.NewEventsCmd(connect))
	rootCmd.AddCommand(commands.NewWaitCmd(connect))
	rootCmd.AddCommand(commands.NewStateCmd(connect))
	rootCmd.AddCommand(commands.NewWatchCmd(connect))

	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}
