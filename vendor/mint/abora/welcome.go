package abora

import (
	"github.com/AnimatedGTVR/MINT/choose"
	"github.com/AnimatedGTVR/MINT/style"
)

// Run shows the first installer choice and prints either "install" or "live".
func (o WelcomeOptions) Run() error {
	if !o.NoLogo {
		if err := renderLogo(o.LogoPath, "120", "auto", "2k", true); err != nil {
			return err
		}
	}

	return choose.Options{
		Options:           installerActionChoices(o.InstallLabel, o.LiveLabel),
		Limit:             1,
		Height:            2,
		Header:            o.Header,
		Cursor:            "▸ ",
		LabelDelimiter:    ":",
		StripANSI:         true,
		ShowHelp:          true,
		CursorStyle:       aboraCursorStyle(),
		HeaderStyle:       aboraHeaderStyle(),
		SelectedItemStyle: aboraSelectedStyle(),
	}.Run()
}

func aboraCursorStyle() style.Styles {
	return style.Styles{Foreground: "43", Bold: true}
}

func aboraHeaderStyle() style.Styles {
	return style.Styles{Foreground: "43", Bold: true}
}

func aboraSelectedStyle() style.Styles {
	return style.Styles{Foreground: "252", Bold: true}
}
