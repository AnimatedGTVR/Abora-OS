package abora

import (
	"strings"
	"testing"
)

func TestEditionChoicesReturnInstallerIDs(t *testing.T) {
	choices := editionChoices()
	if len(choices) != len(editions) {
		t.Fatalf("expected %d choices, got %d", len(editions), len(choices))
	}
	if choices[0] != "COSMIC Edition:cosmic" {
		t.Fatalf("expected COSMIC choice first, got %q", choices[0])
	}
}

func TestInstallerActionChoices(t *testing.T) {
	choices := installerActionChoices("Install", "Live")
	if strings.Join(choices, ",") != "Install:install,Live:live" {
		t.Fatalf("unexpected choices: %#v", choices)
	}
}

func TestRiskPanelIncludesRequiredWarning(t *testing.T) {
	panel := renderRiskPanel()
	for _, want := range []string{
		preAlphaWarningTitle,
		"Prevent your system from booting",
		"Cause data loss",
	} {
		if !strings.Contains(panel, want) {
			t.Fatalf("expected panel to contain %q", want)
		}
	}
}

func TestRenderLogoMissingFileCanFallback(t *testing.T) {
	if err := renderLogo("/definitely/not/a/real/abora-logo.png", "120", "auto", "2k", true); err != nil {
		t.Fatalf("expected missing logo fallback to succeed: %v", err)
	}
}

func TestRenderLogoMissingFileCanFail(t *testing.T) {
	if err := renderLogo("/definitely/not/a/real/abora-logo.png", "120", "auto", "2k", false); err == nil {
		t.Fatal("expected missing logo without fallback to fail")
	}
}

func TestTerminalInfoDetectsAlacritty(t *testing.T) {
	if !((terminalInfo{Term: "alacritty"}).isAlacritty()) {
		t.Fatal("expected TERM=alacritty to be detected")
	}
	if !((terminalInfo{TermProgram: "Alacritty"}).isAlacritty()) {
		t.Fatal("expected TERM_PROGRAM=Alacritty to be detected")
	}
}

func TestTerminalInfoDescribesAlacrittyImageSupport(t *testing.T) {
	got := (terminalInfo{Term: "alacritty"}).imageSupportSummary()
	if !strings.Contains(got, "no") || !strings.Contains(got, "Alacritty") {
		t.Fatalf("expected Alacritty support warning, got %q", got)
	}
}

func TestTerminalInfoDetectsLinuxTTY(t *testing.T) {
	if !((terminalInfo{Term: "linux"}).isLinuxTTY()) {
		t.Fatal("expected TERM=linux to be detected as TTY")
	}
}

func TestTerminalInfoDescribesLinuxTTYImageSupport(t *testing.T) {
	got := (terminalInfo{Term: "linux"}).imageSupportSummary()
	if !strings.Contains(got, "no") || !strings.Contains(got, "TTY") {
		t.Fatalf("expected Linux TTY support warning, got %q", got)
	}
}

func TestTerminalInfoDescribesKittyImageSupport(t *testing.T) {
	got := (terminalInfo{KittyWindowID: "1"}).imageSupportSummary()
	if !strings.Contains(got, "yes") || !strings.Contains(got, "Kitty") {
		t.Fatalf("expected Kitty support summary, got %q", got)
	}
}
