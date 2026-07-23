package abora

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"time"

	choosecmd "github.com/AnimatedGTVR/MINT/choose"
	confirmcmd "github.com/AnimatedGTVR/MINT/confirm"
	inputcmd "github.com/AnimatedGTVR/MINT/input"
	"github.com/AnimatedGTVR/MINT/internal/exit"
	spincmd "github.com/AnimatedGTVR/MINT/spin"
	"github.com/AnimatedGTVR/MINT/style"
	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/x/term"
)

var (
	prototypeStepStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("33")).Bold(true)
	prototypeOKStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("82")).Bold(true)
	prototypeHelpStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("110"))
	prototypeBlueStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("39")).Bold(true)
)

// Run walks through a safe prototype of the Abora OS installer.
func (o PrototypeOptions) Run() error {
	interactive := term.IsTerminal(os.Stdin.Fd())
	control := interactive && !o.NoControl
	if control {
		restore := controlTerminal("Abora OS Installer")
		defer restore()
	}

	logoMode := "auto"
	if o.TTY {
		logoMode = "tty"
	}
	if o.Kitty {
		logoMode = "kitty"
	}
	if control {
		clearTerminal()
	}
	if err := renderLogo(defaultLogoPath, "72", logoMode, "2k", true); err != nil {
		return err
	}

	reader := bufio.NewReader(os.Stdin)
	fmt.Fprintln(os.Stderr, panelStyle.Width(72).Render(lipgloss.JoinVertical(
		lipgloss.Left,
		titleStyle.Render("Abora OS Prototype Installer"),
		"",
		mutedStyle.Render("This prototype does not partition disks or install files yet."),
		mutedStyle.Render("It is here so we can shape the TUI flow before wiring the real backend."),
	)))

	action, err := selectChoice(reader, interactive, "Welcome to Abora OS", []choiceItem{
		{Label: "Install Abora OS to System", Value: "install"},
		{Label: "Use Abora OS in Live Media", Value: "live"},
	})
	if err != nil {
		return err
	}
	if action == "live" {
		if control {
			clearTerminal()
		}
		fmt.Fprintln(os.Stderr, prototypeOKStyle.Render("Live session selected. Exiting installer prototype."))
		return nil
	}

	if control {
		clearTerminal()
		renderMiniHeader("Edition")
	}
	editionItems := make([]choiceItem, 0, len(editions))
	for _, edition := range editions {
		editionItems = append(editionItems, choiceItem{
			Label: fmt.Sprintf("%s - %s", edition.Label, edition.Description),
			Value: edition.ID,
		})
	}
	edition, err := selectChoice(reader, interactive, "Select Abora OS edition", editionItems)
	if err != nil {
		return err
	}

	if control {
		clearTerminal()
		renderMiniHeader("System Details")
	}
	hostname, err := collectInput(reader, interactive, "Hostname", "Name this Abora install", o.Hostname)
	if err != nil {
		return err
	}
	disk, err := collectInput(reader, interactive, "Target disk", "Example: /dev/nvme0n1", o.Disk)
	if err != nil {
		return err
	}
	username, err := collectInput(reader, interactive, "User account", "Primary username", "abora")
	if err != nil {
		return err
	}
	fullName, err := collectInput(reader, interactive, "Full name", "Display name for the primary user", "Abora User")
	if err != nil {
		return err
	}
	passwordHash := ""
	if o.Execute {
		passwordHash, err = collectPasswordHash(reader, interactive)
		if err != nil {
			return err
		}
	}

	if control {
		clearTerminal()
		renderMiniHeader("Localization")
	}
	timezone, err := selectChoice(reader, interactive, "Timezone", []choiceItem{
		{Label: "America/New_York", Value: "America/New_York"},
		{Label: "America/Indianapolis", Value: "America/Indianapolis"},
		{Label: "UTC", Value: "UTC"},
		{Label: "Europe/London", Value: "Europe/London"},
	})
	if err != nil {
		return err
	}
	locale, err := selectChoice(reader, interactive, "Locale", []choiceItem{
		{Label: "English (United States)", Value: "en_US.UTF-8"},
		{Label: "English (United Kingdom)", Value: "en_GB.UTF-8"},
		{Label: "Spanish (United States)", Value: "es_US.UTF-8"},
	})
	if err != nil {
		return err
	}
	keyboard, err := selectChoice(reader, interactive, "Keyboard layout", []choiceItem{
		{Label: "US English", Value: "us"},
		{Label: "US International", Value: "us-intl"},
		{Label: "United Kingdom", Value: "gb"},
		{Label: "German", Value: "de"},
		{Label: "French", Value: "fr"},
	})
	if err != nil {
		return err
	}

	if control {
		clearTerminal()
		renderMiniHeader("Network")
	}
	network, err := selectChoice(reader, interactive, "Network setup", []choiceItem{
		{Label: "Use NetworkManager automatically", Value: "networkmanager"},
		{Label: "Open nmtui after install", Value: "nmtui"},
		{Label: "Skip network setup", Value: "skip"},
	})
	if err != nil {
		return err
	}

	if control {
		clearTerminal()
		renderMiniHeader("Disk Layout")
	}
	layout, err := selectChoice(reader, interactive, "Partitioning", []choiceItem{
		{Label: "Erase disk and install Abora OS", Value: "erase"},
		{Label: "Manual partitioning", Value: "manual"},
		{Label: "Install alongside existing system", Value: "alongside"},
	})
	if err != nil {
		return err
	}
	encryption, err := selectChoice(reader, interactive, "Encryption", []choiceItem{
		{Label: "No encryption", Value: "off"},
		{Label: "Enable LUKS encryption", Value: "luks"},
	})
	if err != nil {
		return err
	}
	filesystem, err := selectChoice(reader, interactive, "Filesystem", []choiceItem{
		{Label: "Btrfs with snapshots", Value: "btrfs"},
		{Label: "Ext4 classic layout", Value: "ext4"},
		{Label: "XFS workstation layout", Value: "xfs"},
	})
	if err != nil {
		return err
	}
	swap, err := selectChoice(reader, interactive, "Swap", []choiceItem{
		{Label: "Swapfile", Value: "swapfile"},
		{Label: "ZRAM", Value: "zram"},
		{Label: "No swap", Value: "off"},
	})
	if err != nil {
		return err
	}

	if control {
		clearTerminal()
		renderMiniHeader("Boot")
	}
	bootMode, err := selectChoice(reader, interactive, "Boot options", []choiceItem{
		{Label: "Standard EFI boot", Value: "efi"},
		{Label: "BOOTX64 Mode (MSI Compatibility Mode)", Value: "msi"},
	})
	if err != nil {
		return err
	}
	if control {
		clearTerminal()
		renderMiniHeader("Software")
	}
	kernel, err := selectChoice(reader, interactive, "Kernel", []choiceItem{
		{Label: "Abora default kernel", Value: "default"},
		{Label: "Zen kernel", Value: "zen"},
		{Label: "LTS kernel", Value: "lts"},
	})
	if err != nil {
		return err
	}
	drivers, err := selectChoice(reader, interactive, "Graphics drivers", []choiceItem{
		{Label: "Auto-detect drivers", Value: "auto"},
		{Label: "NVIDIA proprietary stack", Value: "nvidia"},
		{Label: "Mesa open drivers", Value: "mesa"},
		{Label: "Minimal framebuffer", Value: "minimal"},
	})
	if err != nil {
		return err
	}
	updates, err := selectChoice(reader, interactive, "Updates", []choiceItem{
		{Label: "Install updates during setup", Value: "install"},
		{Label: "Defer updates until first boot", Value: "defer"},
	})
	if err != nil {
		return err
	}
	extras, err := selectChoice(reader, interactive, "Extra software", []choiceItem{
		{Label: "Essentials only", Value: "essentials"},
		{Label: "Gaming tools", Value: "gaming"},
		{Label: "Creator tools", Value: "creator"},
		{Label: "Developer tools", Value: "developer"},
	})
	if err != nil {
		return err
	}
	firstBoot, err := selectChoice(reader, interactive, "First boot", []choiceItem{
		{Label: "Show Abora welcome app", Value: "welcome"},
		{Label: "Open desktop directly", Value: "desktop"},
	})
	if err != nil {
		return err
	}
	dotfiles := "skip"
	if edition == "hyprland" {
		if control {
			clearTerminal()
			renderMiniHeader("Hyprland")
		}
		dotfiles, err = collectInput(reader, interactive, "Dotfiles source", "Git URL or local path, blank to skip", "")
		if err != nil {
			return err
		}
		if dotfiles == "" {
			dotfiles = "skip"
		}
	}

	if o.PreAlpha {
		if control {
			clearTerminal()
			renderMiniHeader("Pre-Alpha Warning")
		}
		if err := promptRisk(reader, "I ACCEPT THE RISK"); err != nil {
			return err
		}
	}

	if control {
		clearTerminal()
		renderMiniHeader("Review")
	}
	renderPrototypeSummary(prototypePlan{
		Edition:     edition,
		Desktop:     edition,
		Hostname:    hostname,
		Username:    username,
		FullName:    fullName,
		PasswordSet: passwordHash != "",
		Disk:        disk,
		Layout:      layout,
		Encryption:  encryption,
		Filesystem:  filesystem,
		Swap:        swap,
		Timezone:    timezone,
		Locale:      locale,
		Keyboard:    keyboard,
		Network:     network,
		BootMode:    bootMode,
		Kernel:      kernel,
		Drivers:     drivers,
		Updates:     updates,
		Extras:      extras,
		FirstBoot:   firstBoot,
		Dotfiles:    dotfiles,
	})

	if err := confirmInstall(reader, interactive); err != nil {
		return err
	}

	if control {
		clearTerminal()
		renderMiniHeader("Installing")
	}
	if o.DryRun {
		fmt.Fprintln(os.Stderr, prototypeOKStyle.Render("Dry run complete. No install steps were simulated."))
		return nil
	}

	if o.Execute {
		return runBackend(o.Backend, prototypePlan{
			Edition:      edition,
			Desktop:      edition,
			Hostname:     hostname,
			Username:     username,
			FullName:     fullName,
			PasswordHash: passwordHash,
			Disk:         disk,
			Layout:       layout,
			Encryption:   encryption,
			Filesystem:   filesystem,
			Swap:         swap,
			Timezone:     timezone,
			Locale:       locale,
			Keyboard:     keyboard,
			Network:      network,
			BootMode:     bootMode,
			Kernel:       kernel,
			Drivers:      drivers,
			Updates:      updates,
			Extras:       extras,
			FirstBoot:    firstBoot,
			Dotfiles:     dotfiles,
		})
	}

	if err := runPrototypeSteps(edition, interactive); err != nil {
		return err
	}
	if control {
		clearTerminal()
	}
	fmt.Fprintln(os.Stderr)
	fmt.Fprintln(os.Stderr, panelStyle.Width(72).Render(lipgloss.JoinVertical(
		lipgloss.Left,
		prototypeOKStyle.Render("Prototype Complete"),
		"",
		mutedStyle.Render("No disks were changed."),
		mutedStyle.Render("Next step: replace these simulated steps with the real Abora installer backend."),
	)))
	return nil
}

