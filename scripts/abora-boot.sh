#!/usr/bin/env bash
# Abora OS — live boot script
# Runs on tty1 via systemd.  Plymouth is quit by ExecStartPre before this runs.

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
export TERM="${TERM:-linux}"

# Env vars the installer looks for — set here so the child process inherits them
export ABORA_DESKTOP_PROFILES_LIB="${ABORA_DESKTOP_PROFILES_LIB:-/etc/abora/desktop-profiles.sh}"
export ABORA_APP_CATALOG_LIB="${ABORA_APP_CATALOG_LIB:-/etc/abora/app-catalog.sh}"
export ABORA_NIXPKGS_PATH="${ABORA_NIXPKGS_PATH:-/etc/abora/nixpkgs}"

force_installer=0
installer_args=()
for arg in "$@"; do
    case "$arg" in
        --force) force_installer=1 ;;
        *) installer_args+=("$arg") ;;
    esac
done

# ── Find bash binary ───────────────────────────────────────────────────────────
BASH_BIN="/run/current-system/sw/bin/bash"
for _b in "${BASH:-}" /run/current-system/sw/bin/bash /usr/bin/bash /bin/bash; do
    [ -n "$_b" ] && [ -x "$_b" ] && { BASH_BIN="$_b"; break; }
done

# ── Colors ─────────────────────────────────────────────────────────────────────
BL=$'\033[38;5;33m'    # Abora blue
WH=$'\033[1;97m'       # bright white
DM=$'\033[38;5;242m'   # dim
CY=$'\033[38;5;87m'    # cyan / accent
NC=$'\033[0m'          # reset

# ── Boot stage display ────────────────────────────────────────────────────────
# Box inner width: 54 chars.  No arithmetic that can return exit-code 1.

BAR_W=40

_boot_frame() {
    # args: spinner  message  percent(0-100)
    local spin="$1"
    local msg="$2"
    local pct="$3"

    local filled=$(( pct * BAR_W / 100 ))
    local empty=$(( BAR_W - filled ))
    local bar
    bar="$(printf '%*s' "$filled" '' | tr ' ' '█')$(printf '%*s' "$empty" '' | tr ' ' '░')"

    # Hard-reset the VT so nothing bleeds in from Plymouth
    printf '\033c'
    printf '\n'
    printf '  %b╔══════════════════════════════════════════════════════╗%b\n' "$BL" "$NC"
    printf '  %b║%b  %-54s%b║%b\n' "$BL" "$WH" "ABORA OS  —  DENALI  ·  Starting" "$BL" "$NC"
    printf '  %b╠══════════════════════════════════════════════════════╣%b\n' "$BL" "$NC"
    printf '  %b║%b  %-54s%b║%b\n' "$BL" "$DM" "$msg" "$BL" "$NC"
    printf '  %b║%b  [%s] %b%s%b  %b%3d%%%b\n' \
        "$BL" "$NC" \
        "$spin" \
        "$CY" "$bar" "$NC" \
        "$WH" "$pct" "$NC"
    printf '  %b╚══════════════════════════════════════════════════════╝%b\n' "$BL" "$NC"
    printf '\n'
}

