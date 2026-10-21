#!/usr/bin/env python3
"""anix doctor (also abora doctor): check installed-system health, explain it, and repair it.

  anix doctor                 check everything and explain what's wrong
  anix doctor --json          the same findings as JSON, for support and bug reports
  anix doctor repair          list the repairs the last check suggests
  anix doctor repair <id>...  run those repairs (asks first; --yes to skip)

Every check produces findings: an id, an area, a status (ok, warn, fail, skip), a one-line summary,
a plain-English explanation and, where a safe fix exists, a repair. A repair is only ever an existing
Abora/ANIX/NixOS command, shown before it runs, so `doctor repair` never does anything a user
couldn't type themselves.

Exit status: 1 if any check failed, else 0 (warnings alone still exit 0).
"""

from __future__ import annotations

import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

SYSTEM_PATH = "/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Abora's shared core (abora_core.py): beside this tool in a checkout, on the live ISO and in the
# hardware-test package; in /etc/abora on an installed system, where each tool is its own Nix store file.
sys.path[:0] = [str(Path(__file__).resolve().parent), "/etc/abora"]
from abora_core import NC, RED, WHITE, banner, dim_line, error, success, ui_setup, warning

config_dir = Path(os.environ.get("ABORA_SYSTEM_CONFIG") or "/etc/nixos")
abora_dir = Path(os.environ.get("ABORA_DIR") or "/etc/abora")
local_config = config_dir / "abora-local.nix"
anix_log = "/tmp/abora-anix-doctor.log"
# What the checks read from the running system. Tests point these at fixtures.
sysfs = Path(os.environ.get("ABORA_DOCTOR_SYSFS") or "/sys")
mounts_file = Path(os.environ.get("ABORA_DOCTOR_MOUNTS") or "/proc/mounts")
route_file = Path(os.environ.get("ABORA_DOCTOR_ROUTE") or "/proc/net/route")
DNS_PROBE_HOST = os.environ.get("ABORA_DOCTOR_DNS_HOST") or "cache.nixos.org"

# First match wins, so more specific markers come first.
DESKTOP_MARKERS = (
    ("services.desktopManager.gnome.enable = true;", "gnome"),
    ("services.desktopManager.plasma6.enable = true;", "plasma"),
    ("programs.hyprland", "hyprland"),
    ("programs.sway.enable = true;", "sway"),
    ("desktopManager.xfce.enable = true;", "xfce"),
    ("desktopManager.cinnamon.enable = true;", "cinnamon"),
    ("desktopManager.mate.enable = true;", "mate"),
    ("desktopManager.budgie.enable = true;", "budgie"),
    ("desktopManager.lxqt.enable = true;", "lxqt"),
    ("desktopManager.pantheon.enable = true;", "pantheon"),
    ("desktopManager.cosmic.enable = true;", "cosmic"),
    ("desktopManager.enlightenment.enable = true;", "enlightenment"),
    ("windowManager.i3.enable = true;", "i3"),
    ("windowManager.awesome.enable = true;", "awesome"),
    ("windowManager.openbox.enable = true;", "openbox"),
    ("programs.niri.enable = true;", "niri"),
    ("programs.river.enable = true;", "river"),
    ("windowManager.qtile.enable = true;", "qtile"),
    ("windowManager.bspwm.enable = true;", "bspwm"),
    ("windowManager.fluxbox.enable = true;", "fluxbox"),
    ("windowManager.icewm.enable = true;", "icewm"),
    ("windowManager.herbstluftwm.enable = true;", "herbstluftwm"),
)

# Free-space thresholds. NixOS needs room to build a new generation before it can drop old ones,
# so a nearly full disk makes `abora update` itself fail -- worth catching early.
ROOT_FAIL_BYTES = 2 * 1024**3
ROOT_WARN_BYTES = 10 * 1024**3
# Each NixOS generation can copy a kernel and initrd onto the EFI partition; a full ESP is the
# classic "update worked, bootloader install failed" error.
BOOT_WARN_BYTES = 64 * 1024**2

# PCI vendor ids for display controllers (class 0x03xxxx).
GPU_VENDORS = {"0x10de": "nvidia", "0x1002": "amd", "0x8086": "intel"}
# The kernel modules each abora.gpu setting should leave loaded.
GPU_MODULES = {
    "nvidia": ("nvidia",),
    "nvidia-open": ("nvidia",),
    "nouveau": ("nouveau",),
    "amdgpu": ("amdgpu",),
    "intel": ("i915", "xe"),
}