func controlTerminal(title string) func() {
	fmt.Fprint(os.Stderr, "\x1b[?1049h")
	fmt.Fprint(os.Stderr, "\x1b[?25l")
	fmt.Fprintf(os.Stderr, "\x1b]0;%s\x07", title)
	clearTerminal()
	return func() {
		fmt.Fprint(os.Stderr, "\x1b[?25h")
		fmt.Fprint(os.Stderr, "\x1b[0m")
		fmt.Fprint(os.Stderr, "\x1b[?1049l")
	}
}

func clearTerminal() {
	fmt.Fprint(os.Stderr, "\x1b[2J\x1b[H")
}

func renderMiniHeader(section string) {
	bar := lipgloss.NewStyle().
		Foreground(lipgloss.Color("15")).
		Background(lipgloss.Color("25")).
		Bold(true).
		Padding(0, 1).
		Width(72).
		Render("Abora OS Installer  /  " + section)
	fmt.Fprintln(os.Stderr, bar)
	fmt.Fprintln(os.Stderr, prototypeBlueStyle.Render("Welcome > Edition > System > Locale > Disk > Boot > Software > Review"))
	fmt.Fprintln(os.Stderr, prototypeHelpStyle.Render(strings.Repeat("-", 72)))
	fmt.Fprintln(os.Stderr)
}

