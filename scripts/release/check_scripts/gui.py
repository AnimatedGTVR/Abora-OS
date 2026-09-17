"""Tests of the Python GUIs (installer, gaming welcome)."""

from __future__ import annotations

import re
import subprocess
import sys

from .core import Context

INSTALLER_GUI = "scripts/abora-installer-gui.py"
GAMING_WELCOME_GUI = "scripts/abora-gaming-welcome-gui.py"

# Imports the real installer GUI module and calls get_disks() with lsblk mocked.
HOTPLUG_TEST = """
import sys, json, importlib.util
from unittest import mock

spec = importlib.util.spec_from_file_location('abora_installer_gui', 'scripts/abora-installer-gui.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

fake_lsblk_json = json.dumps({
    'blockdevices': [
        {'name': 'sda', 'size': '32G', 'type': 'disk', 'model': 'USB Drive', 'hotplug': True},
        {'name': 'nvme0n1', 'size': '1T', 'type': 'disk', 'model': 'NVMe SSD', 'hotplug': False},
    ]
})

class FakeResult:
    def __init__(self, stdout):
        self.stdout = stdout
        self.returncode = 0

def fake_run(cmd, **kwargs):
    if cmd[0] == 'lsblk' and '-J' in cmd:
        return FakeResult(fake_lsblk_json)
    return FakeResult('')

with mock.patch.object(mod.subprocess, 'run', side_effect=fake_run):
    disks = mod.get_disks()

names = [d[0] for d in disks]
if '/dev/sda' in names or '/dev/nvme0n1' not in names:
    print('FAIL: %s' % (disks,))
    sys.exit(1)
print('PASS')
"""


def read(ctx: Context, relative: str) -> str:
    return ctx.path(relative).read_text(encoding="utf-8")


def section(text: str, pattern: str) -> str:
    match = re.search(pattern, text, re.S)
    return match.group(0) if match else ""


def installer_desktops(ctx: Context) -> None:
    # abora-installer-gui.py can't source the Bash desktop library, so it keeps its own
    # DESKTOPS list, which once silently lost "pantheon". Compares the real library
    # function's output against the GUI's real list, not a copy of either.
    library = ctx.run(["bash", "-c", "source scripts/abora-desktop-profiles.sh; abora_supported_desktop_profiles"], capture=True)
    bash_list = sorted(line for line in library.stdout.splitlines() if line)
    match = re.search(r"DESKTOPS = \[(.*?)\]", read(ctx, INSTALLER_GUI), re.S)
    gui_list = sorted(re.findall(r"\('(\w+)'", match.group(1))) if match else []
    name = "runtime: abora-installer-gui.py's DESKTOPS matches abora_supported_desktop_profiles"
    if ctx.result(bash_list == gui_list, name):
        return
    ctx.detail("\n".join([*(f"< {p}" for p in bash_list if p not in gui_list), *(f"> {p}" for p in gui_list if p not in bash_list)]))


def installer_gaming_queue(ctx: Context) -> None:
    text = read(ctx, INSTALLER_GUI)
    required = (
        "GAMING_CHOICES = [",
        "('gaming',     GamingPage)",
        "'gaming', 'options'",
        "'Gaming', 'Options'",
        "'gaming_enabled'",
        "'install_gaming_during_setup', 'no'",
        "'gaming_gamescope'",
        "'gaming_big_picture'",
        "queued after first boot",
    )
    ctx.result(all(item in text for item in required), "runtime: graphical installer queues Abora Gaming after first boot")


def installer_disk_filter(ctx: Context) -> None:
    # get_disks() re-implements the TUI installer's disk-name filter in Python and once
    # drifted, offering /dev/zram0 as an install target. Compares the GUI's real
    # exclusion tuple against the TUI's real awk regex.
    tui_filter = ctx.grep_output("-oE", r"\^\(fd\|loop\|ram\|sr\|zram\)", "scripts/abora-installer.sh").splitlines()[:1]
    match = re.search(r"name\.startswith\(\((.*?)\)\)", read(ctx, INSTALLER_GUI))
    gui_prefixes = ",".join(sorted(re.findall(r"'(\w+)'", match.group(1)))) if match else ""
    ctx.result(
        bool(tui_filter and tui_filter[0]) and gui_prefixes == "fd,loop,ram,sr,zram",
        "runtime: abora-installer-gui.py's disk filter excludes ram/zram like abora-installer.sh",
    )