show_loader() {
    local step pct i total
    local msgs=(
        "Checking live media"
        "Starting network services"
        "Loading installer files"
        "Preparing setup environment"
        "Launching installer"
    )
    total=${#msgs[@]}
    i=0

    for step in "${msgs[@]}"; do
        pct=$(( i * 100 / total ))
        _boot_frame '/' "$step" "$pct"; sleep 0.06
        _boot_frame '-' "$step" "$pct"; sleep 0.06
        _boot_frame '\' "$step" "$pct"; sleep 0.06
        _boot_frame '|' "$step" "$pct"; sleep 0.06
        i=$(( i + 1 ))
    done

    _boot_frame '✓' "Ready" 100
    sleep 0.4
}

installed_root_device() {
    if [[ -e /dev/disk/by-label/ABORA_ROOT ]]; then
        readlink -f /dev/disk/by-label/ABORA_ROOT 2>/dev/null || printf '%s\n' /dev/disk/by-label/ABORA_ROOT
        return 0
    fi
    command -v blkid >/dev/null 2>&1 || return 1
    blkid -L ABORA_ROOT 2>/dev/null
}

has_installed_system_markers() {
    local root="$1"
    local system_profile="${root}/nix/var/nix/profiles/system"
    local bootloader="${root}/boot/EFI/BOOT/BOOTX64.EFI"
    [[ -e "${root}/etc/NIXOS" ]] || return 1
    [[ -e "${root}/etc/nixos/configuration.nix" ]] || return 1
    [[ -e "$system_profile" || -L "$system_profile" ]] && return 0
    compgen -G "${root}/nix/var/nix/profiles/system-*-link" >/dev/null 2>&1 && return 0
    [[ -e "$bootloader" ]] && return 0
    [[ -e "${root}/etc/abora/INSTALLED" ]] && return 0
    return 1
}

installed_system_present() {
    local dev="" mounted_at="" probe_dir="" rc=1

    dev="$(installed_root_device)" || return 1
    [[ -n "$dev" ]] || return 1

    # If an ABORA_ROOT partition exists, never auto-launch the installer from
    # the ISO. A successful install, a partial install, and a user who forgot to
    # detach the ISO all need a guard menu instead of another automatic wipe
    # flow. Reinstall is still available through the explicit menu path or
    # `abora-install --force`.
    return 0

    if command -v findmnt >/dev/null 2>&1; then
        mounted_at="$(findmnt -rn -S "$dev" -o TARGET 2>/dev/null | head -n 1 || true)"
        if [[ -n "$mounted_at" ]] && has_installed_system_markers "$mounted_at"; then
            return 0
        fi
    fi

    command -v mount >/dev/null 2>&1 || return 1
    command -v mktemp >/dev/null 2>&1 || return 1
    probe_dir="$(mktemp -d /run/abora-root-check.XXXXXX 2>/dev/null || mktemp -d /tmp/abora-root-check.XXXXXX)" || return 1

    if mount -o ro "$dev" "$probe_dir" >/dev/null 2>&1; then
        has_installed_system_markers "$probe_dir" && rc=0
        umount "$probe_dir" >/dev/null 2>&1 || true
    fi
    rmdir "$probe_dir" >/dev/null 2>&1 || true
    return "$rc"
}

eject_live_media() {
    command -v eject >/dev/null 2>&1 || return 1
    local d real fstype type
    for d in /dev/sr[0-9]* /dev/cdrom /dev/dvd /dev/disk/by-label/NIXOS_ISO /dev/disk/by-label/ABORA_ISO /dev/disk/by-label/ABORA_OS; do
        [[ -e "$d" ]] || continue
        real="$(readlink -f "$d" 2>/dev/null || printf '%s\n' "$d")"
        type="$(lsblk -dnro TYPE "$real" 2>/dev/null | head -n 1 || true)"
        fstype="$(lsblk -dnro FSTYPE "$real" 2>/dev/null | head -n 1 || true)"
        [[ "$real" == /dev/sr* || "$type" == "rom" || "$fstype" == "iso9660" ]] || continue
        eject "$d" >/dev/null 2>&1 && return 0
    done
    return 0
}

installed_system_menu() {
    # Detect virtualisation once — used for targeted help text.
    local virt=""
    virt="$(systemd-detect-virt 2>/dev/null || true)"

    printf '\033c'
    printf '\n'
    printf '  %b╔══════════════════════════════════════════════════════╗%b\n' "$BL" "$NC"
    printf '  %b║%b  %-54s%b║%b\n' "$BL" "$WH" "ABORA OS  —  Installed System Detected" "$BL" "$NC"
    printf '  %b╠══════════════════════════════════════════════════════╣%b\n' "$BL" "$NC"
    printf '  %b║%b  %-54s%b║%b\n' "$BL" "$DM" "An ABORA_ROOT disk was found." "$BL" "$NC"
    printf '  %b║%b  %-54s%b║%b\n' "$BL" "$DM" "The ISO will not auto-start installer." "$BL" "$NC"

    if [[ "$virt" == "qemu" || "$virt" == "kvm" ]]; then
        printf '  %b║%b  %-54s%b║%b\n' "$BL" "$CY" "QEMU: close VM → run  make qemu-disk" "$BL" "$NC"
    fi
    printf '  %b╚══════════════════════════════════════════════════════╝%b\n' "$BL" "$NC"
    printf '\n'
    printf '  %b1%b  Power off  %b(then boot without the ISO)%b\n' "$CY" "$NC" "$DM" "$NC"
    printf '  %b2%b  Reinstall  %b(wipes the disk — use make qemu-fresh)%b\n' "$CY" "$NC" "$DM" "$NC"
    printf '  %b3%b  Live shell\n' "$CY" "$NC"
    printf '\n'

    if [[ "$virt" == "qemu" || "$virt" == "kvm" ]]; then
        printf '  %bQEMU instructions:%b\n' "$WH" "$NC"
        printf '  1. Press 1 (or Enter) to power off this VM.\n'
        printf '  2. On your host, run:  %bmake qemu-disk%b\n' "$WH" "$NC"
        printf '     (or:  ABORA_QEMU_BOOT=disk ./scripts/run-qemu.sh)\n'
        printf '  That launches QEMU without the ISO — Abora boots from\n'
        printf '  the installed disk. No ISO to fight with.\n'
    else
        printf '  Remove the installation USB/DVD, then reboot.\n'
    fi
    printf '\n'

    local choice
    while true; do
        printf '  %bSelect [1]:%b ' "$CY" "$NC"
        read -r choice </dev/tty || choice="1"
        [[ -z "$choice" ]] && choice="1"
        case "$choice" in
            1|"")
                eject_live_media 2>/dev/null || true
                sync || true
                systemctl poweroff 2>/dev/null || poweroff || {
                    printf '\n  %bPoweroff did not start. Dropping to shell.%b\n\n' "$WH" "$NC"
                    exec "$BASH_BIN" --login
                }
                ;;
            2) return 0 ;;
            3) return 1 ;;
            *) printf '  %bEnter 1, 2, or 3.%b\n' "$DM" "$NC" ;;
        esac
    done
}

