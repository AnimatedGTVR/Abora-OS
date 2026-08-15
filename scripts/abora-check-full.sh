#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

out_dir="${ABORA_CHECK_FULL_DIR:-${HOME:-/tmp}/abora-check-full}"
stamp="$(date +%Y%m%d-%H%M%S)"
report="${out_dir}/abora-full-check-${stamp}.log"
section_timeout="${ABORA_CHECK_FULL_TIMEOUT:-90}"

mkdir -p "$out_dir"

run_section() {
    local title="$1"
    local tmp
    shift

    {
        printf '\n## %s\n' "$title"
        printf '$'
        printf ' %q' "$@"
        printf '\n\n'
    } >>"$report"

    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' RETURN
    timeout "$section_timeout" "$@" >"$tmp" 2>&1 || {
        printf '\n[exit %s]\n' "$?" >>"$tmp"
        redact_file "$tmp" >>"$report"
        rm -f "$tmp"
        trap - RETURN
        return 0
    }
    redact_file "$tmp" >>"$report"
    rm -f "$tmp"
    trap - RETURN
}

run_optional_command() {
    local title="$1"
    local command_name="$2"
    shift 2

    if command -v "$command_name" >/dev/null 2>&1; then
        run_section "$title" "$command_name" "$@"
    else
        {
            printf '\n## %s\n\n' "$title"
            printf '%s command not found\n' "$command_name"
        } >>"$report"
    fi
}

run_nix_dry_build() {
    if [[ ! -d /etc/nixos ]]; then
        printf 'missing /etc/nixos\n'
        return 0
    fi

    cd /etc/nixos
    if [[ "$(id -u)" -eq 0 ]]; then
        nixos-rebuild dry-build --flake .#abora
    # `sudo -n true` succeeds only if sudo can authenticate with zero
    # interaction (cached credential, NOPASSWD) -- this is a diagnostic tool
    # a user might run unattended, so it must never sit there prompting for
    # a password; skip the dry-build cleanly instead.
    elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
        sudo nixos-rebuild dry-build --flake .#abora
    else
        printf 'Skipped: dry-build needs root to write /etc/nixos/flake.lock.\n'
        printf 'Run manually when needed: sudo nixos-rebuild dry-build --flake /etc/nixos#abora\n'
    fi
}

append_file() {
    local title="$1"
    local file="$2"

    {
        printf '\n## %s\n' "$title"
        printf 'file: %s\n\n' "$file"
        if [[ -r "$file" ]]; then
            redact_file "$file" | sed -n '1,260p'
        else
            printf 'missing or unreadable\n'
        fi
    } >>"$report"
}

redact_stream() {
    sed -E \
        -e 's@(^|[^[:alnum:]_])(hashedPassword|password|passwd|secret|token|api[_-]?key)([[:space:]]*[:=][[:space:]]*)("[^"]*"|'\''[^'\'']*'\''|[^[:space:];]+)@\1\2\3"[redacted]"@Ig' \
        -e 's@(github\.com/[^[:space:]]+://)?([^[:space:]@/]+):([^[:space:]@]+)@\[redacted-user\]:[redacted]@g'
}

redact_file() {
    local file="$1"
    redact_stream < "$file"
}

{
    printf 'Abora full check\n'
    printf 'Generated: %s\n' "$(date -Is)"
    printf 'Host: %s\n' "$(hostname 2>/dev/null || printf unknown)"
    printf 'User: %s\n' "$(id -un 2>/dev/null || printf unknown)"
    printf 'Kernel: %s\n' "$(uname -a)"
} | redact_stream >"$report"

run_section "OS release" sh -lc 'cat /etc/os-release 2>/dev/null || true'
run_section "Current system" sh -lc 'readlink /run/current-system 2>/dev/null || true; nixos-version 2>/dev/null || true'
run_section "Abora doctor" abora doctor
run_section "ANIX status" anix status
run_section "ANIX doctor" anix doctor
run_section "ANIX profiles" anix profiles
run_section "ANIX generations" anix generations
run_optional_command "TinyPM version" tinypm --version
run_optional_command "TinyPM package check" tinypm check firefox
run_optional_command "TinyPM doctor" tinypm doctor
run_section "Abora desktop" abora desktop list
run_section "Display services" sh -lc 'systemctl --no-pager --failed; systemctl --no-pager status display-manager 2>/dev/null || true'
run_section "Network and Bluetooth" sh -lc 'systemctl --no-pager status NetworkManager bluetooth 2>/dev/null || true; nmcli networking connectivity check 2>/dev/null || true; nmcli device status 2>/dev/null || true; nmcli radio 2>/dev/null || true; nmcli -f SSID,SIGNAL,SECURITY device wifi list 2>/dev/null || true; resolvectl status 2>/dev/null || true; curl -fsI --connect-timeout 5 --max-time 8 https://cache.nixos.org 2>/dev/null || true; rfkill list 2>/dev/null || true'
run_section "Audio" sh -lc 'systemctl --user --no-pager status pipewire wireplumber pulseaudio 2>/dev/null || true; pactl info 2>/dev/null || true'
run_section "Graphics" sh -lc 'lspci -nnk 2>/dev/null | sed -n "/VGA\\|3D\\|Display/,+4p"; glxinfo -B 2>/dev/null || true'
run_section "Nix flake check" sh -lc 'cd /etc/nixos && nix --extra-experimental-features "nix-command flakes" flake show --no-write-lock-file 2>&1'
run_section "Nix dry build" bash -c "$(declare -f run_nix_dry_build); run_nix_dry_build"

append_file "ANIX config" /etc/nixos/anix.nix
append_file "Abora local config" /etc/nixos/abora-local.nix
append_file "NixOS config" /etc/nixos/configuration.nix
append_file "Dotfiles import log" "${XDG_STATE_HOME:-${HOME:-/tmp}/.local/state}/abora/dotfiles-import.log"

if [[ -d /etc/abora/docs/wiki ]]; then
    run_section "Abora docs present" sh -lc 'find /etc/abora/docs/wiki -maxdepth 1 -type f -printf "%f\n" | sort'
fi

printf '\nFull check log: %s\n' "$report"
printf 'Send this file when asking for help.\n'
