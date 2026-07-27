package abora

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	choosecmd "github.com/AnimatedGTVR/MINT/choose"
	confirmcmd "github.com/AnimatedGTVR/MINT/confirm"
	filtercmd "github.com/AnimatedGTVR/MINT/filter"
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

// Run walks through the Abora OS installer front-end.
func (o PrototypeOptions) Run() error {
	interactive := term.IsTerminal(os.Stdin.Fd())
	control := interactive && !o.NoControl
	if control {
		restore := controlTerminal("Abora OS Installer")
		defer restore()
	}

	logoMode := "auto"
	if o.TTY {
		logoMode = "auto"
	}
	if o.Kitty {
		logoMode = "kitty"
	}
	if control {
		clearTerminal()
	}
	if err := renderLogo(resolveLogoPath(defaultLogoPath), "76", logoMode, "2k", true); err != nil {
		return err
	}

	reader := bufio.NewReader(os.Stdin)
	renderInstallerIntro()

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
		fmt.Fprintln(os.Stderr, prototypeOKStyle.Render("Live session selected."))
		fmt.Fprintln(os.Stderr, prototypeHelpStyle.Render("Dropping to the Abora live shell. Run abora-install to return."))
		return nil
	}

	state := &wizardState{
		hostname: o.Hostname,
		disk:     defaultTargetDisk(o.Disk),
		username: "abora",
		fullName: "Abora User",
		dotfiles: "skip",
	}
	if err := runWizard(o, state, reader, interactive, control); err != nil {
		return err
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
		Edition:     state.edition,
		Desktop:     state.edition,
		Hostname:    state.hostname,
		Username:    state.username,
		FullName:    state.fullName,
		PasswordSet: state.passwordHash != "",
		Disk:        state.disk,
		Layout:      state.layout,
		Encryption:  state.encryption,
		Filesystem:  state.filesystem,
		Swap:        state.swap,
		Timezone:    state.timezone,
		Locale:      state.locale,
		Keyboard:    state.keyboard,
		Network:     state.network,
		BootMode:    state.bootMode,
		Kernel:      state.kernel,
		Drivers:     state.drivers,
		Updates:     state.updates,
		Extras:      state.extras,
		FirstBoot:   state.firstBoot,
		Dotfiles:    state.dotfiles,
	})

	if err := confirmInstall(reader, interactive); err != nil {
		return err
	}
	edition := state.edition
	hostname := state.hostname
	username := state.username
	fullName := state.fullName
	passwordHash := state.passwordHash
	disk := state.disk
	layout := state.layout
	encryption := state.encryption
	filesystem := state.filesystem
	swap := state.swap
	timezone := state.timezone
	locale := state.locale
	keyboard := state.keyboard
	network := state.network
	bootMode := state.bootMode
	kernel := state.kernel
	drivers := state.drivers
	updates := state.updates
	extras := state.extras
	firstBoot := state.firstBoot
	dotfiles := state.dotfiles

	if control {
		clearTerminal()
		renderMiniHeader("Installing")
	}
	if o.DryRun {
		fmt.Fprintln(os.Stderr, prototypeOKStyle.Render("Dry run complete. No install steps were run."))
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
	fmt.Fprintln(os.Stderr, prototypeOKStyle.Render("Install Preview Complete"))
	fmt.Fprintln(os.Stderr, mutedStyle.Render("No disks were changed."))
	fmt.Fprintln(os.Stderr, mutedStyle.Render("Run with --execute to hand this plan to the Abora backend."))
	return nil
}

// wizardState accumulates answers as the installer wizard steps run. It is
// shared by every step function so that later steps (and going back to
// re-visit an earlier one) can see previously entered values.
type wizardState struct {
	edition        string
	hostname       string
	disk           string
	username       string
	fullName       string
	passwordHash   string
	timezoneRegion string
	timezone       string
	locale         string
	keyboard       string
	network        string
	layout         string
	encryption     string
	filesystem     string
	swap           string
	bootMode       string
	kernel         string
	drivers        string
	updates        string
	extras         string
	firstBoot      string
	dotfiles       string
}

// navResult tells runWizard which direction to move after a step completes.
type navResult int

const (
	navNext navResult = iota
	navBack
)

// wizardStep is one screen of the guided installer. header names the screen
// for the mini progress bar. run prompts the user (or, for steps that don't
// apply given earlier answers, does nothing) and reports which direction to
// move; dir is the direction the wizard was already travelling in, which a
// skipped step should simply pass through so back navigation can jump over
// steps that don't apply (e.g. the dotfiles step on non-Hyprland editions).
type wizardStep struct {
	header string
	run    func(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error)
}

