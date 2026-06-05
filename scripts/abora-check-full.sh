#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

out_dir="${ABORA_CHECK_FULL_DIR:-${HOME:-/tmp}/abora-check-full}"
stamp="$(date +%Y%m%d-%H%M%S)"
report="${out_dir}/abora-full-check-${stamp}.log"

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

    "$@" >>"$report" 2>&1 || {
        printf '\n[exit %s]\n' "$?" >>"$report"
        return 0
    }
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
run_section "TinyPM system" tinypm system
run_section "TinyPM sources" tinypm sources
run_section "TinyPM doctor" tinypm doctor
run_section "Abora desktop" abora desktop list
run_section "Display services" sh -lc 'systemctl --no-pager --failed; systemctl --no-pager status display-manager 2>/dev/null || true'
run_section "Network and Bluetooth" sh -lc 'systemctl --no-pager status NetworkManager bluetooth 2>/dev/null || true; nmcli device 2>/dev/null || true; rfkill list 2>/dev/null || true'
run_section "Audio" sh -lc 'systemctl --user --no-pager status pipewire wireplumber pulseaudio 2>/dev/null || true; pactl info 2>/dev/null || true'
run_section "Graphics" sh -lc 'lspci -nnk 2>/dev/null | sed -n "/VGA\\|3D\\|Display/,+4p"; glxinfo -B 2>/dev/null || true'
run_section "Nix flake check" sh -lc 'cd /etc/nixos && nix --extra-experimental-features "nix-command flakes" flake show --no-write-lock-file 2>&1'
run_section "Nix dry build" sh -lc 'cd /etc/nixos && nixos-rebuild dry-build --flake .#abora 2>&1'

append_file "ANIX config" /etc/nixos/anix.nix
append_file "Abora local config" /etc/nixos/abora-local.nix
append_file "NixOS config" /etc/nixos/configuration.nix

if [[ -d /etc/abora/docs/wiki ]]; then
    run_section "Abora docs present" sh -lc 'find /etc/abora/docs/wiki -maxdepth 1 -type f -printf "%f\n" | sort'
fi

printf '\nFull check log: %s\n' "$report"
printf 'Send this file when asking for help.\n'
