package abora

import "github.com/charmbracelet/lipgloss"

var (
	accentColor = lipgloss.Color("33")
	mutedColor  = lipgloss.Color("110")
	panelColor  = lipgloss.Color("25")
	dangerColor = lipgloss.Color("203")

	panelStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(accentColor).
			Padding(1, 2)
	titleStyle = lipgloss.NewStyle().
			Foreground(accentColor).
			Bold(true)
	mutedStyle = lipgloss.NewStyle().
			Foreground(mutedColor)
	labelStyle = lipgloss.NewStyle().
			Foreground(mutedColor).
			Width(13)
	valueStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("159")).
			Bold(true)
)

func kv(label, value string) string {
	return labelStyle.Render(label) + valueStyle.Render(value)
}