@dataclass
class Repair:
    id: str
    description: str
    command: list[str]
    root: bool = False


@dataclass
class Finding:
    id: str
    area: str
    status: str  # ok, warn, fail, skip
    summary: str
    explanation: str = ""
    repair: Repair | None = None
    details: dict = field(default_factory=dict)


findings: list[Finding] = []


def report(id: str, area: str, status: str, summary: str, explanation: str = "", repair: Repair | None = None, **details) -> None:
    findings.append(Finding(id, area, status, summary, explanation, repair, details))


class Tally:
    @staticmethod
    def count(status: str) -> int:
        return sum(1 for f in findings if f.status == status)


def run(argv: list[str], timeout: float = 20) -> subprocess.CompletedProcess | None:
    try:
        return subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None


def local_config_text() -> str:
    try:
        return local_config.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def read_local_string(key: str) -> str:
    """The first `key = "value";` line of abora-local.nix, or ""."""
    pattern = re.compile(r'\s*' + re.escape(key) + r'\s*=\s*"([^"]+)";')
    for line in local_config_text().splitlines():
        match = pattern.match(line)
        if match:
            return match.group(1)
    return ""


def detect_desktop_from_local_config() -> str:
    text = local_config_text()
    return next((name for marker, name in DESKTOP_MARKERS if marker in text), "")


def read_mounts() -> list[tuple[str, str, str, list[str]]]:
    """(device, mount point, fs type, options) for every mounted filesystem."""
    try:
        lines = mounts_file.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []
    out = []
    for line in lines:
        parts = line.split()
        if len(parts) >= 4:
            # /proc/mounts escapes spaces in paths as \040.
            out.append((parts[0], parts[1].replace("\\040", " "), parts[2], parts[3].split(",")))
    return out


def mount_for(path: str) -> tuple[str, str, str, list[str]] | None:
    """The mount `path` lives on: the longest mount point that contains it."""
    best = None
    for entry in read_mounts():
        point = entry[1]
        if point == "/" or path == point or path.startswith(point + "/"):
            if best is None or len(point) > len(best[1]):
                best = entry
    return best


# ── checks ────────────────────────────────────────────────────────────────────

def check_install_files() -> None:
    files = (
        (config_dir / "flake.nix", "flake.nix", "The system config is a flake; without flake.nix nothing can rebuild."),
        (local_config, "abora-local.nix", "The installer writes your settings here (hostname, desktop, user)."),
        (abora_dir / "update.sh", "Abora update tool", "Needed by anix update."),
        (abora_dir / "theme-sync.sh", "Abora theme sync", "Keeps desktop themes in step with the system."),
        (abora_dir / "support-report.sh", "Abora support report", "Collects diagnostics for bug reports."),
        (abora_dir / "anix.sh", "ANIX", "The anix command itself."),
        (abora_dir / "bootloader/theme.txt", "bootloader theme", "The Abora boot menu theme."),
        (abora_dir / "plymouth/abora.plymouth", "Plymouth theme", "The Abora boot splash."),
    )
    missing = [(path, label, why) for path, label, why in files if not path.exists()]
    if not missing:
        report("abora-files", "abora", "ok", "Abora system files are in place")
        return
    for path, label, why in missing:
        if abora_dir not in path.parents:
            report(f"abora-file-{path.name}", "abora", "fail", f"{label} is missing: {path}",
                   f"{why} Nothing rebuilds this file; restore it from an ANIX snapshot (`anix generations`, "
                   "or the Git history in /etc/nixos) or from a backup.")
    # Everything in /etc/abora comes from the system config, so a rebuild puts it back.
    built = [(path, label, why) for path, label, why in missing if abora_dir in path.parents]
    if len(built) == 1:
        path, label, why = built[0]
        report(f"abora-file-{path.name}", "abora", "fail", f"{label} is missing: {path}",
               f"{why} Files in /etc/abora go missing when an update stopped part-way; rebuilding the current "
               "config puts them back.",
               Repair("rebuild", "Rebuild the current system config", ["anix", "apply"]))
    elif built:
        report("abora-files", "abora", "fail", f"{len(built)} Abora system files are missing from {abora_dir}",
               "Files in /etc/abora go missing when an update stopped part-way, or this isn't an installed "
               "Abora system. Rebuilding the current config puts them back.",
               Repair("rebuild", "Rebuild the current system config", ["anix", "apply"]),
               missing=[str(path) for path, _, _ in built])


