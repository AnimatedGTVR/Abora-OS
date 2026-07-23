package main

import (
	"github.com/alecthomas/kong"

	"github.com/AnimatedGTVR/MINT/abora"
	"github.com/AnimatedGTVR/MINT/choose"
	"github.com/AnimatedGTVR/MINT/completion"
	"github.com/AnimatedGTVR/MINT/confirm"
	"github.com/AnimatedGTVR/MINT/file"
	"github.com/AnimatedGTVR/MINT/filter"
	"github.com/AnimatedGTVR/MINT/format"
	"github.com/AnimatedGTVR/MINT/input"
	"github.com/AnimatedGTVR/MINT/join"
	"github.com/AnimatedGTVR/MINT/log"
	"github.com/AnimatedGTVR/MINT/man"
	"github.com/AnimatedGTVR/MINT/pager"
	"github.com/AnimatedGTVR/MINT/spin"
	"github.com/AnimatedGTVR/MINT/style"
	"github.com/AnimatedGTVR/MINT/table"
	"github.com/AnimatedGTVR/MINT/version"
	"github.com/AnimatedGTVR/MINT/write"
)

// MINT is the command-line interface for Abora OS terminal UI helpers.
type MINT struct {
	// Version is a flag that can be used to display the version number.
	Version kong.VersionFlag `short:"v" help:"Print the version number"`

	// Completion generates MINT shell completion scripts.
	Completion completion.Completion `cmd:"" hidden:"" help:"Request shell completion"`

	// Man is a hidden command that generates MINT man pages.
	Man man.Man `cmd:"" hidden:"" help:"Generate man pages"`

	// Abora contains installer-focused helpers for Abora OS scripts.
	Abora abora.Options `cmd:"" help:"Abora OS installer helpers"`

	// Choose provides an interface to choose one option from a given list of
	// options. The options can be provided as (new-line separated) stdin or a
	// list of arguments.
	//
	// It is different from the filter command as it does not provide a fuzzy
	// finding input, so it is best used for smaller lists of options.
	//
	// Let's pick from a list of desktop environments:
	//
	// $ mint choose "COSMIC" "GNOME" "KDE"
	//
	Choose choose.Options `cmd:"" help:"Choose an option from a list of choices"`

	// Confirm provides an interface to ask a user to confirm an action.
	// The user is provided with an interface to choose an affirmative or
	// negative answer, which is then reflected in the exit code for use in
	// scripting.
	//
	// If the user selects the affirmative answer, the program exits with 0.
	// If the user selects the negative answer, the program exits with 1.
	//
	// I.e. confirm if the user wants to delete a file
	//
	// $ mint confirm "Are you sure?" && rm file.txt
	//
	Confirm confirm.Options `cmd:"" help:"Ask a user to confirm an action"`

	// File provides an interface to pick a file from a folder (tree).
	// The user is provided a file manager-like interface to navigate, to
	// select a file.
	//
	// Let's pick a file from the current directory:
	//
	// $ mint file
	// $ mint file .
	//
	// Let's pick a file from the home directory:
	//
	// $ mint file $HOME
	File file.Options `cmd:"" help:"Pick a file from a folder"`

	// Filter provides a fuzzy searching text input to allow filtering a list of
	// options to select one option.
	//
	// By default it will list all the files (recursively) in the current directory
	// for the user to choose one, but the script (or user) can provide different
	// new-line separated options to choose from.
	//
	// I.e. let's pick from a list of options:
	//
	// $ cat choices.txt | mint filter
	//
	Filter filter.Options `cmd:"" help:"Filter items from a list"`

	// Format allows you to render styled text from `markdown`, `code`,
	// `template` strings, or embedded `emoji` strings.
	// For more information see the format/README.md file.
	Format format.Options `cmd:"" help:"Format a string using a template"`

	// Input provides a shell script interface for the text input bubble.
	// https://github.com/charmbracelet/bubbles/tree/master/textinput
	//
	// It can be used to prompt the user for some input. The text the user
	// entered will be sent to stdout.
	//
	// $ mint input --placeholder "Hostname" > answer.text
	//
	Input input.Options `cmd:"" help:"Prompt for some input"`

	// Join provides a shell script interface for the lipgloss JoinHorizontal
	// and JoinVertical commands. It allows you to join multi-line text to
	// build different layouts.
	//
	// For example, you can place two bordered boxes next to each other:
	// Note: We wrap the variable in quotes to ensure the new lines are part of a
	// single argument. Otherwise, the command won't work as expected.
	//
	// $ mint join --horizontal "$LEFT_BOX" "$RIGHT_BOX"
	//
	//   ╔══════════════════════╗╔═════════════╗
	//   ║                      ║║             ║
	//   ║        Left          ║║     Right   ║
	//   ║                      ║║             ║
	//   ╚══════════════════════╝╚═════════════╝
	//
	Join join.Options `cmd:"" help:"Join text vertically or horizontally"`

	// Pager provides a shell script interface for the viewport bubble.
	// https://github.com/charmbracelet/bubbles/tree/master/viewport
	//
	// It allows the user to scroll through content like a pager.
	//
	// ╭────────────────────────────────────────────────╮
	// │    1 │ MINT Pager                              │
	// │    2 │ =========                               │
	// │    3 │                                         │
	// │    4 │ ```                                     │
	// │    5 │ mint pager --height 10 --width 25 < text│
	// │    6 │ ```                                     │
	// │    7 │                                         │
	// │    8 │                                         │
	// ╰────────────────────────────────────────────────╯
	//  ↓↑: navigate • q: quit
	//
	Pager pager.Options `cmd:"" help:"Scroll through a file"`

	// Spin provides a shell script interface for the spinner bubble.
	// https://github.com/charmbracelet/bubbles/tree/master/spinner
	//
	// It is useful for displaying that some task is running in the background
	// while consuming its output so that it is not shown to the user.
	//
	// For example, let's do a long running task: $ sleep 5
	//
	// We can simply prepend a spinner to this task to show it to the user,
	// while performing the task / command in the background.
	//
	// $ mint spin -t "Installing packages..." -- sleep 5
	//
	// The spinner will automatically exit when the task is complete.
	//
	Spin spin.Options `cmd:"" help:"Display spinner while running a command"`

	// Style provides a shell script interface for Lip Gloss.
	// https://github.com/charmbracelet/lipgloss
	//
	// It allows you to use Lip Gloss to style text without needing to use Go.
	// All of the styling options are available as flags.
	//
	// Let's make some text glamorous using bash:
	//
	// $ mint style \
	//  	--foreground 212 --border double --align center \
	//  	--width 50 --margin 2 --padding "2 4" \
	//  	"Abora OS" "Ready to install"
	//
	//
	//    ╔══════════════════════════════════════════════════╗
	//    ║                                                  ║
	//    ║                                                  ║
	//    ║                   Abora OS                       ║
	//    ║              So sweet and so fresh!              ║
	//    ║                                                  ║
	//    ║                                                  ║
	//    ╚══════════════════════════════════════════════════╝
	//
	Style style.Options `cmd:"" help:"Apply coloring, borders, spacing to text"`

	// Table provides a shell script interface for the table bubble.
	// https://github.com/charmbracelet/bubbles/tree/master/table
	//
	// It is useful to render tabular (CSV) data in a terminal and allows
	// the user to select a row from the table.
	//
	// Let's render a table:
	//
	// $ mint table <<< "Edition,Desktop\nCosmic,COSMIC\nGnome,GNOME\nKDE,KDE"
	//
	//  Flavor      Price
	//  Strawberry  $0.50
	//  Banana      $0.99
	//  Cherry      $0.75
	//
	Table table.Options `cmd:"" help:"Render a table of data"`

	// Write provides a shell script interface for the text area bubble.
	// https://github.com/charmbracelet/bubbles/tree/master/textarea
	//
	// It can be used to ask the user to write some long form of text
	// (multi-line) input. The text the user entered will be sent to stdout.
	//
	// $ mint write > output.text
	//
	Write write.Options `cmd:"" help:"Prompt for long-form text"`

	// Log provides a shell script interface for logging using Log.
	// https://github.com/charmbracelet/log
	//
	// It can be used to log messages to output.
	//
	// $ mint log --level info "Hello, world!"
	//
	Log log.Options `cmd:"" help:"Log messages to output"`

	// VersionCheck provides a command that checks if the current MINT version
	// matches a given semantic version constraint.
	//
	// It can be used to check that a minimum MINT version is installed in a
	// script.
	//
	// $ mint version-check '~> 0.15'
	//
	VersionCheck version.Options `cmd:"" help:"Semver check current MINT version"`
}
