"""Tests of the Python GUIs (gaming welcome)."""

from __future__ import annotations

import re
import subprocess
import sys

from .core import Context

GAMING_WELCOME_GUI = "scripts/abora-gaming-welcome-gui.py"

def read(ctx: Context, relative: str) -> str:
    return ctx.path(relative).read_text(encoding="utf-8")


def section(text: str, pattern: str) -> str:
    match = re.search(pattern, text, re.S)
    return match.group(0) if match else ""


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
    gaming_welcome(ctx)