type choiceItem struct {
	Label string
	Value string
}

type prototypePlan struct {
	Edition      string
	Desktop      string
	Hostname     string
	Username     string
	FullName     string
	PasswordSet  bool
	PasswordHash string
	Disk         string
	Layout       string
	Encryption   string
	Filesystem   string
	Swap         string
	Timezone     string
	Locale       string
	Keyboard     string
	Network      string
	BootMode     string
	Kernel       string
	Drivers      string
	Updates      string
	Extras       string
	FirstBoot    string
	Dotfiles     string
}

func renderPrototypeSummary(plan prototypePlan) {
	fmt.Fprintln(os.Stderr, panelStyle.Width(72).Render(lipgloss.JoinVertical(
		lipgloss.Left,
		titleStyle.Render("Abora OS Install Plan"),
		"",
		kv("Edition", plan.Edition),
		kv("Desktop", plan.Desktop),
		kv("Hostname", plan.Hostname),
		kv("User", plan.Username),
		kv("Full name", plan.FullName),
		kv("Password", present(plan.PasswordSet)),
		kv("Disk", plan.Disk),
		kv("Layout", plan.Layout),
		kv("Filesystem", plan.Filesystem),
		kv("Swap", plan.Swap),
		kv("Encryption", plan.Encryption),
		kv("Timezone", plan.Timezone),
		kv("Locale", plan.Locale),
		kv("Keyboard", plan.Keyboard),
		kv("Network", plan.Network),
		kv("Boot", plan.BootMode),
		kv("Kernel", plan.Kernel),
		kv("Drivers", plan.Drivers),
		kv("Updates", plan.Updates),
		kv("Extras", plan.Extras),
		kv("First boot", plan.FirstBoot),
		kv("Dotfiles", plan.Dotfiles),
		"",
		mutedStyle.Render("Prototype only. No disks will be changed."),
	)))
}

