#!/usr/bin/env python3
"""abora welcome: first-run status and quick actions."""

from __future__ import annotations

import contextlib
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# ── UI ────────────────────────────────────────────────────────────────────────
# Python port of the abora-ui.sh primitives. Inlined, not imported: `abora
# update` on a 4.0 system copies each support tool into /etc/nixos/abora on
# its own (sync_abora_files in abora-update.sh), so a shared module would never
# reach it. Every scripts/support/*.py tool carries this same block, and
# tests/support.test.py keeps the copies identical.

BLUE = "\033[38;5;33m"
ACCENT = "\033[38;5;87m"
CYAN = "\033[38;5;44m"
YELLOW = "\033[38;5;222m"
WHITE = "\033[1;97m"
DIM = "\033[38;5;242m"
FAINT = "\033[38;5;237m"
GREEN = "\033[38;5;77m"
RED = "\033[38;5;203m"
NC = "\033[0m"


def ui_setup() -> None:
    # Line buffering keeps our output ordered with the child processes we run.
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace", line_buffering=True)


def ui_version() -> str:
    if os.environ.get("ABORA_VERSION"):
        return os.environ["ABORA_VERSION"]
    try:
        return "".join(Path("/etc/abora/VERSION").read_text(encoding="utf-8").split())
    except OSError:
        return "v4 Everest"


def ui_cols() -> int:
    return shutil.get_terminal_size((80, 24)).columns


def rule() -> None:
    print(f"  {FAINT}{'─' * (ui_cols() - 4)}{NC}")


def brand_header() -> None:
    inner = max(ui_cols() - 6, 18)
    left, right = "  ▸ ABORA OS", f"{ui_version()}  "
    max_left = max(inner - len(right) - 1, 6)
    if len(left) > max_left:
        left = left[: max_left - 3] + "..."
    pad = max(inner - len(left) - len(right), 1)
    print(f"{BLUE}╭{'─' * inner}╮{NC}")
    print(f"{BLUE}│{NC}{WHITE}{left}{NC}{' ' * pad}{DIM}{right}{NC}{BLUE}│{NC}")
    print(f"{BLUE}╰{'─' * inner}╯{NC}")


def banner(title: str = "", subtitle: str = "") -> None:
    print()
    brand_header()
    if title:
        print(f"\n  {WHITE}{title}{NC}")
    if subtitle:
        print(f"  {DIM}{subtitle}{NC}")
    print()
    rule()
    print()


def info(message: str) -> None:
    print(f"  {BLUE}·{NC}  {message}")


def success(message: str) -> None:
    print(f"  {GREEN}✓{NC}  {GREEN}{message}{NC}")


def warning(message: str) -> None:
    print(f"  {YELLOW}!{NC}  {YELLOW}{message}{NC}")


def error(message: str) -> None:
    print(f"  {RED}✗{NC}  {RED}{message}{NC}", file=sys.stderr)


def step(message: str) -> None:
    print(f"  {CYAN}▸{NC}  {message}")


def dim_line(message: str) -> None:
    print(f"  {DIM}{message}{NC}")


def kv(key: str, value: str, width: int = 18) -> None:
    print(f"  {BLUE}│{NC}  {DIM}{key:<{width}}{NC}  {CYAN}{value}{NC}")


def _card_inner() -> int:
    return min(max(ui_cols() - 6, 20), 70)


def card_start(title: str = "") -> None:
    inner = _card_inner()
    if title:
        body = f"{ACCENT} {title} " + "─" * max(inner - len(title) - 3, 0)
    else:
        body = "─" * inner
    print(f"  {BLUE}╭─{body}╮{NC}")


def card_end() -> None:
    print(f"  {BLUE}╰{'─' * (_card_inner() + 1)}╯{NC}")

# ── end UI ────────────────────────────────────────────────────────────────────

home = Path.home()
# These two files are also read directly by profile.d/abora-welcome.sh (shell
# login banner) and the abora-welcome-gui.desktop autostart entry
# (installed-base.nix) -- welcome_config's show_on_startup=false is the
# permanent "don't show again" opt-out, while welcome_marker just tracks
# whether this particular session has already shown it once.
welcome_config = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config") / "abora" / "welcome.conf"
welcome_marker = home / ".cache" / "abora" / "welcome-seen"
local_config = Path(os.environ.get("ABORA_SYSTEM_CONFIG") or "/etc/nixos") / "abora-local.nix"


def run(argv: list[str]) -> int:
    try:
        return subprocess.run(argv).returncode
    except OSError:
        print(f"{argv[0]}: command not found", file=sys.stderr)
        return 127