// runWizard drives every installer question after the initial welcome
// screen, in order, letting the user step back (Esc, or the "Back" list
// entry) to any previous screen without losing what they already entered.
func runWizard(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive, control bool) error {
	steps := []wizardStep{
		{"Edition", stepEdition},
		{"System Details", stepHostname},
		{"System Details", stepDisk},
		{"System Details", stepUsername},
		{"System Details", stepFullName},
		{"System Details", stepPassword},
		{"Localization", stepTimezoneRegion},
		{"Localization", stepTimezoneCity},
		{"Localization", stepLocale},
		{"Localization", stepKeyboard},
		{"Network", stepNetwork},
		{"Disk Layout", stepLayout},
		{"Disk Layout", stepEncryption},
		{"Disk Layout", stepFilesystem},
		{"Disk Layout", stepSwap},
		{"Boot", stepBootMode},
		{"Software", stepKernel},
		{"Software", stepDrivers},
		{"Software", stepUpdates},
		{"Software", stepExtras},
		{"Software", stepFirstBoot},
		{"Hyprland", stepDotfiles},
	}

	dir := navNext
	idx := 0
	for idx < len(steps) {
		step := steps[idx]
		if control {
			clearTerminal()
			renderWizardHeader(step.header, idx+1, len(steps))
		}
		result, err := step.run(o, st, reader, interactive, dir)
		if err != nil {
			return err
		}
		dir = result
		if result == navNext {
			idx++
		} else if idx > 0 {
			idx--
		}
		// idx == 0 and navBack: nothing earlier than Edition to go back to
		// (Esc on the welcome screen already exits); just re-show it.
	}
	return nil
}

// backItem is prepended to a choice list to make "go back" discoverable as
// a normal list entry, not just an Esc keypress people may not try.
var backItem = choiceItem{Label: "← Back", Value: "__mint_back__"}

func selectChoiceNav(reader *bufio.Reader, interactive bool, title string, choices []choiceItem, allowBack bool) (string, navResult, error) {
	items := choices
	if allowBack {
		items = append([]choiceItem{backItem}, choices...)
	}
	value, err := selectChoice(reader, interactive, title, items)
	if err != nil {
		if allowBack && errors.Is(err, choosecmd.ErrNothingSelected) {
			return "", navBack, nil
		}
		return "", navNext, err
	}
	if allowBack && value == backItem.Value {
		return "", navBack, nil
	}
	return value, navNext, nil
}

// selectFilterNav is selectChoiceNav's counterpart for long lists (100+
// items) where scrolling a plain numbered menu isn't practical -- it uses
// mint's fuzzy-search filter component instead of choose.
func selectFilterNav(reader *bufio.Reader, interactive bool, title string, choices []choiceItem, allowBack bool) (string, navResult, error) {
	items := choices
	if allowBack {
		items = append([]choiceItem{backItem}, choices...)
	}
	if !interactive {
		value, err := promptChoice(reader, title, items)
		if err != nil {
			return "", navNext, err
		}
		if allowBack && value == backItem.Value {
			return "", navBack, nil
		}
		return value, navNext, nil
	}

	labels := make([]string, len(items))
	byLabel := make(map[string]string, len(items))
	for i, item := range items {
		labels[i] = item.Label
		byLabel[item.Label] = item.Value
	}

	// Filter (unlike choose) has no built-in label:value splitting, so we
	// look the picked label back up in byLabel above. Every option below
	// that has a Kong `default:"..."` tag needs to be set explicitly here:
	// those defaults are only ever applied by Kong's own CLI-flag parsing,
	// and we're constructing this struct directly in Go, not through Kong.
	// Strict in particular matters a lot: left at its Go zero value (false)
	// it lets whatever you're still typing be "selected" as a fake extra
	// match, so pressing Enter can submit your half-typed search text
	// instead of the highlighted real timezone -- which is exactly why
	// picking a specific zone was failing.
	for {
		selected, err := runCaptured(func() error {
			return filtercmd.Options{
				Options:               labels,
				Limit:                 1,
				Strict:                true,
				Fuzzy:                 true,
				FuzzySort:             true,
				Header:                title,
				Placeholder:           "Type to search...",
				Prompt:                "> ",
				Indicator:             "→",
				SelectedPrefix:        " ● ",
				UnselectedPrefix:      " ○ ",
				ShowHelp:              true,
				StripANSI:             true,
				HeaderStyle:           aboraStyle("33", true),
				PromptStyle:           aboraStyle("33", true),
				PlaceholderStyle:      aboraStyle("246", false),
				MatchStyle:            aboraStyle("252", true),
				TextStyle:             aboraStyle("246", false),
				IndicatorStyle:        aboraStyle("33", true),
				SelectedPrefixStyle:   aboraStyle("33", true),
				UnselectedPrefixStyle: aboraStyle("246", false),
			}.Run()
		})
		if err != nil {
			if allowBack && errors.Is(err, filtercmd.ErrNothingSelected) {
				return "", navBack, nil
			}
			return "", navNext, err
		}
		value, ok := byLabel[strings.TrimSpace(selected)]
		if !ok {
			// Shouldn't happen with Strict:true, but don't crash the whole
			// installer over a stray mismatch -- just ask again.
			fmt.Fprintln(os.Stderr, riskErrorStyle.Render("That wasn't one of the listed options, try again."))
			continue
		}
		if allowBack && value == backItem.Value {
			return "", navBack, nil
		}
		return value, navNext, nil
	}
}