func selectChoice(reader *bufio.Reader, interactive bool, title string, choices []choiceItem) (string, error) {
	if !interactive {
		return promptChoice(reader, title, choices)
	}

	options := make([]string, 0, len(choices))
	for _, choice := range choices {
		options = append(options, choice.Label+":"+choice.Value)
	}
	return runCaptured(func() error {
		return choosecmd.Options{
			Options:           options,
			Limit:             1,
			Height:            len(options),
			Header:            title,
			Cursor:            "▸ ",
			LabelDelimiter:    ":",
			StripANSI:         true,
			ShowHelp:          true,
			CursorStyle:       aboraStyle("33", true),
			HeaderStyle:       aboraStyle("33", true),
			SelectedItemStyle: aboraStyle("252", true),
			ItemStyle:         aboraStyle("246", false),
		}.Run()
	})
}

func collectInput(reader *bufio.Reader, interactive bool, title, placeholder, fallback string) (string, error) {
	if !interactive {
		return promptText(reader, title, fallback)
	}

	value, err := runCaptured(func() error {
		return inputcmd.Options{
			Header:      title,
			Placeholder: placeholder,
			Prompt:      "▸ ",
			Value:       fallback,
			Width:       42,
			CharLimit:   80,
			ShowHelp:    true,
			HeaderStyle: aboraStyle("33", true),
			PromptStyle: aboraStyle("33", true),
			CursorStyle: aboraStyle("33", true),
		}.Run()
	})
	if err != nil {
		return "", err
	}
	if strings.TrimSpace(value) == "" {
		return fallback, nil
	}
	return value, nil
}

