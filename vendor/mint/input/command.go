package input

import (
	"errors"
	"fmt"
	"os"

	"github.com/AnimatedGTVR/MINT/cursor"
	"github.com/AnimatedGTVR/MINT/internal/stdin"
	"github.com/AnimatedGTVR/MINT/internal/timeout"
	"github.com/AnimatedGTVR/MINT/style"
	"github.com/charmbracelet/bubbles/help"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
)

// Run provides a shell script interface for the text input bubble.
// https://github.com/charmbracelet/bubbles/textinput
func (o Options) Run() error {
	if o.Value == "" {
		if in, _ := stdin.Read(stdin.StripANSI(o.StripANSI)); in != "" {
			o.Value = in
		}
	}

	i := textinput.New()
	if o.Value != "" {
		i.SetValue(o.Value)
	} else if in, _ := stdin.Read(stdin.StripANSI(o.StripANSI)); in != "" {
		i.SetValue(in)
	}
	i.Focus()
	i.Prompt = o.Prompt
	i.Placeholder = o.Placeholder
	i.Width = o.Width
	i.PromptStyle = o.PromptStyle.ToLipgloss()
	i.PlaceholderStyle = o.PlaceholderStyle.ToLipgloss()
	i.Cursor.Style = o.CursorStyle.ToLipgloss()
	i.Cursor.SetMode(cursor.Modes[o.CursorMode])
	i.CharLimit = o.CharLimit

	if o.Password {
		i.EchoMode = textinput.EchoPassword
		i.EchoCharacter = '•'
	}

	top, right, bottom, left := style.ParsePadding(o.Padding)
	m := model{
		textinput:   i,
		header:      o.Header,
		headerStyle: o.HeaderStyle.ToLipgloss(),
		padding:     []int{top, right, bottom, left},
		autoWidth:   o.Width < 1,
		showHelp:    o.ShowHelp,
		help:        help.New(),
		keymap:      defaultKeymap(),
	}

	ctx, cancel := timeout.Context(o.Timeout)
	defer cancel()

	p := tea.NewProgram(
		m,
		tea.WithOutput(os.Stderr),
		tea.WithReportFocus(),
		tea.WithContext(ctx),
	)
	tm, err := p.Run()
	if err != nil {
		return fmt.Errorf("failed to run input: %w", err)
	}

	m = tm.(model)
	if !m.submitted {
		return errors.New("not submitted")
	}
	fmt.Println(m.textinput.Value())
	return nil
}