func collectInputNav(reader *bufio.Reader, interactive bool, title, placeholder, fallback string) (string, navResult, error) {
	value, err := collectInput(reader, interactive, title, placeholder+"  (Esc to go back)", fallback)
	if err != nil {
		if errors.Is(err, inputcmd.ErrNotSubmitted) {
			return "", navBack, nil
		}
		return "", navNext, err
	}
	return value, navNext, nil
}

func stepEdition(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	items := make([]choiceItem, 0, len(editions))
	for _, edition := range editions {
		items = append(items, choiceItem{
			Label: fmt.Sprintf("%s - %s", edition.Label, edition.Description),
			Value: edition.ID,
		})
	}
	value, nav, err := selectChoiceNav(reader, interactive, "Select Abora OS edition", items, false)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.edition = value
	return navNext, nil
}

func stepHostname(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	value, nav, err := collectInputNav(reader, interactive, "Hostname", "Name this Abora install", st.hostname)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.hostname = value
	return navNext, nil
}

func stepDisk(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	disks := detectedInstallDisks()
	if len(disks) == 1 {
		st.disk = disks[0].Value
		fmt.Fprintln(os.Stderr, prototypeHelpStyle.Render("Using detected target disk: "+disks[0].Label))
		time.Sleep(700 * time.Millisecond)
		return navNext, nil
	}
	if len(disks) > 0 {
		value, nav, err := selectChoiceNav(reader, interactive, "Target disk", disks, true)
		if err != nil {
			return navNext, err
		}
		if nav == navBack {
			return navBack, nil
		}
		st.disk = value
		return navNext, nil
	}

	value, nav, err := collectInputNav(reader, interactive, "Target disk", "Example: /dev/nvme0n1", st.disk)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.disk = value
	return navNext, nil
}

func defaultTargetDisk(fallback string) string {
	if isBlockDevice(fallback) {
		return fallback
	}
	disks := detectedInstallDisks()
	if len(disks) == 0 {
		return fallback
	}
	return disks[0].Value
}

func detectedInstallDisks() []choiceItem {
	entries, err := os.ReadDir("/sys/block")
	if err != nil {
		return nil
	}
	var disks []choiceItem
	for _, entry := range entries {
		name := entry.Name()
		if !isInstallDiskName(name) {
			continue
		}
		device := "/dev/" + name
		if !isBlockDevice(device) {
			continue
		}
		size := diskSizeLabel(name)
		model := strings.TrimSpace(readSysBlockFile(name, "device/model"))
		label := device
		if size != "" {
			label += "  " + size
		}
		if model != "" {
			label += "  " + model
		}
		disks = append(disks, choiceItem{Label: label, Value: device})
	}
	sort.SliceStable(disks, func(i, j int) bool { return disks[i].Value < disks[j].Value })
	return disks
}

func isInstallDiskName(name string) bool {
	if strings.HasPrefix(name, "loop") || strings.HasPrefix(name, "ram") ||
		strings.HasPrefix(name, "zram") || strings.HasPrefix(name, "dm-") ||
		strings.HasPrefix(name, "sr") || strings.HasPrefix(name, "fd") {
		return false
	}
	return strings.HasPrefix(name, "sd") || strings.HasPrefix(name, "vd") ||
		strings.HasPrefix(name, "hd") || strings.HasPrefix(name, "xvd") ||
		strings.HasPrefix(name, "nvme") || strings.HasPrefix(name, "mmcblk")
}

func isBlockDevice(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return info.Mode()&os.ModeDevice != 0
}

