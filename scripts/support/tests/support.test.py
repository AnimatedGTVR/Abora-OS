#!/usr/bin/env python3
"""Behaviour tests for the support tools (scripts/support/*.py): doctor,
recovery, welcome, support-report, check-full and hardware-test.

Run by scripts/check-scripts.py like the Bash suites: prints [ok]/[fail] lines
and exits 1 if any check failed. A tool runs as a real process where the
behaviour is end to end (help text, archives, interactive menus), and is
loaded as a module where a check has to control what it sees (fake lsblk
output, recorded commands). Checks that need Linux, or a POSIX shell for fake
commands, report themselves skipped elsewhere.
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import os
import subprocess
import sys
import tarfile
import tempfile
import traceback
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
SUPPORT = REPO / "scripts" / "support"
TOOLS = ("abora-doctor", "abora-recovery", "abora-welcome", "abora-support-report", "abora-check-full", "abora-hardware-test")
POSIX = os.name == "posix"
LINUX = sys.platform.startswith("linux")

CHECKS = []


class Skip(Exception):
    pass


def check(name: str):
    def register(function):
        CHECKS.append((name, function))
        return function
    return register


def load(tool: str):
    spec = importlib.util.spec_from_file_location(tool.replace("-", "_"), SUPPORT / f"{tool}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_tool(tool: str, *args: str, env: dict[str, str] | None = None, input: str | None = None) -> subprocess.CompletedProcess:
    """Run a tool; stdout and stderr come back together in .stdout."""
    return subprocess.run(
        [sys.executable, str(SUPPORT / f"{tool}.py"), *args],
        cwd=REPO, env={**os.environ, **(env or {})}, input=input,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8",
    )


def fake_command(directory: Path, name: str, body: str) -> None:
    path = directory / name
    path.write_text(f"#!/bin/sh\n{body}\n", encoding="utf-8")
    path.chmod(0o755)


def expect(text: str, *needles: str) -> None:
    missing = [needle for needle in needles if needle not in text]
    assert not missing, f"missing from output: {missing}"


def block(tool: str, start: str, end: str) -> str:
    text = (SUPPORT / f"{tool}.py").read_text(encoding="utf-8")
    assert start in text and end in text, f"{tool}.py has no {start!r} ... {end!r} block"
    return text[text.index(start):text.index(end)]


def silenced():
    return contextlib.redirect_stdout(io.StringIO())


@check("runtime: welcome and recovery help are actionable")
def _():
    welcome_help = run_tool("abora-welcome", "--help")
    recovery_help = run_tool("abora-recovery", "--help")
    welcome_bad = run_tool("abora-welcome", "nope")
    recovery_bad = run_tool("abora-recovery", "nope")
    assert welcome_help.returncode == recovery_help.returncode == 0, "--help must exit 0"
    assert welcome_bad.returncode == recovery_bad.returncode == 1, "an unknown command must exit 1"
    expect(welcome_help.stdout, "abora welcome startup off", "Show desktop, wallpaper, gaming, update, Flathub, and ANIX status")
    expect(recovery_help.stdout, "abora recovery report", "abora recovery network", "Create a redacted support archive")
    expect(welcome_bad.stdout, "Unknown welcome command: nope", "abora welcome status")
    expect(recovery_bad.stdout, "Unknown recovery command: nope", "abora recovery rollback")


@check("runtime: repair-flake-purity points at its follow-up commands")
def _():
    expect((REPO / "scripts/config/abora-repair-flake-purity.sh").read_text(encoding="utf-8"),
           "abora repair --mango", "sudo abora config apply")


@check("runtime: welcome menu choices run the right commands")
def _():
    welcome = load("abora-welcome")
    calls = []
    answers = iter(["1", "", "2", "", "6", "", "q"])
    with mock.patch.object(welcome, "run", lambda argv: calls.append(argv) or 0), \
            mock.patch("builtins.input", lambda prompt="": next(answers)), silenced():
        status = welcome.interactive_menu()
    assert status == 0, f"quitting the menu returned {status}"
    assert calls == [["abora", "doctor"], ["abora", "apps"], ["abora", "recovery"]], f"ran {calls}"


@check("runtime: recovery actions run the right commands and keep their exit status")
def _():
    recovery = load("abora-recovery")
    calls = []
    with mock.patch.object(recovery, "run", lambda argv: calls.append(argv) or 3), silenced():
        statuses = [recovery.main([action]) for action in ("rollback", "report", "doctor", "anix")]
    assert statuses == [3, 3, 3, 3], f"direct actions must pass the command's status through, got {statuses}"
    assert calls == [["anix", "rollback", "nix", "--now"], ["abora", "support-report"], ["abora", "doctor"], ["anix", "doctor"]], f"ran {calls}"


@check("runtime: recovery network diagnostics run every check and survive failures")
def _():
    recovery = load("abora-recovery")
    calls = []
    output = io.StringIO()
    with mock.patch.object(recovery, "run", lambda argv: calls.append(argv) or 1), \
            mock.patch.object(recovery.shutil, "which", lambda name: f"/fake/{name}"), contextlib.redirect_stdout(output):
        status = recovery.main(["network"])
    assert status == 0, f"network diagnostics returned {status}"
    for argv in (
        ["systemctl", "--no-pager", "--full", "status", "NetworkManager"],
        ["nmcli", "networking", "connectivity", "check"],
        ["nmcli", "radio"],
        ["resolvectl", "status"],
        ["ping", "-c", "2", "-W", "3", "1.1.1.1"],
        ["curl", "-fsI", "--connect-timeout", "5", "--max-time", "8", "https://cache.nixos.org"],
    ):
        assert argv in calls, f"did not run {argv}"
    expect(output.getvalue(), "Command exited with status 1; continuing diagnostics.")


@check("runtime: recovery menu survives a failing action and returns to the menu")
def _():
    # The menu runs exactly when the system is already broken, so a failing
    # action ("5) Run ANIX doctor" with a broken anix) must bring the menu
    # back rather than end the session.
    if not POSIX:
        raise Skip("needs a POSIX shell for the fake anix")
    with tempfile.TemporaryDirectory() as tmp:
        fake_command(Path(tmp), "anix", "exit 1")
        done = run_tool("abora-recovery", "menu", env={"PATH": f"{tmp}:{os.environ['PATH']}"}, input="5\n\nq\n")
    renders = done.stdout.count("Roll back previous generation")
    assert done.returncode == 0 and renders >= 2, f"exit status {done.returncode}, menu renders {renders} (need 0 and >=2)"


@check("runtime: welcome menu survives a failing action and returns to the menu")
def _():
    # `abora doctor` exits 1 whenever it finds any problem, which used to end
    # the first-run welcome flow on "1) Run system doctor".
    if not POSIX:
        raise Skip("needs a POSIX shell for the fake abora")
    with tempfile.TemporaryDirectory() as tmp:
        fake_command(Path(tmp), "abora", "exit 1")
        done = run_tool("abora-welcome", "menu", env={"PATH": f"{tmp}:{os.environ['PATH']}"}, input="1\n\nq\n")
    renders = done.stdout.count("Run system doctor")
    assert done.returncode == 0 and renders >= 2, f"exit status {done.returncode}, menu renders {renders} (need 0 and >=2)"


@check("runtime: welcome startup on/off writes the opt-out config and session marker")
def _():
    with tempfile.TemporaryDirectory() as tmp:
        env = {"HOME": tmp, "USERPROFILE": tmp, "XDG_CONFIG_HOME": ""}
        config = Path(tmp, ".config/abora/welcome.conf")
        marker = Path(tmp, ".cache/abora/welcome-seen")
        off = run_tool("abora-welcome", "startup", "off", env=env)
        assert off.returncode == 0 and config.read_text() == "show_on_startup=false\n" and marker.exists(), off.stdout
        on = run_tool("abora-welcome", "startup", "on", env=env)
        assert on.returncode == 0 and config.read_text() == "show_on_startup=true\n" and not marker.exists(), on.stdout
        bad = run_tool("abora-welcome", "startup", "maybe", env=env)
        assert bad.returncode == 1, f"startup maybe exited {bad.returncode}"
        expect(bad.stdout, "Usage: abora welcome startup <on|off>")


@check("runtime: doctor and welcome read abora-local.nix settings")
def _():
    doctor, welcome = load("abora-doctor"), load("abora-welcome")
    fixture = REPO / "scripts/test-fixtures/abora-local.nix"
    with mock.patch.object(doctor, "local_config", fixture), mock.patch.object(welcome, "local_config", fixture):
        assert doctor.read_local_string("abora.desktop") == "gnome"
        assert doctor.read_local_string("abora.hostname") == "test-machine"
        assert welcome.read_setting("wallpaper") == "titlis-alps.jpg"
        assert welcome.read_bool_setting("extras.diagnostics") == "false"
        assert welcome.read_setting("missing.key") == ""
    with tempfile.TemporaryDirectory() as tmp:
        legacy = Path(tmp, "abora-local.nix")
        legacy.write_text("{\n  services.desktopManager.plasma6.enable = true;\n}\n", encoding="utf-8")
        with mock.patch.object(doctor, "local_config", legacy):
            assert doctor.read_local_string("abora.desktop") == ""
            assert doctor.detect_desktop_from_local_config() == "plasma"


@check("runtime: doctor's ANIX log never follows a planted symlink")
def _():
    # The ANIX doctor log is a fixed, predictable /tmp path by design. A plain
    # open() there would let a pre-planted symlink redirect a root-run doctor's
    # write onto any file; the content it points at must survive untouched.
    if not POSIX:
        raise Skip("needs symlinks and a POSIX shell for the fake anix")
    doctor = load("abora-doctor")
    with tempfile.TemporaryDirectory() as tmp:
        sensitive, log = Path(tmp, "sensitive"), Path(tmp, "predictable.log")
        sensitive.write_text("SENSITIVE CONTENT MUST SURVIVE\n")
        log.symlink_to(sensitive)
        fake_command(Path(tmp), "anix", "echo anix doctor output")
        with mock.patch.object(doctor, "anix_log", str(log)), \
                mock.patch.dict(os.environ, {"PATH": f"{tmp}:{os.environ['PATH']}"}), silenced():
            doctor.check_anix()
        assert sensitive.read_text() == "SENSITIVE CONTENT MUST SURVIVE\n", "the symlink target was overwritten"
        assert not log.is_symlink() and log.read_text() == "anix doctor output\n", "the log was not recreated as a real file"


@check("runtime: support report redacts copied logs")
def _():
    with tempfile.TemporaryDirectory() as home, tempfile.TemporaryDirectory() as out:
        state = Path(home, "state/abora")
        state.mkdir(parents=True)
        (state / "dotfiles-import.log").write_text(
            'token = "ghp_super-secret"\nhashedPassword = "$y$j9T$secret-hash"\nordinary line\n', encoding="utf-8")
        done = subprocess.run(
            [sys.executable, str(SUPPORT / "abora-support-report.py")], cwd=REPO,
            env={**os.environ, "HOME": f"{home}/home", "XDG_STATE_HOME": f"{home}/state",
                 "ABORA_RELEASE_NAME": 'token = "report-secret"', "ABORA_SUPPORT_OUTPUT_DIR": out},
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
        )
        archive = Path(done.stdout.strip())
        assert done.returncode == 0 and archive.is_file(), f"no archive (exit {done.returncode}, stdout {done.stdout!r})"
        with tarfile.open(archive) as tar:
            folder = archive.name[: -len(".tar.gz")]
            log = tar.extractfile(f"{folder}/dotfiles-import.log").read().decode()
            report = tar.extractfile(f"{folder}/report.txt").read().decode()
    expect(log, "[redacted]", "ordinary line")
    expect(report, "[redacted]", "## System", "## Current boot journal (tail)")
    assert "super-secret" not in log and "secret-hash" not in log, "the copied log kept a secret"
    assert "report-secret" not in report, "the report header kept a secret"


@check("runtime: support report rejects bad arguments with status 2")
def _():
    missing = run_tool("abora-support-report", "--output-dir")
    unknown = run_tool("abora-support-report", "--bogus")
    assert missing.returncode == 2 and unknown.returncode == 2, f"exit {missing.returncode} / {unknown.returncode}"
    expect(missing.stdout, "--output-dir needs a directory")
    expect(unknown.stdout, "unknown argument: --bogus", "abora support-report [--output-dir DIR]")


@check("runtime: redaction is identical in abora-check-full.py and abora-support-report.py")
def _():
    # Each tool must be self-contained (see the block's own comment), so
    # nothing else keeps the two copies from drifting apart.
    report = block("abora-support-report", "# ── redaction", "# ── end redaction")
    check_full = block("abora-check-full", "# ── redaction", "# ── end redaction")
    assert report == check_full, "the redaction blocks differ"


@check("runtime: the UI block is identical in every support tool that has one")
def _():
    copies = {tool: block(tool, "# ── UI", "# ── end UI") for tool in ("abora-doctor", "abora-recovery", "abora-welcome", "abora-hardware-test")}
    differing = [tool for tool, text in copies.items() if text != copies["abora-doctor"]]
    assert not differing, f"UI block differs from abora-doctor.py in: {differing}"


@check("runtime: redaction handles Nix indented-string PSKs and full authorization headers")
def _():
    # Two credential shapes the redactor used to leak into a support archive, both reachable from files these tools
    # copy verbatim: a Nix indented string (psk = ''passphrase''), which the single-quote branch matched as an empty
    # value, and a Digest authorization header, whose credentials sit in later parameters past the first space.
    redact = load("abora-support-report").redact
    text = "\n".join([
        "  psk = ''correct horse battery staple'';",
        "  psk = ''unterminated indented string",
        'Authorization: Digest username="alice", realm="ex", response="sensitive-response"',
        "Authorization: Bearer ghp_bearer-secret",
        "Authorization: Basic dXNlcjpwYXNz",
        '  psk = "quoted-psk-secret";',
        "ordinary line mentioning a token ring network",
    ])
    out = redact(text)
    for secret in ("correct horse battery staple", "unterminated indented string", "sensitive-response", 'realm="ex"',
                   "ghp_bearer-secret", "dXNlcjpwYXNz", "quoted-psk-secret"):
        assert secret not in out, f"{secret!r} leaked: {out!r}"
    expect(out, "Authorization: Bearer [redacted]", "Authorization: Basic [redacted]", "ordinary line mentioning a token ring network")


@check("runtime: redaction handles multiline Nix indented-string credentials without gutting ordinary blocks")
def _():
    # psk = ''\n  passphrase\n''; -- a line-based redactor rewrote the opening line and left the passphrase on the next
    # one, so the report read as sanitised while still carrying the secret. The collapse must stay scoped to credential
    # keys: an ordinary extraConfig = '' ... '' block has to survive.
    redact = load("abora-support-report").redact
    out = redact("\n".join([
        "  psk = ''", "    supersecret-multiline-passphrase", "  '';",
        "  extraConfig = ''", "    keep-this-diagnostic-line", "  '';",
    ]))
    assert "supersecret-multiline-passphrase" not in out, out
    expect(out, "[redacted]", "keep-this-diagnostic-line")


@check("runtime: redaction hides credentials without devouring timestamps or host:port pairs")
def _():
    redact = load("abora-support-report").redact
    cases = {
        "Generated: 2026-08-16T16:43:28-04:00": "Generated: 2026-08-16T16:43:28-04:00",
        "port: talking to host:8080 now": "port: talking to host:8080 now",
        "url: https://user:pass@example.com/repo": "url: [redacted-user]:[redacted]@example.com/repo",
        'hashedPassword = "$y$j9T$hash";': 'hashedPassword = "[redacted]";',
        "API_KEY: abc123 next": 'API_KEY: "[redacted]" next',
        "my_token=abc": "my_token=abc",
        # sed (which this replaced) takes the longest value alternative: the
        # whole unquoted run here, not just the quoted "abc" Python would pick.
        'token="abc"def ok': 'token="[redacted]" ok',
        "a\npassword: x\nb": 'a\npassword: "[redacted]"\nb',
    }
    wrong = {text: redact(text) for text, wanted in cases.items() if redact(text) != wanted}
    assert not wrong, f"wrong redactions: {wrong}"


@check("runtime: abora-hardware-test excludes zram/loop/ram/sr/fd from disk detection")
def _():
    # zram (RAM-backed swap) reports TYPE=disk too, so it used to count as a
    # disk target and as "a fixed internal disk".
    hardware = load("abora-hardware-test")
    lsblk = "\n".join((
        'NAME="zram0" SIZE="8G" MODEL="" TRAN="" RM="0" TYPE="disk"',
        'NAME="loop0" SIZE="1G" MODEL="" TRAN="" RM="0" TYPE="disk"',
        'NAME="sda" SIZE="256G" MODEL="Fake SSD 970" TRAN="sata" RM="0" TYPE="disk"',
        'NAME="sdb" SIZE="32G" MODEL="" TRAN="usb" RM="1" TYPE="disk"',
    ))
    with mock.patch.object(hardware, "output_of", lambda *argv: lsblk):
        disks = hardware.disks()
    assert [disk["NAME"] for disk in disks] == ["sda", "sdb"], f"found {disks}"
    assert hardware.describe_disk(disks[0]) == "/dev/sda  256G  Fake SSD 970  [sata, fixed]", hardware.describe_disk(disks[0])
    assert hardware.describe_disk(disks[1]) == "/dev/sdb  32G  Unknown model  [usb, removable]", hardware.describe_disk(disks[1])


@check("runtime: abora-hardware-test runs end to end")
def _():
    # Packaged standalone (nix/pkgs/hardware-test.nix) because it has no
    # /etc/abora dependency, so it must run clean on whatever Linux machine
    # runs the checks, not just compile.
    if not LINUX:
        raise Skip("needs Linux")
    done = run_tool("abora-hardware-test")
    assert done.returncode == 0, f"exited {done.returncode}:\n{done.stdout[-2000:]}"


def main() -> int:
    failed = False
    for name, function in CHECKS:
        try:
            function()
            print(f"[ok]   {name}", flush=True)
        except Skip as reason:
            print(f"[ok]   {name} (skipped: {reason})", flush=True)
        except Exception as exc:
            failed = True
            print(f"[fail] {name}", flush=True)
            detail = str(exc) if isinstance(exc, AssertionError) else traceback.format_exc()
            for line in detail.splitlines():
                print(f"              {line}", flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
