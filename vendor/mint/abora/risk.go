package abora

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/AnimatedGTVR/MINT/internal/exit"
	"github.com/charmbracelet/lipgloss"
)

const preAlphaWarningTitle = "WARNING: ABORA PRE-ALPHA BUILD"

const preAlphaWarningBody = `Pre-alpha builds are unfinished development versions intended only for testing and gathering feedback.

Installing this build may:

- Prevent your system from booting
- Break existing applications or configurations
- Cause data loss
- Require manual recovery or a complete reinstall
- Include incomplete, unstable, or missing features

Do not install this build on your primary computer or any system containing important data.

Back up all important files before continuing.
`

var (
	riskPanelStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("203")).
			Padding(1, 2).
			Width(72)
	riskTitleStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("203")).
			Bold(true)
	riskPromptStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("43")).
			Bold(true)
	riskPhraseStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("229")).
			Background(lipgloss.Color("236")).
			Padding(0, 1)
	riskErrorStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("203")).
			Bold(true)
)

// Run requires the user to type the configured phrase exactly before continuing.
func (o RiskOptions) Run() error {
	if !o.Quiet {
		fmt.Fprintln(os.Stderr, renderRiskPanel())
		fmt.Fprintln(os.Stderr)
	}

	fmt.Fprintf(os.Stderr, "%s %s\n> ", riskPromptStyle.Render("Type this exactly to continue:"), riskPhraseStyle.Render(o.Phrase))

	scanner := bufio.NewScanner(os.Stdin)
	if !scanner.Scan() {
		if err := scanner.Err(); err != nil {
			return fmt.Errorf("unable to read acknowledgement: %w", err)
		}
		return exit.ErrExit(1)
	}

	if strings.TrimRight(scanner.Text(), "\r\n") != o.Phrase {
		fmt.Fprintln(os.Stderr, riskErrorStyle.Render("Acknowledgement did not match; aborting."))
		return exit.ErrExit(1)
	}

	return nil
}

func renderRiskPanel() string {
	return riskPanelStyle.Render(
		lipgloss.JoinVertical(
			lipgloss.Left,
			riskTitleStyle.Render(preAlphaWarningTitle),
			"",
			preAlphaWarningBody,
		),
	)
}