func diskSizeLabel(name string) string {
	raw := strings.TrimSpace(readSysBlockFile(name, "size"))
	sectors, err := strconv.ParseUint(raw, 10, 64)
	if err != nil || sectors == 0 {
		return ""
	}
	bytes := sectors * 512
	units := []string{"B", "KiB", "MiB", "GiB", "TiB"}
	value := float64(bytes)
	unit := 0
	for value >= 1024 && unit < len(units)-1 {
		value /= 1024
		unit++
	}
	if unit < 3 {
		return fmt.Sprintf("%.0f %s", value, units[unit])
	}
	return fmt.Sprintf("%.1f %s", value, units[unit])
}

func readSysBlockFile(name, rel string) string {
	data, err := os.ReadFile(filepath.Join("/sys/block", name, rel))
	if err != nil {
		return ""
	}
	return string(data)
}

func stepUsername(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	value, nav, err := collectInputNav(reader, interactive, "User account", "Primary username", st.username)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.username = value
	return navNext, nil
}

func stepFullName(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	value, nav, err := collectInputNav(reader, interactive, "Full name", "Display name for the primary user", st.fullName)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.fullName = value
	return navNext, nil
}

func stepPassword(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	if !o.Execute {
		return dir, nil
	}
	hash, err := collectPasswordHash(reader, interactive)
	if err != nil {
		return navNext, err
	}
	st.passwordHash = hash
	return navNext, nil
}

// timezoneRegionOrder controls the order regions are shown in; only
// regions that actually have zones on this system are offered.
var timezoneRegionOrder = []string{"Americas", "Europe", "Africa", "Asia", "Australia & Oceania", "Other", "UTC"}

// timezoneTopLevelRegion maps a real IANA top-level zone directory to one
// of the human-facing regions above. Legacy backward-compat directories
// (Brazil, Canada, Chile, Mexico, US, posix, right, ...) are deliberately
// left out: they duplicate zones that already exist under their real
// continent, e.g. US/Indiana-Starke is the same zone as
// America/Indiana/Knox.
var timezoneTopLevelRegion = map[string]string{
	"America":    "Americas",
	"Europe":     "Europe",
	"Africa":     "Africa",
	"Asia":       "Asia",
	"Australia":  "Australia & Oceania",
	"Pacific":    "Australia & Oceania",
	"Antarctica": "Other",
	"Arctic":     "Other",
	"Atlantic":   "Other",
	"Indian":     "Other",
}

var (
	timezoneDataOnce  sync.Once
	timezoneRegions   []string
	timezonesByRegion map[string][]choiceItem
)

// loadTimezoneData walks the system's real IANA tzdata (/usr/share/zoneinfo)
// so every region shows every zone that actually exists there -- places
// like Indiana or Kentucky have several distinct zones within the same
// state/region, which a hand-picked list will always miss some of. Falls
// back to a small curated list if tzdata isn't present on this system.
func loadTimezoneData() ([]string, map[string][]choiceItem) {
	timezoneDataOnce.Do(func() {
		const zoneDir = "/usr/share/zoneinfo"
		byRegion := map[string][]choiceItem{}

		entries, err := os.ReadDir(zoneDir)
		if err != nil {
			timezoneRegions, timezonesByRegion = timezoneFallbackRegions, timezoneFallbackByRegion
			return
		}
		for _, top := range entries {
			region, ok := timezoneTopLevelRegion[top.Name()]
			if !ok {
				continue
			}
			base := filepath.Join(zoneDir, top.Name())
			_ = filepath.WalkDir(base, func(path string, d fs.DirEntry, err error) error {
				if err != nil || d.IsDir() {
					return nil
				}
				zoneName, relErr := filepath.Rel(zoneDir, path)
				if relErr != nil {
					return nil
				}
				zoneName = filepath.ToSlash(zoneName)
				byRegion[region] = append(byRegion[region], choiceItem{
					Label: zoneLabel(zoneName),
					Value: zoneName,
				})
				return nil
			})
		}
		byRegion["UTC"] = []choiceItem{{Label: "UTC", Value: "UTC"}}

		for region := range byRegion {
			sort.Slice(byRegion[region], func(i, j int) bool {
				return byRegion[region][i].Label < byRegion[region][j].Label
			})
		}

		regions := make([]string, 0, len(timezoneRegionOrder))
		for _, region := range timezoneRegionOrder {
			if len(byRegion[region]) > 0 {
				regions = append(regions, region)
			}
		}
		timezoneRegions, timezonesByRegion = regions, byRegion
	})
	return timezoneRegions, timezonesByRegion
}

