#!/usr/bin/env python3
"""Boot the newest Abora ISO, or the installed test disk, in QEMU.

Environment overrides (empty counts as unset):
  ABORA_QEMU_BOOT          iso (default; also live/install) or disk (also installed/hard-drive/harddrive)
  ABORA_QEMU_FRESH=1       delete the test disk first, for a clean install
  ABORA_QEMU_NOGRAPHIC=1   headless: serial console and QEMU monitor in this terminal
  ABORA_QEMU_SERIAL_STDIO=1  keep the window, mirror guest serial output here
  ABORA_ISO_PATH           ISO to boot (default: newest *.iso in out/iso or out/)
  ABORA_QEMU_DISK          qcow2 test disk (default out/qemu/abora-qemu.qcow2)
  ABORA_QEMU_DISK_SIZE     size when creating the disk (default 32G)
  ABORA_QEMU_MEMORY_MB     default 4096
  ABORA_QEMU_CPUS          default 4
  ABORA_OUT_DIR, ABORA_ISO_DIR, ABORA_QEMU_DIR, ABORA_LOG_DIR
"""

from __future__ import annotations

import os
import shutil
import signal
import subprocess
import sys
from pathlib import Path

from abora_release import env, repo_root

INSTALLED_DISK_BYTES = 200 * 1024 * 1024  # an empty qcow2 is ~200 KiB; a real install is far larger
FIRMWARE_DIRS = (
    "/usr/share/OVMF",
    "/usr/share/edk2/x64",
    "/run/current-system/sw/share/OVMF",
    "/nix/var/nix/profiles/system/sw/share/OVMF",
)
BOOT_MODES = {
    **dict.fromkeys(("iso", "live", "install"), "iso"),
    **dict.fromkeys(("disk", "installed", "hard-drive", "harddrive"), "disk"),
}


def note(*lines: str) -> None:
    for line in lines:
        print(line, file=sys.stderr, flush=True)


def newest_iso(*directories: Path) -> Path | None:
    candidates = []
    for directory in directories:
        try:
            entries = list(directory.iterdir())
        except OSError:
            continue
        for path in entries:
            if path.name.endswith(".iso") and path.is_file() and not path.is_symlink():
                candidates.append((path.stat().st_mtime_ns, str(path)))
    return Path(max(candidates)[1]) if candidates else None


