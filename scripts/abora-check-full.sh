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
    shift

    {
        printf '\n## %s\n' "$title"
        printf '$'
        printf ' %q' "$@"
        printf '\n\n'
    } >>"$report"

    timeout "$section_timeout" "$@" >>"$report" 2>&1 || {
        printf '\n[exit %s]\n' "$?" >>"$report"
        return 0
    }
}

run_optional_command() {
    local title="$1"
    local command_name="$2"
    shift 2

    if command -v "$command_name" >/dev/null 2>&1; then
        run_section "$title" "$command_name" "$@"
    elif [[ "$command_name" == "tinypm" && -x /etc/abora/tinypm/tinypm ]]; then
        run_section "$title" env TINYPM_FLAVOR=abora /etc/abora/tinypm/tinypm "$@"
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
            sed -n '1,260p' "$file"
        else
            printf 'missing or unreadable\n'
        fi
    } >>"$report"
}

{
    printf 'Abora full check\n'
    printf 'Generated: %s\n' "$(date -Is)"
    printf 'Host: %s\n' "$(hostname 2>/dev/null || printf unknown)"
    printf 'User: %s\n' "$(id -un 2>/dev/null || printf unknown)"
    printf 'Kernel: %s\n' "$(uname -a)"
} >"$report"

run_section "OS release" sh -lc 'cat /etc/os-release 2>/dev/null || true'
run_section "Current system" sh -lc 'readlink /run/current-system 2>/dev/null || true; nixos-version 2>/dev/null || true'
run_section "Abora doctor" abora doctor
run_section "ANIX status" anix status
run_section "ANIX doctor" anix doctor
run_section "ANIX profiles" anix profiles
run_section "ANIX generations" anix generations
run_optional_command "TinyPM system" tinypm system
run_optional_command "TinyPM sources" tinypm sources
run_optional_command "TinyPM doctor" tinypm doctor
run_section "Abora desktop" abora desktop list
run_section "Display services" sh -lc 'systemctl --no-pager --failed; systemctl --no-pager status display-manager 2>/dev/null || true'
run_section "Network and Bluetooth" sh -lc 'systemctl --no-pager status NetworkManager bluetooth 2>/dev/null || true; nmcli device 2>/dev/null || true; rfkill list 2>/dev/null || true'
run_section "Audio" sh -lc 'systemctl --user --no-pager status pipewire wireplumber pulseaudio 2>/dev/null || true; pactl info 2>/dev/null || true'
run_section "Graphics" sh -lc 'lspci -nnk 2>/dev/null | sed -n "/VGA\\|3D\\|Display/,+4p"; glxinfo -B 2>/dev/null || true'
run_section "Nix flake check" sh -lc 'cd /etc/nixos && nix --extra-experimental-features "nix-command flakes" flake show --no-write-lock-file 2>&1'
run_section "Nix dry build" bash -c "$(declare -f run_nix_dry_build); run_nix_dry_build"

append_file "ANIX config" /etc/nixos/anix.nix
append_file "Abora local config" /etc/nixos/abora-local.nix
append_file "NixOS config" /etc/nixos/configuration.nix

if [[ -d /etc/abora/docs/wiki ]]; then
    run_section "Abora docs present" sh -lc 'find /etc/abora/docs/wiki -maxdepth 1 -type f -printf "%f\n" | sort'
fi

printf '\nFull check log: %s\n' "$report"
printf 'Send this file when asking for help.\n'