// zoneLabel turns e.g. "America/Indiana/Indianapolis" into
// "Indianapolis, Indiana — America/Indiana/Indianapolis": a human-readable
// name up front (searchable by city or sub-region) with the real zone ID
// visible too, since that's what actually gets written to the installed
// system and people may want to confirm it directly.
func zoneLabel(zoneName string) string {
	parts := strings.Split(zoneName, "/")
	city := strings.ReplaceAll(parts[len(parts)-1], "_", " ")
	if len(parts) > 2 {
		sub := strings.ReplaceAll(parts[len(parts)-2], "_", " ")
		return fmt.Sprintf("%s, %s — %s", city, sub, zoneName)
	}
	return fmt.Sprintf("%s — %s", city, zoneName)
}

// timezoneFallbackRegions/timezoneFallbackByRegion are used only if this
// system has no /usr/share/zoneinfo to read from.
var timezoneFallbackRegions = []string{"Americas", "Europe", "Africa", "Asia", "Australia & Oceania", "UTC"}

var timezoneFallbackByRegion = map[string][]choiceItem{
	"Americas": {
		{Label: "New York — America/New_York", Value: "America/New_York"},
		{Label: "Chicago — America/Chicago", Value: "America/Chicago"},
		{Label: "Denver — America/Denver", Value: "America/Denver"},
		{Label: "Los Angeles — America/Los_Angeles", Value: "America/Los_Angeles"},
		{Label: "Indianapolis, Indiana — America/Indiana/Indianapolis", Value: "America/Indiana/Indianapolis"},
		{Label: "Toronto — America/Toronto", Value: "America/Toronto"},
		{Label: "Mexico City — America/Mexico_City", Value: "America/Mexico_City"},
		{Label: "Sao Paulo — America/Sao_Paulo", Value: "America/Sao_Paulo"},
	},
	"Europe": {
		{Label: "London — Europe/London", Value: "Europe/London"},
		{Label: "Paris — Europe/Paris", Value: "Europe/Paris"},
		{Label: "Berlin — Europe/Berlin", Value: "Europe/Berlin"},
		{Label: "Madrid — Europe/Madrid", Value: "Europe/Madrid"},
		{Label: "Moscow — Europe/Moscow", Value: "Europe/Moscow"},
	},
	"Africa": {
		{Label: "Cairo — Africa/Cairo", Value: "Africa/Cairo"},
		{Label: "Lagos — Africa/Lagos", Value: "Africa/Lagos"},
		{Label: "Johannesburg — Africa/Johannesburg", Value: "Africa/Johannesburg"},
	},
	"Asia": {
		{Label: "Dubai — Asia/Dubai", Value: "Asia/Dubai"},
		{Label: "Kolkata — Asia/Kolkata", Value: "Asia/Kolkata"},
		{Label: "Shanghai — Asia/Shanghai", Value: "Asia/Shanghai"},
		{Label: "Tokyo — Asia/Tokyo", Value: "Asia/Tokyo"},
		{Label: "Singapore — Asia/Singapore", Value: "Asia/Singapore"},
	},
	"Australia & Oceania": {
		{Label: "Sydney — Australia/Sydney", Value: "Australia/Sydney"},
		{Label: "Perth — Australia/Perth", Value: "Australia/Perth"},
		{Label: "Auckland — Pacific/Auckland", Value: "Pacific/Auckland"},
	},
	"UTC": {
		{Label: "UTC", Value: "UTC"},
	},
}

func stepTimezoneRegion(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	regions, _ := loadTimezoneData()
	items := make([]choiceItem, 0, len(regions))
	for _, region := range regions {
		items = append(items, choiceItem{Label: region, Value: region})
	}
	value, nav, err := selectChoiceNav(reader, interactive, "Timezone region", items, true)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.timezoneRegion = value
	return navNext, nil
}

func stepTimezoneCity(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	// UTC has exactly one option; skip straight past the extra prompt.
	if st.timezoneRegion == "UTC" {
		st.timezone = "UTC"
		return dir, nil
	}
	_, byRegion := loadTimezoneData()
	cities := byRegion[st.timezoneRegion]
	// Some regions have well over a hundred real zones (Americas alone has
	// 150+, once every Indiana/Kentucky-style sub-zone is included) -- a
	// plain numbered list doesn't scale, so let people type to search.
	value, nav, err := selectFilterNav(reader, interactive, "Timezone in "+st.timezoneRegion, cities, true)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.timezone = value
	return navNext, nil
}