func collectPasswordHash(reader *bufio.Reader, interactive bool) (string, error) {
	var password string
	var err error
	if interactive {
		password, err = runCaptured(func() error {
			return inputcmd.Options{
				Header:      "Password",
				Placeholder: "Password for the primary user",
				Prompt:      "▸ ",
				Password:    true,
				Width:       42,
				CharLimit:   256,
				ShowHelp:    true,
				HeaderStyle: aboraStyle("33", true),
				PromptStyle: aboraStyle("33", true),
				CursorStyle: aboraStyle("33", true),
			}.Run()
		})
	} else {
		password, err = promptText(reader, "Password", "")
	}
	if err != nil {
		return "", err
	}
	if password == "" {
		return "", fmt.Errorf("password cannot be empty")
	}
	cmd := exec.Command("openssl", "passwd", "-6", "-stdin")
	cmd.Stdin = strings.NewReader(password + "\n")
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("could not hash password with openssl: %w", err)
	}
	return strings.TrimSpace(string(out)), nil
}

func confirmInstall(reader *bufio.Reader, interactive bool) error {
	if !interactive {
		choice, err := promptChoice(reader, "Start prototype install?", []choiceItem{
			{Label: "Start Install", Value: "start"},
			{Label: "Go Back to Live Session", Value: "cancel"},
		})
		if err != nil {
			return err
		}
		if choice != "start" {
			fmt.Fprintln(os.Stderr, riskErrorStyle.Render("Install cancelled."))
			return exit.ErrExit(1)
		}
		return nil
	}

	if err := (confirmcmd.Options{
		Default:         true,
		Affirmative:     "Start Install",
		Negative:        "Cancel",
		Prompt:          "Start the prototype install?",
		ShowHelp:        true,
		PromptStyle:     aboraStyle("33", true),
		SelectedStyle:   style.Styles{Foreground: "16", Background: "33", Bold: true, Padding: "0 2"},
		UnselectedStyle: style.Styles{Foreground: "252", Background: "238", Padding: "0 2"},
	}).Run(); err != nil {
		fmt.Fprintln(os.Stderr, riskErrorStyle.Render("Install cancelled."))
		return err
	}
	return nil
}

func runBackend(backend string, plan prototypePlan) error {
	params, err := writeBatchParams(plan)
	if err != nil {
		return err
	}
	fmt.Fprintln(os.Stderr, prototypeBlueStyle.Render("Starting real Abora installer backend..."))
	fmt.Fprintln(os.Stderr, prototypeHelpStyle.Render("Batch params: "+params))

	cmd := exec.Command("bash", backend, "--batch", params)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	cmd.Env = append(os.Environ(),
		"ABORA_DESKTOP_PROFILES_LIB="+envDefault("ABORA_DESKTOP_PROFILES_LIB", "/etc/abora/desktop-profiles.sh"),
		"ABORA_APP_CATALOG_LIB="+envDefault("ABORA_APP_CATALOG_LIB", "/etc/abora/app-catalog.sh"),
	)
	return cmd.Run()
}

