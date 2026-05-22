#!/usr/bin/env bash
# Abora OS — live boot script
# Runs on tty1 via systemd.  Plymouth is quit by ExecStartPre before this runs.

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
export TERM="${TERM:-linux}"

# Env vars the installer looks for — set here so the child process inherits them
export ABORA_DESKTOP_PROFILES_LIB="${ABORA_DESKTOP_PROFILES_LIB:-/etc/abora/desktop-profiles.sh}"
export ABORA_APP_CATALOG_LIB="${ABORA_APP_CATALOG_LIB:-/etc/abora/app-catalog.sh}"
export ABORA_NIXPKGS_PATH="${ABORA_NIXPKGS_PATH:-/etc/abora/nixpkgs}"

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

# ── Entry ──────────────────────────────────────────────────────────────────────
# Plymouth was already quit by ExecStartPre= in the service unit.
# Do a hard VT reset so any framebuffer residue is cleared.
printf '\033c'

show_loader

printf '\033c'

# Launch the installer.
# We never exit 0 here — if the user chose Reboot/Poweroff, the installer
# calls systemctl reboot/poweroff directly and we never reach this point.
# If the installer exits for any other reason (clean exit after "Stay in live
# shell", or a crash), drop to the live shell so the service keeps running and
# tty1 stays ours (prevents autovt@tty1 from taking over).
"$BASH_BIN" /etc/abora/installer.sh "$@" || true

printf '\n'
printf '  %b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$DM" "$NC"
printf '  %bInstaller exited.  You are now in the live shell.%b\n'      "$WH" "$NC"
printf '  %bType %babora-install%b to restart the installer.%b\n'       "$DM" "$WH" "$DM" "$NC"
printf '  %b━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%b\n' "$DM" "$NC"
printf '\n'
exec "$BASH_BIN" --login