func stepLocale(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	value, nav, err := selectChoiceNav(reader, interactive, "Locale", []choiceItem{
		{Label: "English (United States)", Value: "en_US.UTF-8"},
		{Label: "English (United Kingdom)", Value: "en_GB.UTF-8"},
		{Label: "Spanish (United States)", Value: "es_US.UTF-8"},
		{Label: "Spanish (Spain)", Value: "es_ES.UTF-8"},
		{Label: "French (France)", Value: "fr_FR.UTF-8"},
		{Label: "German (Germany)", Value: "de_DE.UTF-8"},
		{Label: "Portuguese (Brazil)", Value: "pt_BR.UTF-8"},
		{Label: "Japanese (Japan)", Value: "ja_JP.UTF-8"},
	}, true)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.locale = value
	return navNext, nil
}

func stepKeyboard(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	value, nav, err := selectChoiceNav(reader, interactive, "Keyboard layout", []choiceItem{
		{Label: "US English", Value: "us"},
		{Label: "US International", Value: "us-intl"},
		{Label: "United Kingdom", Value: "gb"},
		{Label: "German", Value: "de"},
		{Label: "French", Value: "fr"},
		{Label: "Spanish", Value: "es"},
	}, true)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.keyboard = value
	return navNext, nil
}

func stepNetwork(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	value, nav, err := selectChoiceNav(reader, interactive, "Network setup", []choiceItem{
		{Label: "Use NetworkManager automatically", Value: "networkmanager"},
		{Label: "Open nmtui after install", Value: "nmtui"},
		{Label: "Skip network setup", Value: "skip"},
	}, true)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.network = value
	return navNext, nil
}

func stepLayout(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	value, nav, err := selectChoiceNav(reader, interactive, "Partitioning", []choiceItem{
		{Label: "Erase disk and install Abora OS", Value: "erase"},
		{Label: "Manual partitioning", Value: "manual"},
		{Label: "Install alongside existing system", Value: "alongside"},
	}, true)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.layout = value
	return navNext, nil
}

func stepEncryption(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	value, nav, err := selectChoiceNav(reader, interactive, "Encryption", []choiceItem{
		{Label: "No encryption", Value: "off"},
		{Label: "Enable LUKS encryption", Value: "luks"},
	}, true)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.encryption = value
	return navNext, nil
}

func stepFilesystem(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	value, nav, err := selectChoiceNav(reader, interactive, "Filesystem", []choiceItem{
		{Label: "Btrfs with snapshots", Value: "btrfs"},
		{Label: "Ext4 classic layout", Value: "ext4"},
		{Label: "XFS workstation layout", Value: "xfs"},
	}, true)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.filesystem = value
	return navNext, nil
}

func stepSwap(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	value, nav, err := selectChoiceNav(reader, interactive, "Swap", []choiceItem{
		{Label: "Swapfile", Value: "swapfile"},
		{Label: "ZRAM", Value: "zram"},
		{Label: "No swap", Value: "off"},
	}, true)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.swap = value
	return navNext, nil
}

func stepBootMode(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	value, nav, err := selectChoiceNav(reader, interactive, "Boot options", []choiceItem{
		{Label: "Standard EFI boot", Value: "efi"},
		{Label: "BOOTX64 Mode (MSI Compatibility Mode)", Value: "msi"},
	}, true)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.bootMode = value
	return navNext, nil
}

func stepKernel(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	value, nav, err := selectChoiceNav(reader, interactive, "Kernel", []choiceItem{
		{Label: "Abora default kernel", Value: "default"},
		{Label: "Zen kernel", Value: "zen"},
		{Label: "LTS kernel", Value: "lts"},
	}, true)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.kernel = value
	return navNext, nil
}

func stepDrivers(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	value, nav, err := selectChoiceNav(reader, interactive, "Graphics drivers", []choiceItem{
		{Label: "Auto-detect drivers", Value: "auto"},
		{Label: "NVIDIA proprietary stack", Value: "nvidia"},
		{Label: "Mesa open drivers", Value: "mesa"},
		{Label: "Minimal framebuffer", Value: "minimal"},
	}, true)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.drivers = value
	return navNext, nil
}

func stepUpdates(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	value, nav, err := selectChoiceNav(reader, interactive, "Updates", []choiceItem{
		{Label: "Install updates during setup", Value: "install"},
		{Label: "Defer updates until first boot", Value: "defer"},
	}, true)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.updates = value
	return navNext, nil
}

func stepExtras(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	value, nav, err := selectChoiceNav(reader, interactive, "Extra software", []choiceItem{
		{Label: "Essentials only", Value: "essentials"},
		{Label: "Gaming tools", Value: "gaming"},
		{Label: "Creator tools", Value: "creator"},
		{Label: "Developer tools", Value: "developer"},
	}, true)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.extras = value
	return navNext, nil
}

