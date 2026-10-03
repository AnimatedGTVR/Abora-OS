#!/usr/bin/env python3
"""abora-hardware-test: is this machine a good candidate for Abora hardware testing?

A readiness check, not a replacement for a real USB boot and install. Exit
status 1 when the machine has no safe install target, else 0.
"""

from __future__ import annotations

import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path

SYSTEM_PATH = "/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

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

support_report_script = Path(
    os.environ.get("ABORA_SUPPORT_REPORT_SCRIPT") or Path(__file__).resolve().parent / "abora-support-report.py"
)

USAGE = """Usage:
  abora-hardware-test
  abora-hardware-test --with-report

Checks whether the current machine looks like a good candidate for Abora
hardware testing. This is a readiness check, not a replacement for a real
USB boot and install."""

# TYPE=disk alone does not mean real storage -- zram (RAM-backed swap)
# reports TYPE=disk too (lsblk -P on a real machine: /dev/zram0 TYPE="disk",
# RM="0", TRAN=""), so without this filter zram counted as a disk target and
# as "a fixed internal disk". abora-installer.sh's collect_disks() excludes
# the same name prefixes for the same reason.
NOT_A_DISK = re.compile(r"^(fd|loop|ram|sr|zram)")
LSBLK_PAIR = re.compile(r'(\w+)="([^"]*)"')


class Tally:
    passed = 0
    warnings = 0
    failures = 0


def passed(message: str) -> None:
    Tally.passed += 1
    print(f"  {GREEN}✓{NC}  {GREEN}{message}{NC}")


def warn(message: str) -> None:
    Tally.warnings += 1
    print(f"  {YELLOW}!{NC}  {YELLOW}{message}{NC}")


def fail(message: str) -> None:
    Tally.failures += 1
    print(f"  {RED}✗{NC}  {RED}{message}{NC}")


def section(title: str) -> None:
    print()
    print(f"  {ACCENT}▸ {title}{NC}")
    rule()


def output_of(*argv: str) -> str:
    """A command's stdout, or "" when it is missing or fails to start."""
    try:
        return subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, errors="replace").stdout
    except OSError:
        return ""


def memory_gib() -> float:
    try:
        meminfo = Path("/proc/meminfo").read_text(encoding="utf-8")
    except OSError:
        return 0.0
    match = re.search(r"^MemTotal:\s+(\d+)", meminfo, re.M)
    return int(match.group(1)) / 1024 / 1024 if match else 0.0


def disks() -> list[dict[str, str]]:
    """Real whole disks from lsblk: no partitions, CD-ROMs, loop, RAM or zram devices."""
    found = []
    for line in output_of("lsblk", "-dn", "-P", "-e", "7,11", "-o", "NAME,SIZE,MODEL,TRAN,RM,TYPE").splitlines():
        disk = dict(LSBLK_PAIR.findall(line))
        if disk.get("TYPE") == "disk" and not NOT_A_DISK.match(disk.get("NAME", "")):
            found.append(disk)
    return found


def describe_disk(disk: dict[str, str]) -> str:
    removable = "removable" if disk.get("RM") == "1" else "fixed"
    return (f"/dev/{disk.get('NAME', '')}  {disk.get('SIZE', '')}  {disk.get('MODEL') or 'Unknown model'}  "
            f"[{disk.get('TRAN') or 'internal'}, {removable}]")


def interfaces(prefix: str) -> list[str]:
    names = (line.split()[0] for line in output_of("ip", "-br", "link").splitlines() if line.split())
    return [name for name in names if re.match(prefix, name)]


def mentions(pattern: str, *commands: list[str]) -> bool:
    """True when any of the commands' output matches pattern, case-insensitively."""
    return any(re.search(pattern, output_of(*argv), re.I) for argv in commands if shutil.which(argv[0]))


def gpu_lines() -> list[str]:
    if not shutil.which("lspci"):
        return []
    return [line for line in output_of("lspci").splitlines()
            if re.search(r"VGA compatible controller|3D controller|Display controller", line, re.I)]


def indented(lines: list[str]) -> None:
    for line in lines:
        print(f"  {line}")


