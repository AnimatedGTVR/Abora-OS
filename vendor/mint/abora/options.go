package abora

import "github.com/AnimatedGTVR/MINT/choose"

const defaultLogoPath = "/home/animatedpc/Work/abora-os/assets/Abora-Text.png"

// Options contains Abora OS installer-focused helpers.
type Options struct {
	Edition   EditionOptions   `cmd:"" help:"Choose an Abora OS edition"`
	Logo      LogoOptions      `cmd:"" help:"Render an Abora OS logo image"`
	Prototype PrototypeOptions `cmd:"" help:"Run a prototype Abora OS installer flow"`
	Risk      RiskOptions      `cmd:"" help:"Require acknowledgement before unsafe installs"`
	Summary   SummaryOptions   `cmd:"" help:"Render an installer summary card"`
	Welcome   WelcomeOptions   `cmd:"" help:"Show the Abora OS installer welcome menu"`
}

// EditionOptions configures the Abora edition picker.
type EditionOptions struct {
	List        bool   `help:"List editions without opening the picker"`
	Recommended bool   `help:"Print the recommended edition id"`
	Header      string `help:"Picker header" default:"Select Abora OS edition:"`
}

// RiskOptions configures the pre-alpha risk acknowledgement prompt.
type RiskOptions struct {
	Phrase string `help:"Phrase required to continue" default:"I ACCEPT THE RISK"`
	Quiet  bool   `help:"Only print the input prompt"`
}

// PrototypeOptions configures the prototype installer flow.
type PrototypeOptions struct {
	PreAlpha  bool   `help:"Require the pre-alpha risk acknowledgement"`
	TTY       bool   `help:"Force TTY-safe logo rendering"`
	Kitty     bool   `help:"Force Kitty graphics logo rendering"`
	DryRun    bool   `help:"Show the flow without pretending to install files"`
	Execute   bool   `help:"Run the real Abora installer backend after confirmation"`
	Backend   string `help:"Installer backend script" default:"/etc/abora/installer.sh"`
	NoControl bool   `help:"Do not clear or take over the terminal"`
	Hostname  string `help:"Default target hostname" default:"abora"`
	Disk      string `help:"Default target disk" default:"/dev/vda"`
}

// LogoOptions configures terminal image rendering.
type LogoOptions struct {
	Path       string `help:"Logo image path" default:"${defaultLogoPath}"`
	Width      string `help:"Rendered logo width in terminal columns" default:"72"`
	Mode       string `help:"Render mode" enum:"auto,pixels,kitty,iterm,chafa,ansi,sixel,text,open,tty" default:"auto"`
	Quality    string `help:"Render quality preset" enum:"standard,2k" default:"2k"`
	Doctor     bool   `help:"Show terminal graphics support diagnostics"`
	NoFallback bool   `help:"Fail instead of rendering text when no image renderer is available"`
}

// SummaryOptions configures the installer summary card.
type SummaryOptions struct {
	Edition  string `help:"Edition id" default:"cosmic"`
	Hostname string `help:"Target hostname" default:"abora"`
	Disk     string `help:"Target disk" default:"not selected"`
	Desktop  string `help:"Desktop environment" default:"auto"`
}

// WelcomeOptions configures the installer welcome menu.
type WelcomeOptions struct {
	LiveLabel    string `help:"Live session label" default:"Use Abora OS in Live Media"`
	InstallLabel string `help:"Install action label" default:"Install Abora OS to System"`
	Header       string `help:"Picker header" default:"Welcome to Abora OS"`
	LogoPath     string `help:"Logo image path" default:"${defaultLogoPath}"`
	NoLogo       bool   `help:"Do not render the Abora logo before the menu"`
}

var editions = []struct {
	ID          string
	Label       string
	Description string
}{
	{"cosmic", "COSMIC Edition", "Recommended live desktop for Abora OS"},
	{"hyprland", "Hyprland Edition", "Tiling live desktop for keyboard-driven installs"},
	{"gnome", "GNOME Edition", "GNOME live desktop"},
	{"kde", "KDE Edition", "KDE Plasma live desktop"},
	{"other", "Other Environments", "Alternate desktop and window manager builds"},
}

func editionChoices() []string {
	choices := make([]string, 0, len(editions))
	for _, edition := range editions {
		choices = append(choices, edition.Label+":"+edition.ID)
	}
	return choices
}

func installerActionChoices(installLabel, liveLabel string) []string {
	return []string{
		installLabel + ":install",
		liveLabel + ":live",
	}
}

func editionPicker(header string) choose.Options {
	return choose.Options{
		Options:          editionChoices(),
		Limit:            1,
		Height:           len(editions),
		Header:           header,
		Cursor:           "> ",
		CursorPrefix:     "-> ",
		SelectedPrefix:   "[x] ",
		UnselectedPrefix: "[ ] ",
		LabelDelimiter:   ":",
		StripANSI:        true,
		ShowHelp:         true,
	}
}