func stepFirstBoot(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	value, nav, err := selectChoiceNav(reader, interactive, "First boot", []choiceItem{
		{Label: "Show Abora welcome app", Value: "welcome"},
		{Label: "Open desktop directly", Value: "desktop"},
	}, true)
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	st.firstBoot = value
	return navNext, nil
}

func stepDotfiles(o PrototypeOptions, st *wizardState, reader *bufio.Reader, interactive bool, dir navResult) (navResult, error) {
	if st.edition != "hyprland" {
		st.dotfiles = "skip"
		return dir, nil
	}
	value, nav, err := collectInputNav(reader, interactive, "Dotfiles source", "Git URL or local path, blank to skip", "")
	if err != nil {
		return navNext, err
	}
	if nav == navBack {
		return navBack, nil
	}
	if value == "" {
		value = "skip"
	}
	st.dotfiles = value
	return navNext, nil
}

func resolveLogoPath(path string) string {
	if path != "" {
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}
	for _, candidate := range []string{
		"/etc/abora/Abora-Text.png",
		"/run/current-system/etc/abora/Abora-Text.png",
		"/run/current-system/sw/share/abora/Abora-Text.png",
		"assets/Abora-Text.png",
		"/home/animatedpc/Work/abora-os/assets/Abora-Text.png",
	} {
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	return path
}

func renderInstallerIntro() {
	renderTTYIntroPanel([]string{
		"Abora OS Installer  EVEREST 4.0",
		"Easy guided install",
		"Pick the basics, review once, then Abora installs the system.",
		"Defaults are chosen for a simple desktop setup.",
	})
	fmt.Fprintln(os.Stderr)
}

func renderTTYIntroPanel(rows []string) {
	const width = 72
	border := "+" + strings.Repeat("-", width-2) + "+"
	fmt.Fprintf(os.Stderr, "\x1b[1;34m%s\x1b[0m\n", border)
	fmt.Fprintf(os.Stderr, "\x1b[1;34m|\x1b[0m%s\x1b[1;34m|\x1b[0m\n", strings.Repeat(" ", width-2))
	for i, row := range rows {
		if len(row) > width-6 {
			row = row[:width-6]
		}
		color := "\x1b[36m"
		if i == 0 {
			color = "\x1b[1;34m"
		} else if i == 1 {
			color = "\x1b[1;36m"
		}
		line := "  " + color + row + "\x1b[0m" + strings.Repeat(" ", width-4-len(row))
		fmt.Fprintf(os.Stderr, "\x1b[1;34m|\x1b[0m%s\x1b[1;34m|\x1b[0m\n", line)
	}
	fmt.Fprintf(os.Stderr, "\x1b[1;34m|\x1b[0m%s\x1b[1;34m|\x1b[0m\n", strings.Repeat(" ", width-2))
	fmt.Fprintf(os.Stderr, "\x1b[1;34m%s\x1b[0m\n", border)
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

// renderWizardHeader is renderMiniHeader plus a "Step X of Y" progress
// indicator, used for every screen in the answerable step wizard so people
// always know how far along they are and how much is left.
func renderWizardHeader(section string, step, total int) {
	bar := lipgloss.NewStyle().
		Foreground(lipgloss.Color("15")).
		Background(lipgloss.Color("25")).
		Bold(true).
		Padding(0, 1).
		Width(72).
		Render(fmt.Sprintf("Abora OS Installer  /  %s  (Step %d of %d)", section, step, total))
	fmt.Fprintln(os.Stderr, bar)
	fmt.Fprintln(os.Stderr, prototypeHelpStyle.Render("← Back or Esc to go back  •  "+strings.Repeat("-", 40)))
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
	fmt.Fprintln(os.Stderr, "\x1b[1;34mAbora OS Install Plan\x1b[0m")
	fmt.Fprintln(os.Stderr, "\x1b[36m"+strings.Repeat("-", 72)+"\x1b[0m")
	rows := [][2]string{
		{"Edition", plan.Edition}, {"Desktop", plan.Desktop},
		{"Hostname", plan.Hostname}, {"User", plan.Username},
		{"Full name", plan.FullName}, {"Password", present(plan.PasswordSet)},
		{"Disk", plan.Disk}, {"Layout", plan.Layout},
		{"Filesystem", plan.Filesystem}, {"Swap", plan.Swap},
		{"Encryption", plan.Encryption}, {"Timezone", plan.Timezone},
		{"Locale", plan.Locale}, {"Keyboard", plan.Keyboard},
		{"Network", plan.Network}, {"Boot", plan.BootMode},
		{"Kernel", plan.Kernel}, {"Drivers", plan.Drivers},
		{"Updates", plan.Updates}, {"Extras", plan.Extras},
		{"First boot", plan.FirstBoot}, {"Dotfiles", plan.Dotfiles},
	}
	for i := 0; i < len(rows); i += 2 {
		left := summaryCell(rows[i][0], rows[i][1])
		right := ""
		if i+1 < len(rows) {
			right = summaryCell(rows[i+1][0], rows[i+1][1])
		}
		fmt.Fprintf(os.Stderr, "%-36s%s\n", left, right)
	}
	fmt.Fprintln(os.Stderr)
	fmt.Fprintln(os.Stderr, "\x1b[36mReview this once. The next step starts the real Abora install.\x1b[0m")
}

func summaryCell(label, value string) string {
	if value == "" {
		value = "-"
	}
	return fmt.Sprintf("%-11s %s", label, value)
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
			Cursor:            "> ",
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
			Header:           title,
			Placeholder:      placeholder,
			Prompt:           "> ",
			Value:            fallback,
			Width:            42,
			CharLimit:        80,
			ShowHelp:         true,
			HeaderStyle:      aboraStyle("33", true),
			PromptStyle:      aboraStyle("33", true),
			CursorStyle:      aboraStyle("33", true),
			PlaceholderStyle: aboraStyle("246", false),
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
	for {
		password, err := promptPassword(reader)
		if err != nil {
			return "", err
		}
		if password != "" {
			cmd := exec.Command("openssl", "passwd", "-6", "-stdin")
			cmd.Stdin = strings.NewReader(password + "\n")
			out, err := cmd.Output()
			if err != nil {
				return "", fmt.Errorf("could not hash password with openssl: %w", err)
			}
			return strings.TrimSpace(string(out)), nil
		}
		fmt.Fprintln(os.Stderr, riskErrorStyle.Render("Password cannot be empty. Please type a password and press Enter."))
	}
}

func promptPassword(reader *bufio.Reader) (string, error) {
	password, err := promptPasswordTTY("Password for the primary user")
	if err == nil {
		return password, nil
	}
	return promptText(reader, "Password", "")
}

func promptPasswordTTY(prompt string) (string, error) {
	ttyFile, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		return "", err
	}
	defer ttyFile.Close()

	fmt.Fprintf(ttyFile, "\n\x1b[1;34m%s\x1b[0m\n> ", prompt)
	setTTYEcho(ttyFile, false)
	line, readErr := bufio.NewReaderSize(ttyFile, 4096).ReadString('\n')
	defer setTTYEcho(ttyFile, true)
	fmt.Fprintln(ttyFile)
	if readErr != nil && len(line) == 0 {
		return "", readErr
	}
	return strings.TrimSpace(line), nil
}

func setTTYEcho(ttyFile *os.File, enabled bool) {
	mode := "-echo"
	if enabled {
		mode = "echo"
	}
	cmd := exec.Command("stty", mode)
	cmd.Stdin = ttyFile
	cmd.Stdout = ttyFile
	cmd.Stderr = ttyFile
	_ = cmd.Run()
}

func confirmInstall(reader *bufio.Reader, interactive bool) error {
	if !interactive {
		choice, err := promptChoice(reader, "Start Abora install?", []choiceItem{
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
		Prompt:          "Start the Abora install?",
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
	if err := cmd.Run(); err != nil {
		printInstallerLogTail("/tmp/abora-install.log", 18)
		return err
	}
	return nil
}

func printInstallerLogTail(path string, lines int) {
	data, err := os.ReadFile(path)
	if err != nil || len(data) == 0 {
		return
	}
	parts := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
	if len(parts) > lines {
		parts = parts[len(parts)-lines:]
	}
	fmt.Fprintln(os.Stderr)
	fmt.Fprintln(os.Stderr, "\x1b[1;34mInstaller log tail\x1b[0m")
	fmt.Fprintln(os.Stderr, "\x1b[36m"+strings.Repeat("-", 72)+"\x1b[0m")
	for _, line := range parts {
		fmt.Fprintln(os.Stderr, line)
	}
	fmt.Fprintln(os.Stderr, "\x1b[36m"+strings.Repeat("-", 72)+"\x1b[0m")
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
			fmt.Fprint(os.Stderr, prototypeHelpStyle.Render("."))
			time.Sleep(45 * time.Millisecond)
		}
		time.Sleep(350 * time.Millisecond)
		fmt.Fprintln(os.Stderr, " "+prototypeOKStyle.Render("done"))
	}
	return nil
}