# ── Entry ──────────────────────────────────────────────────────────────────────
# Plymouth was already quit by ExecStartPre= in the service unit.
# Do a hard VT reset so any framebuffer residue is cleared.
printf '\033c'

# Wait for udev to settle so /dev/disk/by-label/ symlinks are populated
# before we check for an existing installation.
udevadm settle --timeout=10 2>/dev/null || true

if (( ! force_installer )) && installed_system_present; then
    if ! installed_system_menu; then
        printf '\n'
        printf '  %bLive shell. Run %babora-install --force%b to reinstall.%b\n\n' "$WH" "$CY" "$WH" "$NC"
        exec "$BASH_BIN" --login
    fi
fi

show_loader

printf '\033c'

# Launch the installer.
# We never exit 0 here — if the user chose Reboot/Poweroff, the installer
# calls systemctl reboot/poweroff directly and we never reach this point.
# If the installer exits for any other reason (clean exit after "Stay in live
# shell", or a crash), drop to the live shell so the service keeps running and
# tty1 stays ours (prevents autovt@tty1 from taking over).
"$BASH_BIN" /etc/abora/installer.sh "${installer_args[@]}" || true

printf '\n'
printf '  %b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$DM" "$NC"
printf '  %bInstaller exited.  You are now in the live shell.%b\n'      "$WH" "$NC"
printf '  %bType %babora-install%b to restart the installer.%b\n'       "$DM" "$WH" "$DM" "$NC"
printf '  %b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$DM" "$NC"
printf '\n'
exec "$BASH_BIN" --login