def check_bootloader() -> None:
    uefi = (sysfs / "firmware/efi").is_dir()
    mode = "UEFI" if uefi else "BIOS"
    boot = mount_for("/boot")
    if uefi:
        if boot is None or boot[1] != "/boot":
            report("boot-esp-mounted", "bootloader", "fail", "The EFI system partition isn't mounted at /boot",
                   "On UEFI, NixOS installs each new generation's boot entry onto the EFI partition at /boot. "
                   "With it unmounted, updates build fine but the next boot still starts the old system, or "
                   "fails to find a kernel. Check the /boot line in hardware-configuration.nix.",
                   mode=mode)
            return
        if boot[2] not in ("vfat", "msdos"):
            report("boot-esp-fs", "bootloader", "warn", f"/boot is {boot[2]}, not FAT",
                   "UEFI firmware can only read FAT partitions, so a non-FAT /boot usually means the EFI "
                   "partition isn't the one mounted there.", mode=mode, fstype=boot[2])
            return
    try:
        free = shutil.disk_usage("/boot").free if Path("/boot").is_dir() else None
    except OSError:
        free = None
    if free is not None and uefi and free < BOOT_WARN_BYTES:
        report("boot-space", "bootloader", "warn", f"Only {free // 1024**2} MB free on the EFI partition",
               "Each kept generation can put its own kernel and initrd on /boot. When it fills up, the next "
               "update fails while installing the bootloader. Removing old generations frees it.",
               Repair("gc-generations", "Remove generations older than 14 days, then rewrite the boot menu",
                      ["anix", "gc", "old"], root=False), mode=mode, free_bytes=free)
        return
    report("boot", "bootloader", "ok", f"Bootloader looks healthy ({mode})", mode=mode)


def check_nix() -> None:
    nix, rebuild = shutil.which("nix"), shutil.which("nixos-rebuild")
    if not nix or not rebuild:
        missing = " and ".join(name for name, path in (("nix", nix), ("nixos-rebuild", rebuild)) if not path)
        report("nix-tools", "nix", "fail", f"{missing} not found",
               "Abora is built and updated by Nix; without these, nothing can rebuild. This normally only "
               "happens when PATH is stripped (for example under a minimal sudo).")
        return
    report("nix-tools", "nix", "ok", "nix and nixos-rebuild are available")
    if (config_dir / "flake.nix").is_file() and not (config_dir / "flake.lock").is_file():
        report("nix-flake-lock", "nix", "warn", "flake.lock is missing",
               "Without flake.lock, the next rebuild picks whatever nixpkgs is newest instead of the "
               "release-pinned one, and `anix package install` can't pin to the system's nixpkgs. Restore it from "
               "the Git history in /etc/nixos if it's there.")
    store = run(["nix", "store", "ping"], timeout=15) or run(["nix", "store", "info"], timeout=15)
    if store is not None and store.returncode != 0 and "daemon" in (store.stdout or "").lower():
        report("nix-daemon", "nix", "fail", "The Nix daemon isn't answering",
               "Every rebuild and package install goes through nix-daemon. Restarting it usually fixes this.",
               Repair("restart-nix-daemon", "Restart nix-daemon", ["systemctl", "restart", "nix-daemon.service"], root=True))


def check_channel() -> None:
    channel = os.environ.get("ABORA_DEFAULT_CHANNEL") or "unstable"
    channel_file = config_dir / "abora" / "channel"
    if channel_file.is_file():
        channel = "".join(channel_file.read_text(encoding="utf-8").split())
    if channel in ("stable", "demo", "dev", "unstable"):
        report("channel", "updates", "ok", f"Update channel: {channel}", channel=channel)
    else:
        report("channel", "updates", "warn", f"Unknown update channel: {channel}",
               "anix update reads the channel from /etc/nixos/abora/channel. An unknown name means it can't "
               "find a release to update to.",
               Repair("channel-stable", "Set the update channel to stable", ["anix", "channel", "set", "stable"], root=True),
               channel=channel)


