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

# The key list has to cover networking.wireless.networks.*.psk: NixOS stores
# the plaintext Wi-Fi passphrase there, and configuration.nix is copied into
# these reports verbatim. The '' alternative catches Nix indented strings
# (psk = ''secret''): without it the ordinary single-quote branch matches the
# leading '' as an empty value and leaves the passphrase in the report. It
# redacts to end of line so an unterminated indented string still fails
# closed. The authorization rule is separate because a header puts the
# credential after a scheme word ("Bearer <token>"), which the key=value rule
# cannot reach -- dmesg and journalctl carry those routinely. It also runs to
# end of line, because a Digest header keeps credentials in later parameters
# (realm=, response=) well past the first space.
redact_stream() {
    # sed is line-based, so a Nix indented string spanning several lines --
    #   psk = ''
    #     passphrase
    #   '';
    # -- had its opening line rewritten to "[redacted]" while the passphrase
    # sat untouched on the next line, which reads as sanitised and is not.
    # Collapse credential blocks first, then apply the single-line rules.
    # A block opens only on a credential key, so an ordinary indented string
    # such as extraConfig = '' ... '' passes through intact.
    awk '
        function countq(s,   n, p) {
            n = 0
            p = index(s, q)
            while (p > 0) { n++; s = substr(s, p + 2); p = index(s, q) }
            return n
        }
        BEGIN {
            q = sprintf("%c%c", 39, 39)
            credopen = "(hashedpassword|password|passwd|psk|pskraw|presharedkey|secret|token|api[_-]?key)[ \t]*[:=][ \t]*" q
        }
        {
            if (inblock) { if (countq($0) > 0) inblock = 0; next }
            if (tolower($0) ~ credopen && countq($0) == 1 && $0 ~ (q "[ \t]*$")) { inblock = 1; print; next }
            print
        }
    ' | sed -E \
        -e 's@(^|[^[:alnum:]_])(hashedPassword|password|passwd|psk|pskRaw|preSharedKey|secret|token|api[_-]?key)([[:space:]]*[:=][[:space:]]*)("[^"]*"|'\'''\''.*|'\''[^'\'']*'\''|[^[:space:];]+)@\1\2\3"[redacted]"@Ig' \
        -e 's@((proxy-)?authorization[[:space:]]*:[[:space:]]*)((bearer|basic|token|digest)[[:space:]]+)?.*@\1\3[redacted]@Ig' \
        -e 's@(github\.com/[^[:space:]]+://)?([^[:space:]@/]+):([^[:space:]@]+)\@@\[redacted-user\]:[redacted]\@@g'
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