def installer_hotplug(ctx: Context) -> None:
    # lsblk -J emits HOTPLUG as a JSON boolean; comparing it to the string '1' never
    # excluded anything, so a second USB drive was offered as an install target.
    gtk = ctx.run([sys.executable, "-c", "import gi; gi.require_version('Gtk','4.0')"], quiet=True)
    if gtk.returncode != 0:
        ctx.ok("PyGObject/Gtk4 unavailable (get_disks hotplug test skipped)")
        return
    probe = ctx.run([sys.executable, "-c", HOTPLUG_TEST], capture=True)
    output = probe.stdout.rstrip("\n")
    if not ctx.result(output == "PASS", "runtime: abora-installer-gui.py's get_disks() excludes hotplug-flagged disks"):
        ctx.detail(output)


def gaming_welcome(ctx: Context) -> None:
    text = read(ctx, GAMING_WELCOME_GUI)

    # The Sign In card treats Steam as installed via read_installed_apps() OR
    # shutil.which('steam'); the Platforms row must use the same detection.
    platform_state = section(text, r"def _set_platform_button_state.*?(?=\n    def )")
    ctx.result(
        "_steam_installed()" in platform_state,
        "runtime: gaming welcome Platforms Steam row matches Sign In's installed detection",
    )

    sudo = section(text, r"def sudo_prefix\(\).*?(?=\n\ndef )")
    enable = section(text, r"def _enable_gaming\(self\).*?(?=\n    def )")
    install = section(text, r"def _install\(self, app_id: str\).*?(?=\n    def )")
    command = section(text, r"def command_path\(tool: str\).*?(?=\n\ndef )")
    ctx.result(
        "SUDO_ASKPASS" in sudo
        and "No graphical privilege helper found" in sudo
        and "sudo_prefix_or_status(self)" in enable
        and "sudo_prefix_or_status(self)" in install
        and "'abora': '/etc/abora/abora.sh'" in command
        and "'abora-update': '/etc/abora/update.sh'" in command,
        "runtime: gaming welcome handles missing GUI privilege helper cleanly",
    )

    formatter = section(text, r"def command_failure_message\(proc: subprocess.CompletedProcess\).*?(?=\n\ndef )")
    runner = section(text, r"def _run_background\(self, label: str, command: list\[str\], on_done\).*?(?=\n    def )")
    done = section(text, r"def _on_background_done\(self, ok: bool, message: str, on_done\).*?(?=\n    def )")
    ctx.result(
        "ABORA_GAMING_WELCOME_TIMEOUT" in text
        and bool(formatter)
        and all(s in formatter for s in (
            "proc.stdout", "proc.stderr", "Failed — run abora gaming doctor or abora logs", "fetcher-cache.*sqlite",
            "local fetch-cache disk I/O error", "abora gaming repair-cache", "nix-collect-garbage -d",
        ))
        and bool(runner)
        and all(s in runner for s in (
            "command_failure_message(proc)", "COMMAND_TIMEOUT_SECONDS", "subprocess.TimeoutExpired",
            "slow connection or cold cache", "_set_busy(True)",
        ))
        and bool(done)
        and "_refresh_buttons()" in done
        and "_set_busy(False)" in done
        and all(s in text for s in ("Gaming Doctor", "['doctor']", "Repair Nix Cache", "['repair-cache']", "def _run_local_tool")),
        "runtime: gaming welcome shows app-manager failures, repair tools, and locks duplicate actions",
    )


def run(ctx: Context) -> None:
    installer_desktops(ctx)
    installer_gaming_queue(ctx)
    installer_disk_filter(ctx)
    installer_hotplug(ctx)
    gaming_welcome(ctx)