def xorriso_extract(iso: Path, inner: str, target: Path) -> None:
    subprocess.run(
        ["xorriso", "-indev", str(iso), "-osirrox", "on", "-extract", inner, str(target)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def serial_boot_entry(cfg: Path) -> tuple[str, str, str]:
    """LINUX/INITRD/APPEND of the `LABEL boot-serial` block in isolinux.cfg."""
    kernel = initrd = append = ""
    if not cfg.is_file():
        return kernel, initrd, append
    in_block = False
    for line in cfg.read_text(encoding="utf-8", errors="replace").splitlines():
        if line == "LABEL boot-serial":
            in_block = True
            continue
        if in_block:
            if line.startswith("LABEL "):
                break
            if line.startswith("LINUX "):
                kernel = line[len("LINUX "):]
            elif line.startswith("INITRD "):
                initrd = line[len("INITRD "):]
            elif line.startswith("APPEND "):
                append = line[len("APPEND "):]
    return kernel, initrd, append


def has_gtk_display() -> bool:
    probe = subprocess.run(["qemu-system-x86_64", "-display", "gtk,help"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if probe.returncode == 0:
        return True
    listing = subprocess.run(["qemu-system-x86_64", "-display", "help"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return any(line.startswith("gtk") for line in listing.stdout.splitlines())


def main() -> int:
    repo = repo_root(__file__)
    out_dir = Path(env("ABORA_OUT_DIR") or repo / "out")
    iso_dir = Path(env("ABORA_ISO_DIR") or out_dir / "iso")
    qemu_dir = Path(env("ABORA_QEMU_DIR") or out_dir / "qemu")
    log_dir = Path(env("ABORA_LOG_DIR") or out_dir / "logs")
    iso_path = env("ABORA_ISO_PATH")
    disk_path = Path(env("ABORA_QEMU_DISK") or qemu_dir / "abora-qemu.qcow2")
    memory_mb = env("ABORA_QEMU_MEMORY_MB") or "4096"
    cpu_count = env("ABORA_QEMU_CPUS") or "4"
    disk_size = env("ABORA_QEMU_DISK_SIZE") or "32G"
    requested_boot = env("ABORA_QEMU_BOOT") or "iso"
    nographic = env("ABORA_QEMU_NOGRAPHIC") == "1"
    fresh = env("ABORA_QEMU_FRESH") == "1"
    serial_stdio = env("ABORA_QEMU_SERIAL_STDIO") == "1"

    for tool in ("qemu-system-x86_64", "qemu-img"):
        if not shutil.which(tool):
            note(f"{tool} is required. Install qemu on your host.")
            return 1

    boot_mode = BOOT_MODES.get(requested_boot)
    if boot_mode is None:
        note(f"Invalid ABORA_QEMU_BOOT: {requested_boot} (use iso or disk).")
        return 1

    if boot_mode == "iso" and not iso_path:
        latest = newest_iso(iso_dir, out_dir)
        if latest is None:
            note(f"No ISO found in {out_dir}. Build one first with `make iso` or set ABORA_ISO_PATH.")
            return 1
        iso_path = str(latest)
    if boot_mode == "iso" and not Path(iso_path).is_file():
        note(f"ISO not found: {iso_path}")
        return 1

    for directory in (out_dir, iso_dir, qemu_dir, log_dir):
        directory.mkdir(parents=True, exist_ok=True)

    # Fresh disk: wipe the old image so installation starts clean.
    if fresh and disk_path.is_file():
        print("  Removing old disk image for fresh start…", flush=True)
        disk_path.unlink()
    if not disk_path.is_file():
        created = subprocess.run(["qemu-img", "create", "-f", "qcow2", str(disk_path), disk_size], stdout=subprocess.DEVNULL)
        if created.returncode != 0:
            return created.returncode

    # Auto-switch to disk boot when the qcow2 is large enough to hold a real
    # installation, so "make qemu" works after installing without having to
    # remember "make qemu-disk".
    if boot_mode == "iso" and disk_path.is_file():
        disk_bytes = disk_path.stat().st_size
        if disk_bytes > INSTALLED_DISK_BYTES:
            print(f"  Found existing installation on {disk_path} ({disk_bytes // 1073741824} GiB) — booting disk.")
            print("  Use 'make qemu-fresh' to wipe and reinstall from scratch.", flush=True)
            boot_mode = "disk"

    args = [
        "-m", memory_mb,
        "-smp", cpu_count,
        "-drive", f"file={disk_path},format=qcow2,if=virtio",
        "-netdev", "user,id=n1",
        "-device", "virtio-net-pci,netdev=n1",
    ]

    kvm = Path("/dev/kvm")
    if kvm.is_char_device() and os.access(kvm, os.R_OK | os.W_OK):
        args += ["-enable-kvm", "-cpu", "host"]
    else:
        note("  Note: /dev/kvm not available — running without hardware acceleration (slow).")
        args += ["-cpu", "qemu64"]

    # UEFI firmware (optional — mirrors real hardware better).
    firmware = next((Path(d) for d in FIRMWARE_DIRS if (Path(d) / "OVMF_CODE.fd").is_file()), None)
    if firmware is not None and (firmware / "OVMF_VARS.fd").is_file():
        vars_copy = qemu_dir / "OVMF_VARS.fd"
        if not vars_copy.is_file():
            shutil.copyfile(firmware / "OVMF_VARS.fd", vars_copy)
        args += [
            "-drive", f"if=pflash,format=raw,readonly=on,file={firmware / 'OVMF_CODE.fd'}",
            "-drive", f"if=pflash,format=raw,file={vars_copy}",
        ]

    # When serial output is requested, the ISO's default ISOLINUX label has no
    # console=ttyS0, and its "Serial console" entry can't be picked from the
    # QEMU command line: the guest boots but stays silent, which looks exactly
    # like a hang. Boot that entry's kernel/initrd/append directly instead;
    # root=fstab still resolves against the attached CD-ROM.
    want_serial = boot_mode == "iso" and (nographic or serial_stdio)
    if want_serial and not shutil.which("xorriso"):
        note(
            "  Note: xorriso not found; cannot extract the ISO's serial-console boot entry.",
            "  Falling back to the normal boot menu (guest serial output may be silent).",
        )
        want_serial = False

    if want_serial:
        serial_dir = qemu_dir / "serial-boot"
        serial_dir.mkdir(parents=True, exist_ok=True)
        cfg = serial_dir / "isolinux.cfg"
        cfg.unlink(missing_ok=True)
        xorriso_extract(Path(iso_path), "/isolinux/isolinux.cfg", cfg)
        kernel_rel, initrd_rel, append = serial_boot_entry(cfg)

        kernel, initrd = serial_dir / "vmlinuz", serial_dir / "initrd"
        if kernel_rel and initrd_rel and append:
            xorriso_extract(Path(iso_path), f"/{kernel_rel}", kernel)
            xorriso_extract(Path(iso_path), f"/{initrd_rel}", initrd)
        if kernel_rel and initrd_rel and append and kernel.is_file() and initrd.is_file():
            args += ["-kernel", str(kernel), "-initrd", str(initrd), "-append", append, "-cdrom", iso_path]
        else:
            note(
                "  Note: could not extract the ISO's serial-console boot entry;",
                "  falling back to the normal boot menu (guest serial output may be silent).",
            )
            want_serial = False

    if not want_serial:
        if boot_mode == "iso":
            # order=c: the disk stays the default for warm reboots; once=d: CD-ROM for this cold boot only.
            args += ["-boot", "order=c,once=d", "-cdrom", iso_path]
        else:
            args += ["-boot", "order=c"]

    serial_log = log_dir / "abora-serial.log"
    if nographic:
        args += ["-nographic", "-serial", "mon:stdio"]
    else:
        args += ["-display", "gtk,show-cursor=on,grab-on-hover=off" if has_gtk_display() else "sdl,grab-on-hover=off"]
        args += ["-vga", "virtio", "-usb", "-device", "usb-tablet"]
        args += ["-serial", "stdio" if serial_stdio else f"file:{serial_log}"]

    if boot_mode == "iso":
        print("Booting Abora installer ISO in QEMU:")
        print(f"  ISO:  {iso_path}")
    else:
        print("Booting installed Abora disk in QEMU:")
    print(f"  Disk: {disk_path}")
    if not nographic and not serial_stdio:
        print(f"  Serial log: {serial_log}")
    if serial_stdio and not nographic:
        print("  Serial: live output mirrored into this terminal")
    print("  Close the QEMU window or press Ctrl+C here to stop the VM.")
    print("", flush=True)

    process = subprocess.Popen(["qemu-system-x86_64", *args])
    try:
        status = process.wait()
    except KeyboardInterrupt:
        # QEMU gets the same Ctrl+C from the terminal; wait for it to exit.
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        process.wait()
        print()
        print("QEMU stopped.")
        return 0

    if status in (0, 130, -signal.SIGINT):
        print("QEMU stopped.")
        return 0
    code = status if status >= 0 else 128 - status
    note(f"QEMU exited with status {code}.")
    return code


if __name__ == "__main__":
    sys.exit(main())