def supported_desktops() -> list[str]:
    profiles = abora_dir / "desktop-profiles.sh"
    if not profiles.is_file():
        return []
    listed = subprocess.run(
        ["bash", "-c", 'source "$1"; abora_supported_desktop_profiles', "bash", str(profiles)],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    return listed.stdout.splitlines()


def check_desktop() -> None:
    desktop = (
        read_local_string("abora.desktop")
        or read_local_string("system.nixos.variant_id")
        or detect_desktop_from_local_config()
    )
    if not desktop:
        report("desktop", "desktop", "warn", "No desktop setting in abora-local.nix",
               "anix can't tell which desktop this system should start.")
        return
    known = supported_desktops()
    if known and desktop not in known:
        report("desktop", "desktop", "warn", f"Desktop profile may be invalid: {desktop}",
               "This name isn't one of Abora's desktop profiles, so a rebuild may fail or start no desktop. "
               "`anix desktop list` shows the valid ones.", desktop=desktop)
        return
    report("desktop", "desktop", "ok", f"Desktop profile: {desktop}", desktop=desktop)
    if desktop == "none" or not shutil.which("systemctl"):
        return
    active = run(["systemctl", "is-active", "display-manager.service"], timeout=5)
    state = (active.stdout.strip() if active else "") or "unknown"
    if state == "failed":
        report("desktop-session", "desktop", "fail", "The display manager (login screen) failed to start",
               "The desktop is configured but the login screen service crashed. Its log says why: "
               "journalctl -b -u display-manager. A failed GPU driver is the usual cause; see the GPU check.",
               Repair("restart-display-manager", "Restart the login screen", ["systemctl", "restart", "display-manager.service"], root=True))
    elif state not in ("active", "unknown", "activating"):
        report("desktop-session", "desktop", "warn", f"The display manager is {state}",
               "The login screen isn't running. That's expected over SSH or on a server, not on a desktop install.")


def pci_gpus() -> list[str]:
    devices = sysfs / "bus/pci/devices"
    found = []
    try:
        entries = sorted(devices.iterdir())
    except OSError:
        return found
    for device in entries:
        try:
            pci_class = (device / "class").read_text().strip()
            vendor = (device / "vendor").read_text().strip()
        except OSError:
            continue
        if pci_class.startswith("0x03") and vendor in GPU_VENDORS:
            found.append(GPU_VENDORS[vendor])
    return found


def check_gpu() -> None:
    gpus = pci_gpus()
    setting = read_local_string("abora.gpu") or "auto"
    if not gpus:
        report("gpu", "gpu", "skip", "No NVIDIA, AMD or Intel GPU found", gpus=gpus, setting=setting)
        return
    loaded = [name for name in ("nvidia", "nouveau", "amdgpu", "i915", "xe") if (sysfs / "module" / name).is_dir()]
    if setting in GPU_MODULES:
        expected = GPU_MODULES[setting]
        if not any(module in loaded for module in expected):
            report("gpu-driver", "gpu", "fail", f"abora.gpu is {setting}, but its driver isn't loaded",
                   f"The config asks for the {setting} driver ({'/'.join(expected)}), and the running kernel "
                   "doesn't have it. If you just changed abora.gpu, reboot. If it persists, Secure Boot can block "
                   "the NVIDIA module, and `journalctl -b -k | grep -i -e nvidia -e drm` shows why.",
                   gpus=gpus, setting=setting, loaded=loaded)
            return
    elif "nvidia" in gpus and "nvidia" not in loaded:
        report("gpu-driver", "gpu", "warn", "NVIDIA GPU is using the open-source nouveau driver",
               "nouveau works for desktops, but games and CUDA need NVIDIA's driver. Set it with "
               "`anix config set gpu nvidia-open` (Turing and newer) or `nvidia`, then `anix config apply`.",
               gpus=gpus, setting=setting, loaded=loaded)
        return
    report("gpu-driver", "gpu", "ok", f"GPU driver loaded: {', '.join(loaded) or 'none needed'}",
           gpus=gpus, setting=setting, loaded=loaded)


def has_default_route() -> bool:
    try:
        lines = route_file.read_text(encoding="utf-8").splitlines()[1:]
    except OSError:
        return True  # can't tell; let the DNS check speak
    return any(len(parts) > 2 and parts[1] == "00000000" for parts in (line.split() for line in lines))


def check_network() -> None:
    if not has_default_route():
        report("network", "network", "warn", "No network connection (no default route)",
               "This computer isn't connected to a network, so updates and package installs can't download "
               "anything. `anix network` walks through Wi-Fi and cable checks.")
        return
    previous = socket.getdefaulttimeout()
    socket.setdefaulttimeout(5)
    started = time.monotonic()
    try:
        socket.getaddrinfo(DNS_PROBE_HOST, 443)
    except OSError:
        report("network-dns", "network", "fail", f"DNS can't resolve {DNS_PROBE_HOST}",
               "The network is up but names don't resolve, so Nix can't reach its binary cache. Restarting "
               "NetworkManager re-reads DNS from the network; `anix network` shows more.",
               Repair("restart-networkmanager", "Restart NetworkManager", ["systemctl", "restart", "NetworkManager.service"], root=True))
        return
    finally:
        socket.setdefaulttimeout(previous)
    report("network-dns", "network", "ok", f"Network and DNS work ({int((time.monotonic() - started) * 1000)} ms)")


def check_disk() -> None:
    root = mount_for("/")
    if root is not None and "ro" in root[3]:
        report("disk-readonly", "disk", "fail", "The root filesystem is mounted read-only",
               "Linux remounts a filesystem read-only when it finds errors on it. Nothing can be updated or "
               "saved until it's checked. Back up what matters, then run a filesystem check from the Abora "
               "live USB (`fsck` on the root partition).", device=root[0])
        return
    for path, label in (("/nix", "the Nix store"), ("/", "the root filesystem")):
        try:
            free = shutil.disk_usage(path).free
        except OSError:
            continue
        gb = free / 1024**3
        if free < ROOT_FAIL_BYTES:
            report("disk-space", "disk", "fail", f"Only {gb:.1f} GB free on {label}",
                   "A rebuild needs room for the new generation before old ones can go, so updates will fail. "
                   "Removing old generations is the quickest way to free space.",
                   Repair("gc-generations", "Remove generations older than 14 days", ["anix", "gc", "old"]),
                   free_bytes=free)
            return
        if free < ROOT_WARN_BYTES:
            report("disk-space", "disk", "warn", f"{gb:.1f} GB free on {label}",
                   "That's tight for a major update. Old generations are usually what's using the space.",
                   Repair("gc-generations", "Remove generations older than 14 days", ["anix", "gc", "old"]),
                   free_bytes=free)
            return
        if path == "/nix":
            break  # /nix is on / for nearly every install; one line is enough
    report("disk-space", "disk", "ok", "Enough free disk space")


def check_services() -> None:
    if not shutil.which("systemctl"):
        report("services", "services", "skip", "systemd isn't available here")
        return
    listed = run(["systemctl", "--failed", "--plain", "--no-legend", "--no-pager"], timeout=10)
    if listed is None or listed.returncode != 0:
        report("services", "services", "skip", "Couldn't ask systemd about failed services")
        return
    failed = [line.split()[0] for line in listed.stdout.splitlines() if line.split()]
    if not failed:
        report("services", "services", "ok", "No failed system services")
        return
    abora = [unit for unit in failed if unit.startswith(("abora", "anix", "flatpak", "nix-"))]
    report("services", "services", "fail" if abora else "warn",
           f"{len(failed)} failed service(s): {', '.join(failed[:5])}{' …' if len(failed) > 5 else ''}",
           "A failed unit also makes the next `nixos-rebuild switch` report an error, even when the new "
           f"system is fine. See why with: journalctl -b -u {failed[0]}",
           Repair("reset-failed", "Clear the failed state so the next rebuild starts clean", ["systemctl", "reset-failed"], root=True),
           units=failed)


def check_flatpak() -> None:
    if not shutil.which("flatpak"):
        report("flatpak", "apps", "warn", "Flatpak isn't installed",
               "`anix apps` installs desktop apps from Flathub through Flatpak. Turn it on with "
               "`anix enable flatpak`, then `anix apply`.")
        return
    remotes = subprocess.run(["flatpak", "remotes", "--system"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True).stdout
    if "flathub" in (line.split()[0] for line in remotes.splitlines() if line.split()):
        report("flatpak", "apps", "ok", "Flathub is set up")
    else:
        report("flatpak", "apps", "warn", "Flathub isn't set up yet",
               "Abora adds Flathub in the background after the first boot with a network. Until then "
               "`anix apps` has nothing to install from.",
               Repair("flathub", "Add the Flathub remote", ["flatpak", "remote-add", "--if-not-exists", "--system", "flathub",
                                                             "https://dl.flathub.org/repo/flathub.flatpakrepo"], root=True))


ANSI = re.compile(r"\x1b\[[0-9;]*m")


def check_anix() -> None:
    """ANIX's own config checks (anix.nix, flake evaluation, Git snapshots), one finding per line."""
    if not shutil.which("anix"):
        report("anix", "anix", "warn", "The anix command isn't installed")
        return
    # Fixed, predictable /tmp path by design (so "see ..." below is
    # actionable) -- a plain open() there is a classic symlink race, so remove
    # the name (never follows a symlink), then create it exclusively: a
    # symlink racing back into place makes the open fail closed.
    try:
        os.unlink(anix_log)
    except OSError:
        pass
    try:
        log = os.fdopen(os.open(anix_log, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o666), "w")
    except OSError:
        report("anix", "anix", "warn", f"Couldn't write the ANIX doctor log at {anix_log}")
        return
    with log:
        # ANIX_DOCTOR_LAYER_ONLY: `anix doctor` is this tool on Abora, so ask for ANIX's own checks
        # instead of coming back here. Older anix ignores the variable and runs those checks anyway.
        done = subprocess.run(["anix", "doctor"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                              env={**os.environ, "ANIX_DOCTOR_LAYER_ONLY": "1"})
        log.write(done.stdout)
    lines = [ANSI.sub("", line).strip() for line in done.stdout.splitlines()]
    marks = {"✓": "ok", "!": "warn", "✗": "fail"}
    parsed = 0
    for line in lines:
        if line[:1] in marks and "Doctor found" not in line:
            parsed += 1
            status, text = marks[line[0]], line[1:].strip()
            fix = None
            if status != "ok" and ("ANIX config" in text or "Git repo" in text or "config directory" in text):
                fix = Repair("anix-config", "Create the missing ANIX config and snapshot repo", ["anix", "doctor", "--fix"], root=False)
            report(f"anix-{parsed}", "anix", status, text,
                   "" if status == "ok" else f"From ANIX's config checks; the full output is in {anix_log}.", fix)
    if not parsed:
        if done.returncode == 0:
            report("anix", "anix", "ok", "ANIX doctor completed")
        else:
            report("anix", "anix", "warn", f"ANIX doctor reported issues; see {anix_log}")


CHECKS = (
    check_install_files, check_bootloader, check_nix, check_anix, check_channel, check_desktop,
    check_gpu, check_network, check_disk, check_services, check_flatpak,
)


def run_checks() -> None:
    findings.clear()
    for check in CHECKS:
        try:
            check()
        except Exception as exc:  # one broken check must not hide the others
            report(check.__name__.removeprefix("check_"), "doctor", "warn", f"This check crashed: {exc}")


# ── output ────────────────────────────────────────────────────────────────────

def repairs() -> list[Repair]:
    seen, out = set(), []
    for finding in findings:
        if finding.status in ("warn", "fail") and finding.repair and finding.repair.id not in seen:
            seen.add(finding.repair.id)
            out.append(finding.repair)
    return out


AREA_TITLES = {"abora": "Abora files", "nix": "Nix", "anix": "ANIX config", "gpu": "GPU", "apps": "Apps (Flatpak)"}


def print_human() -> int:
    banner("Abora Doctor", "Checking installed-system health.")
    area = None
    for finding in findings:
        if finding.area != area:
            area = finding.area
            print(f"\n  {WHITE}{AREA_TITLES.get(area, area.capitalize())}{NC}")
        if finding.status == "ok":
            success(finding.summary)
        elif finding.status == "skip":
            dim_line(f"–  {finding.summary}")
        elif finding.status == "warn":
            warning(finding.summary)
        else:
            # On stdout, unlike abora_core's error(), so a failure stays next to its explanation when piped.
            print(f"  {RED}✗{NC}  {RED}{finding.summary}{NC}")
        if finding.status in ("warn", "fail"):
            if finding.explanation:
                for line in wrap(finding.explanation):
                    dim_line(f"   {line}")
            if finding.repair:
                dim_line(f"   Fix: anix doctor repair {finding.repair.id}")
    failures, warnings = Tally.count("fail"), Tally.count("warn")
    print()
    if failures:
        print(f"  {RED}✗{NC}  {RED}Abora doctor found {failures} problem(s) and {warnings} warning(s).{NC}")
    elif warnings:
        warning(f"Abora doctor found {warnings} warning(s).")
    else:
        success("Abora doctor found no problems.")
    if repairs():
        dim_line("See every suggested fix: anix doctor repair")
    print()
    return 1 if failures else 0


def wrap(text: str, width: int = 74) -> list[str]:
    lines, current = [], ""
    for word in text.split():
        if current and len(current) + 1 + len(word) > width:
            lines.append(current)
            current = word
        else:
            current = f"{current} {word}".strip()
    return lines + ([current] if current else [])


def print_json() -> int:
    payload = {
        "tool": "abora-doctor",
        "schema": 1,
        "version": ui_version_safe(),
        "generated": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "summary": {status: Tally.count(status) for status in ("ok", "warn", "fail", "skip")},
        "findings": [asdict(finding) for finding in findings],
    }
    json.dump(payload, sys.stdout, indent=2)
    print()
    return 1 if Tally.count("fail") else 0


def ui_version_safe() -> str:
    try:
        return "".join((abora_dir / "VERSION").read_text(encoding="utf-8").split())
    except OSError:
        return os.environ.get("ABORA_VERSION", "")


def as_root(command: list[str]) -> list[str]:
    if os.geteuid() == 0 or command[0] == "anix":
        return command  # anix asks for sudo itself
    return ["sudo", *command] if shutil.which("sudo") else command


def do_repair(ids: list[str], assume_yes: bool) -> int:
    available = {repair.id: repair for repair in repairs()}
    if not ids:
        banner("Abora Doctor", "Repairs for what the check found.")
        if not available:
            success("Nothing to repair.")
            print()
            return 0
        for repair in available.values():
            print(f"  {repair.id:<26} {repair.description}")
            dim_line(f"  {'':<26} runs: {' '.join(as_root(repair.command) if repair.root else repair.command)}")
        print()
        dim_line("Run one: anix doctor repair <id>   (or several at once)")
        print()
        return 0
    unknown = [repair_id for repair_id in ids if repair_id not in available]
    if unknown:
        error(f"No such repair for this system right now: {', '.join(unknown)}")
        dim_line("List the ones that apply: anix doctor repair")
        return 2
    status = 0
    for repair_id in ids:
        repair = available[repair_id]
        command = as_root(repair.command) if repair.root else repair.command
        print(f"\n  {repair.description}\n  runs: {' '.join(command)}")
        if not assume_yes:
            if not sys.stdin.isatty():
                error("Not running without confirmation; add --yes.")
                return 1
            if input("  Run it? [y/N] ").strip().lower() not in ("y", "yes"):
                warning("Skipped.")
                continue
        result = subprocess.run(command)
        if result.returncode == 0:
            success(f"{repair_id}: done")
        else:
            error(f"{repair_id}: the command failed (exit {result.returncode})")
            status = 1
    print()
    return status


USAGE = """Usage:
  anix doctor                 check system health and explain any problems
  anix doctor --json          the same as JSON (attach it to a bug report)
  anix doctor repair          list the fixes for what the check found
  anix doctor repair <id>...  run those fixes (asks first; --yes to skip)
  anix doctor --fix           fix ANIX's own config basics (anix.nix, snapshot repo)
"""


def main(argv: list[str]) -> int:
    args = list(argv)
    as_json = "--json" in args
    assume_yes = "--yes" in args or "-y" in args
    args = [a for a in args if a not in ("--json", "--yes", "-y")]
    if args[:1] in (["-h"], ["--help"], ["help"]):
        print(USAGE)
        return 0
    if args[:1] in (["--fix"], ["--repair"]):
        return subprocess.run(["anix", "doctor", *args], env={**os.environ, "ANIX_DOCTOR_LAYER_ONLY": "1"}).returncode
    if args and args[0] != "repair":
        error(f"Unknown doctor option: {args[0]}")
        print(USAGE)
        return 2
    run_checks()
    if args[:1] == ["repair"]:
        return do_repair(args[1:], assume_yes)
    return print_json() if as_json else print_human()


if __name__ == "__main__":
    os.environ["PATH"] = SYSTEM_PATH + (":" + os.environ["PATH"] if os.environ.get("PATH") else "")
    ui_setup()
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