def set_startup(value: str) -> int:
    welcome_config.parent.mkdir(parents=True, exist_ok=True)
    welcome_marker.parent.mkdir(parents=True, exist_ok=True)
    if value in ("on", "true", "yes", "1"):
        welcome_config.write_text("show_on_startup=true\n", encoding="utf-8")
        welcome_marker.unlink(missing_ok=True)
        success("Abora Welcome will show on startup.")
        return 0
    if value in ("off", "false", "no", "0"):
        welcome_config.write_text("show_on_startup=false\n", encoding="utf-8")
        welcome_marker.touch()
        success("Abora Welcome will not show on startup.")
        return 0
    error("Usage: abora welcome startup <on|off>")
    return 1


def read_setting(key: str, value_pattern: str = r'"([^"]+)";') -> str:
    """The first `abora.<key> = <value>` in abora-local.nix, or ""."""
    try:
        lines = local_config.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return ""
    pattern = re.compile(r"\s*abora\." + re.escape(key) + r"\s*=\s*" + value_pattern)
    for line in lines:
        match = pattern.match(line)
        if match:
            return match.group(1)
    return ""


def read_bool_setting(key: str) -> str:
    return read_setting(key, r"(true|false)")


def flathub_configured() -> bool:
    if not shutil.which("flatpak"):
        return False
    remotes = subprocess.run(["flatpak", "remotes", "--system"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout
    return "flathub" in (line.split()[0] for line in remotes.splitlines() if line.split())


def show_status() -> None:
    channel = os.environ.get("ABORA_DEFAULT_CHANNEL") or "unstable"
    channel_file = Path("/etc/nixos/abora/channel")
    if channel_file.is_file():
        channel = "".join(channel_file.read_text(encoding="utf-8").split())

    card_start("System")
    kv("desktop", read_setting("desktop") or "unknown")
    kv("wallpaper", read_setting("wallpaper") or "unknown")
    kv("Gaming", "enabled" if read_bool_setting("gaming.enable") == "true" else "off")
    kv("updates", channel)
    kv("Flathub", "configured" if flathub_configured() else "not configured")
    kv("ANIX", "ready" if Path("/etc/nixos/anix.nix").is_file() else "not initialized")
    card_end()


def menu() -> None:
    banner("Welcome To Abora", "A few useful first steps.")
    show_status()
    print()
    print(f"  {CYAN}1{NC}  Run system doctor")
    print(f"  {CYAN}2{NC}  Open app manager")
    print(f"  {CYAN}3{NC}  Open gaming setup")
    print(f"  {CYAN}4{NC}  Create first ANIX snapshot")
    print(f"  {CYAN}5{NC}  Switch desktop")
    print(f"  {CYAN}6{NC}  Open recovery tools")
    print(f"  {DIM}q{NC}  Quit\n")


def usage() -> None:
    banner("Welcome", "First-run status and quick actions.")
    for command, description in (
        ("abora welcome", "Open the interactive welcome menu."),
        ("abora welcome status", "Show desktop, wallpaper, gaming, update, Flathub, and ANIX status."),
        ("abora welcome startup on", "Show Abora Welcome automatically after login."),
        ("abora welcome startup off", "Stop showing Abora Welcome automatically."),
    ):
        print(f"  {CYAN}{command}{NC}")
        dim_line(f"  {description}")
        print()


MENU_CHOICES = {
    "1": ["abora", "doctor"],
    "2": ["abora", "apps"],
    "3": ["abora", "gaming", "status"],
    "4": ["anix", "save", "anix: first Abora snapshot"],
    "5": ["abora", "desktop", "list"],
    "6": ["abora", "recovery"],
}


def interactive_menu() -> int:
    while True:
        menu()
        try:
            choice = input("  Choose: ")
        except EOFError:
            return 1
        # A failing choice's status is deliberately ignored, so it returns to
        # the menu instead of ending the first-run welcome flow. `abora
        # doctor` in particular exits 1 whenever it finds any problem at all:
        # on a brand-new install with one flagged issue, "1) Run system
        # doctor" (a very plausible first click) would otherwise end the
        # session before the user ever saw the other options.
        if choice in ("q", "Q"):
            return 0
        if choice in MENU_CHOICES:
            run(MENU_CHOICES[choice])
        else:
            warning(f"Unknown choice: {choice}")
        print()
        try:
            input("  Press Enter to continue...")
        except EOFError:
            return 1


def main(args: list[str]) -> int:
    command = args[0] if args else "menu"
    if command == "status":
        banner("Welcome To Abora", "Current system status.")
        show_status()
        print()
        return 0
    if command in ("menu", ""):
        return interactive_menu()
    if command in ("help", "--help", "-h"):
        usage()
        return 0
    if command == "startup":
        return set_startup(args[1] if len(args) > 1 else "")
    error(f"Unknown welcome command: {command}")
    with contextlib.redirect_stdout(sys.stderr):
        usage()
    return 1


if __name__ == "__main__":
    ui_setup()
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
