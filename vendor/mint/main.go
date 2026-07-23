// Package main is MINT: Abora OS terminal UI tools for shell scripts.
package main

import (
	"errors"
	"fmt"
	"os"
	"runtime/debug"
	"strings"

	"github.com/AnimatedGTVR/MINT/internal/exit"
	"github.com/alecthomas/kong"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/termenv"
)

const shaLen = 7

var (
	// Version contains the application version number. It's set via ldflags
	// when building.
	Version = ""

	// CommitSHA contains the SHA of the commit that this application was built
	// against. It's set via ldflags when building.
	CommitSHA = ""
)

var mintAccent = lipgloss.NewStyle().Foreground(lipgloss.Color("43"))

func main() {
	lipgloss.SetColorProfile(termenv.NewOutput(os.Stderr).Profile)
	applyMINTEnvironmentAliases()

	if Version == "" {
		if info, ok := debug.ReadBuildInfo(); ok && info.Main.Sum != "" {
			Version = info.Main.Version
		} else {
			Version = "unknown (built from source)"
		}
	}
	commandName := commandName()
	version := fmt.Sprintf("%s version %s", commandName, Version)
	if len(CommitSHA) >= shaLen {
		version += " (" + CommitSHA[:shaLen] + ")"
	}

	mint := &MINT{}
	ctx := kong.Parse(
		mint,
		kong.Name(commandName),
		kong.Description(fmt.Sprintf("Abora OS terminal UI tools for %s shell scripts.", mintAccent.Render("guided"))),
		kong.UsageOnError(),
		kong.ConfigureHelp(kong.HelpOptions{
			Compact:             true,
			Summary:             false,
			NoExpandSubcommands: true,
		}),
		kong.Vars{
			"version":                 version,
			"versionNumber":           Version,
			"defaultHeight":           "0",
			"defaultWidth":            "0",
			"defaultAlign":            "left",
			"defaultBorder":           "none",
			"defaultBorderForeground": "",
			"defaultBorderBackground": "",
			"defaultBackground":       "",
			"defaultForeground":       "",
			"defaultMargin":           "0 0",
			"defaultPadding":          "0 0",
			"defaultUnderline":        "false",
			"defaultBold":             "false",
			"defaultFaint":            "false",
			"defaultItalic":           "false",
			"defaultStrikethrough":    "false",
			"defaultLogoPath":         "/home/animatedpc/Work/abora-os/assets/Abora-Text.png",
		},
	)
	if err := ctx.Run(); err != nil {
		var ex exit.ErrExit
		if errors.As(err, &ex) {
			os.Exit(int(ex))
		}
		if errors.Is(err, tea.ErrInterrupted) {
			os.Exit(exit.StatusAborted)
		}
		if errors.Is(err, tea.ErrProgramKilled) {
			fmt.Fprintln(os.Stderr, "timed out")
			os.Exit(exit.StatusTimeout)
		}
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func commandName() string {
	name := os.Args[0]
	if idx := strings.LastIndex(name, "/"); idx >= 0 {
		name = name[idx+1:]
	}
	if name == "" {
		return "gum"
	}
	return name
}

func applyMINTEnvironmentAliases() {
	for _, entry := range os.Environ() {
		key, value, ok := strings.Cut(entry, "=")
		if !ok || !strings.HasPrefix(key, "MINT_") {
			continue
		}
		gumKey := "GUM_" + strings.TrimPrefix(key, "MINT_")
		if _, exists := os.LookupEnv(gumKey); !exists {
			_ = os.Setenv(gumKey, value)
		}
	}
}