func writeBatchParams(plan prototypePlan) (string, error) {
	file, err := os.CreateTemp("", "abora-mint-batch-*.sh")
	if err != nil {
		return "", err
	}
	defer file.Close()

	appsLabel := mapChoice(plan.Extras, map[string]string{
		"essentials": "Essentials",
		"gaming":     "Gaming",
		"creator":    "Creator",
		"developer":  "Developer",
	}, "Essentials")
	desktop := normalizeBackendDesktop(plan.Edition)
	xkb := xkbForKeyboard(plan.Keyboard)
	gpu := backendGPU(plan.Drivers)
	dotfiles := ""
	if plan.Dotfiles != "skip" {
		dotfiles = plan.Dotfiles
	}
	values := map[string]string{
		"disk":                      plan.Disk,
		"hostname_value":            plan.Hostname,
		"username_value":            plan.Username,
		"timezone_value":            plan.Timezone,
		"keyboard_value":            plan.Keyboard,
		"xkb_layout_value":          xkb,
		"locale_value":              plan.Locale,
		"language_label":            plan.Locale,
		"desktop_profile":           desktop,
		"desktop_label":             desktop,
		"desktop_variant_id":        desktop,
		"gpu_value":                 gpu,
		"starter_apps_bundle":       plan.Extras,
		"starter_apps_label":        appsLabel,
		"install_apps_during_setup": mapChoice(plan.Updates, map[string]string{"install": "yes", "defer": "no"}, "no"),
		"anix_enabled":              "yes",
		"github_identity":           "Skipped",
		"user_password_hash":        plan.PasswordHash,
		"root_password_hash":        plan.PasswordHash,
		"root_password_mode":        "same",
		"dotfiles_url":              dotfiles,
	}
	for _, key := range batchKeys() {
		if _, err := fmt.Fprintf(file, "%s=%s\n", key, shellQuote(values[key])); err != nil {
			return "", err
		}
	}
	return file.Name(), nil
}

func batchKeys() []string {
	return []string{
		"disk", "hostname_value", "username_value", "timezone_value", "keyboard_value",
		"xkb_layout_value", "locale_value", "language_label", "desktop_profile",
		"desktop_label", "desktop_variant_id", "gpu_value", "starter_apps_bundle",
		"starter_apps_label", "install_apps_during_setup", "anix_enabled",
		"github_identity", "user_password_hash", "root_password_hash",
		"root_password_mode", "dotfiles_url",
	}
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", "'\"'\"'") + "'"
}

func normalizeBackendDesktop(edition string) string {
	if edition == "kde" {
		return "plasma"
	}
	return edition
}

func xkbForKeyboard(keyboard string) string {
	switch keyboard {
	case "gb":
		return "gb"
	case "de":
		return "de"
	case "fr":
		return "fr"
	default:
		return "us"
	}
}

func backendGPU(driver string) string {
	switch driver {
	case "nvidia", "mesa", "minimal":
		if driver == "mesa" {
			return "auto"
		}
		if driver == "minimal" {
			return "none"
		}
		return driver
	default:
		return "auto"
	}
}

func mapChoice(value string, choices map[string]string, fallback string) string {
	if mapped, ok := choices[value]; ok {
		return mapped
	}
	return fallback
}

