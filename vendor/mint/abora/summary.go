package abora

import (
	"fmt"
	"os"

	"github.com/charmbracelet/lipgloss"
)

// Run renders a compact installer summary card to stderr.
func (o SummaryOptions) Run() error {
	card := panelStyle.
		BorderForeground(panelColor).
		Width(58).
		Render(lipgloss.JoinVertical(
			lipgloss.Left,
			titleStyle.Render("Abora OS Install Summary"),
			"",
			kv("Edition", o.Edition),
			kv("Desktop", o.Desktop),
			kv("Hostname", o.Hostname),
			kv("Disk", o.Disk),
			"",
			mutedStyle.Render("Review these choices before starting the installer."),
		))

	fmt.Fprintln(os.Stderr, card)
	return nil
}