def run_support_report() -> str:
    """The archive path the support report printed, or "" if it failed."""
    try:
        done = subprocess.run([sys.executable, str(support_report_script)], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    except OSError:
        return ""
    return done.stdout.strip()


def main(args: list[str]) -> int:
    with_report = False
    for arg in args:
        if arg == "--with-report":
            with_report = True
        elif arg in ("-h", "--help"):
            print(USAGE)
            return 0
        else:
            print(f"Unknown option: {arg}\n", file=sys.stderr)
            print(USAGE, file=sys.stderr)
            return 1

    banner("Hardware Readiness Test", "Checks whether this machine is a suitable Abora test target.")
    info("This does not replace a real Abora USB boot.")

    section("Firmware and platform")
    virt = output_of("systemd-detect-virt").strip()
    if virt and virt != "none":
        warn(f"This machine appears virtualized ({virt}). Use a real machine for final confidence.")
    else:
        passed("Running on bare metal")

    if Path("/sys/firmware/efi").is_dir():
        passed("UEFI firmware detected")
    else:
        warn("No UEFI firmware detected. BIOS testing is still useful, but the UEFI path remains untested.")

    machine = platform.machine()
    if machine == "x86_64":
        passed("x86_64 platform detected")
    else:
        warn(f"Non-x86_64 platform detected: {machine}")

    section("CPU and memory")
    memory = memory_gib()
    info(f"Memory: {memory:.1f} GiB")
    if round(memory, 1) >= 4.0:
        passed("Memory meets the 4 GiB minimum for comfortable testing")
    else:
        warn("Memory is under 4 GiB. Abora may still boot, but testing could feel cramped.")

    if shutil.which("lscpu"):
        model = re.search(r"^Model name:\s*(.*)$", output_of("lscpu"), re.M)
        info(f"CPU: {model.group(1) if model else ''}")

    section("Storage")
    targets = disks()
    if targets:
        passed(f"Detected {len(targets)} disk target(s)")
        indented([describe_disk(disk) for disk in targets])
    else:
        fail("No installable disks were detected by lsblk")

    if any(disk.get("RM") == "0" for disk in targets):
        passed("At least one fixed internal disk is visible")
    else:
        fail("No fixed internal disk is visible. Abora would have nowhere safe to install.")

    transports = {disk.get("TRAN") for disk in targets}
    if "nvme" in transports:
        passed("NVMe storage is present")
    elif "sata" in transports:
        passed("SATA storage is present")
    else:
        warn("No NVMe or SATA disk transport was detected")

    section("Graphics")
    gpus = gpu_lines()
    if gpus:
        passed("Graphics controller(s) detected")
        indented(gpus)
        if any("nvidia" in line.lower() for line in gpus):
            warn("NVIDIA hardware detected. Test boot graphics, suspend, and multi-monitor behavior carefully.")
            info("The installer's GPU step (and 'abora config set gpu') can pick nouveau, nvidia, or nvidia-open.")
    else:
        warn("No graphics controller details were detected via lspci")

    section("Networking and peripherals")
    ethernet = interfaces(r"(en|eth)")
    wifi = interfaces(r"(wl|wlan)")
    if ethernet:
        passed("Ethernet interface(s) detected")
        indented(ethernet)
    else:
        warn("No Ethernet interfaces detected")

    if wifi:
        passed("Wi-Fi interface(s) detected")
        indented(wifi)
    else:
        warn("No Wi-Fi interfaces detected")

    if mentions("bluetooth", ["rfkill", "list"], ["lsusb"], ["lspci"]):
        passed("Bluetooth hardware appears to be present")
    else:
        warn("Bluetooth hardware was not detected")

    if mentions("audio", ["lspci"], ["lsusb"]):
        passed("Audio hardware appears to be present")
    else:
        warn("Audio hardware was not detected from PCI/USB data")

    section("Abora tooling")
    report_tool = support_report_script.is_file()
    if report_tool:
        passed("Support report tool is available")
    else:
        warn(f"Support report tool is not available at {support_report_script}")

    if with_report:
        if report_tool:
            report_path = run_support_report()
            if report_path and Path(report_path).is_file():
                passed(f"Support report created: {report_path}")
            else:
                warn("Support report generation did not complete cleanly")
        else:
            warn("Skipped report generation because the support report tool is unavailable")
    else:
        info("Run with --with-report to save a support archive at the same time.")

    section("Summary")
    card_start("Results")
    print(f"  {BLUE}│{NC}  {GREEN}Passed{NC}    {GREEN}{Tally.passed}{NC}")
    print(f"  {BLUE}│{NC}  {YELLOW}Warnings{NC}  {YELLOW}{Tally.warnings}{NC}")
    print(f"  {BLUE}│{NC}  {RED}Failures{NC}  {RED}{Tally.failures}{NC}")
    print(f"  {BLUE}│{NC}")
    card_end()

    if Tally.failures:
        fail("This machine is not a safe hardware test target yet.")
        return 1
    if Tally.warnings:
        warn("This machine looks usable for Abora hardware testing, but keep the warnings in mind.")
    else:
        passed("This machine looks ready for a first Abora hardware test.")
    return 0


if __name__ == "__main__":
    os.environ["PATH"] = SYSTEM_PATH + (":" + os.environ["PATH"] if os.environ.get("PATH") else "")
    ui_setup()
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