func envDefault(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func runCaptured(run func() error) (string, error) {
	oldStdout := os.Stdout
	readPipe, writePipe, err := os.Pipe()
	if err != nil {
		return "", err
	}
	os.Stdout = writePipe
	defer func() {
		os.Stdout = oldStdout
	}()
	err = run()
	_ = writePipe.Close()
	var builder strings.Builder
	_, _ = io.Copy(&builder, readPipe)
	_ = readPipe.Close()
	return strings.TrimSpace(builder.String()), err
}

func aboraStyle(foreground string, bold bool) style.Styles {
	return style.Styles{Foreground: foreground, Bold: bold}
}

func promptChoice(reader *bufio.Reader, title string, choices []choiceItem) (string, error) {
	fmt.Fprintln(os.Stderr)
	fmt.Fprintln(os.Stderr, prototypeStepStyle.Render(title))
	for i, choice := range choices {
		fmt.Fprintf(os.Stderr, "  %d. %s\n", i+1, choice.Label)
	}
	for {
		fmt.Fprint(os.Stderr, "> ")
		line, err := reader.ReadString('\n')
		if err != nil && len(line) == 0 {
			return "", err
		}
		line = strings.TrimSpace(line)
		if line == "" {
			return choices[0].Value, nil
		}
		for i, choice := range choices {
			if line == fmt.Sprint(i+1) {
				return choice.Value, nil
			}
		}
		for _, choice := range choices {
			if strings.EqualFold(line, choice.Value) || strings.EqualFold(line, choice.Label) {
				return choice.Value, nil
			}
		}
		fmt.Fprintln(os.Stderr, riskErrorStyle.Render("Choose a listed number or value."))
	}
}

func promptText(reader *bufio.Reader, title, fallback string) (string, error) {
	fmt.Fprintf(os.Stderr, "\n%s [%s]\n> ", prototypeStepStyle.Render(title), fallback)
	line, err := reader.ReadString('\n')
	if err != nil && len(line) == 0 {
		return "", err
	}
	line = strings.TrimSpace(line)
	if line == "" {
		return fallback, nil
	}
	return line, nil
}

func promptRisk(reader *bufio.Reader, phrase string) error {
	fmt.Fprintln(os.Stderr)
	fmt.Fprintln(os.Stderr, renderRiskPanel())
	fmt.Fprintf(os.Stderr, "\n%s %s\n> ", riskPromptStyle.Render("Type this exactly to continue:"), riskPhraseStyle.Render(phrase))
	line, err := reader.ReadString('\n')
	if err != nil && len(line) == 0 {
		return err
	}
	if strings.TrimSpace(line) != phrase {
		fmt.Fprintln(os.Stderr, riskErrorStyle.Render("Acknowledgement did not match; aborting."))
		return exit.ErrExit(1)
	}
	return nil
}

func runPrototypeSteps(edition string, interactive bool) error {
	steps := []string{
		"Checking boot mode",
		"Preparing network services",
		"Preparing target layout",
		"Formatting target filesystem",
		"Configuring swap",
		"Configuring encryption choices",
		"Installing Abora OS base system",
		"Installing selected kernel",
		"Installing graphics drivers",
		"Configuring " + edition + " desktop",
		"Installing extra software profile",
		"Applying locale and timezone",
		"Applying keyboard layout",
		"Creating user account",
		"Configuring first boot welcome",
		"Importing edition settings",
		"Installing bootloader",
		"Writing first boot setup",
	}
	fmt.Fprintln(os.Stderr)
	for i, step := range steps {
		title := fmt.Sprintf("[%d/%d] %s", i+1, len(steps), step)
		if interactive {
			if err := (spincmd.Options{
				Command:      []string{"sh", "-c", "sleep 0.45"},
				Spinner:      "dot",
				Title:        title,
				SpinnerStyle: aboraStyle("33", true),
				TitleStyle:   aboraStyle("252", false),
			}).Run(); err != nil {
				return err
			}
			fmt.Fprintln(os.Stderr, prototypeOKStyle.Render("done")+" "+prototypeHelpStyle.Render(step))
			continue
		}

		fmt.Fprintf(os.Stderr, "%s %s\n", prototypeStepStyle.Render(fmt.Sprintf("[%d/%d]", i+1, len(steps))), step)
		fmt.Fprint(os.Stderr, prototypeHelpStyle.Render("      "))
		for frame := 0; frame < 8; frame++ {
			fmt.Fprint(os.Stderr, prototypeHelpStyle.Render("•"))
			time.Sleep(45 * time.Millisecond)
		}
		time.Sleep(350 * time.Millisecond)
		fmt.Fprintln(os.Stderr, " "+prototypeOKStyle.Render("done"))
	}
	return nil
}
