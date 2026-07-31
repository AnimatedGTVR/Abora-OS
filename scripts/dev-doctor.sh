#!/usr/bin/env bash
set -euo pipefail

# A friendly pre-flight check for anyone about to work on Abora OS itself —
# first-time contributors most of all. abora-doctor.sh diagnoses an
# *installed Abora system*; this diagnoses *your dev machine*, before
# you've built anything, so a missing tool or disabled Nix feature shows up
# as one clear, actionable line instead of a cryptic failure five minutes
# into `make iso`.

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"

# shellcheck source=/dev/null
if [[ -f "$ui_lib" ]]; then
    source "$ui_lib"
else
    # Standalone fallback so this still runs from a bare checkout before
    # abora-ui.sh has ever been sourced anywhere (mirrors the pattern
    # check-scripts.sh uses to test the same fallback in isolation).
    abora_info()    { printf '  %s\n' "$1"; }
    abora_success() { printf '  [ok]   %s\n' "$1"; }
    abora_warn()    { printf '  [warn] %s\n' "$1"; }
    abora_error()   { printf '  [fail] %s\n' "$1"; }
fi

warnings=0
failures=0

ok()   { abora_success "$1"; }
warn() { warnings=$((warnings + 1)); abora_warn "$1"; }
fail() { failures=$((failures + 1)); abora_error "$1"; }

repo_root="$(CDPATH= cd -- "$script_dir/.." && pwd)"

printf '\n'
printf 'Abora OS dev environment check\n'
printf 'This looks at YOUR machine, not the repo — run it before your first build.\n\n'

# ── Required tools ──────────────────────────────────────────────────────────
if command -v git >/dev/null 2>&1; then
    ok "git found ($(git --version | head -1))"
else
    fail "git not found — install it with your distro's package manager (e.g. 'sudo apt install git', 'sudo pacman -S git')"
fi

if command -v nix >/dev/null 2>&1; then
    ok "nix found ($(nix --version 2>/dev/null | head -1))"

    # Flakes + nix-command are opt-in experimental features on most Nix
    # installs; this repo needs both for every `make iso`/`make qemu`
    # target, and the error you get without them ("experimental Nix
    # feature ... is disabled") doesn't say what to do about it.
    nix_conf_has_flakes=0
    for conf in /etc/nix/nix.conf "$HOME/.config/nix/nix.conf"; do
        if [[ -f "$conf" ]] && grep -Eq 'experimental-features.*(flakes|nix-command)' "$conf" 2>/dev/null; then
            nix_conf_has_flakes=1
        fi
    done
    if [[ "$nix_conf_has_flakes" -eq 1 ]]; then
        ok "flakes + nix-command look enabled in your nix.conf"
    else
        warn "flakes/nix-command not found in nix.conf — add this line to /etc/nix/nix.conf (or ~/.config/nix/nix.conf):"
        abora_info "    experimental-features = nix-command flakes"
        abora_info "  or pass --extra-experimental-features 'nix-command flakes' to every nix/make command"
    fi

    if nix --extra-experimental-features "nix-command flakes" store info >/dev/null 2>&1; then
        ok "nix daemon is reachable"
    else
        fail "nix daemon is not reachable — 'make iso'/'make qemu' will not work until it is."
        abora_info "  On NixOS: check 'systemctl status nix-daemon'."
        abora_info "  On other distros: (re)run the official installer — https://nixos.org/download"
        abora_info "  In a container/sandbox without a daemon, single-user Nix (nix-user-chroot or"
        abora_info "  a VM with real Nix) is the usual fix — a daemon-less Nix cannot build flakes."
    fi
else
    fail "nix not found — install it from https://nixos.org/download (Determinate Nix or the official installer both work)"
fi

if command -v qemu-system-x86_64 >/dev/null 2>&1 && command -v qemu-img >/dev/null 2>&1; then
    ok "qemu found ($(qemu-system-x86_64 --version | head -1))"
else
    warn "qemu-system-x86_64/qemu-img not found — you can still 'make iso', but 'make qemu' (boot-testing) needs them."
    abora_info "  Debian/Ubuntu: sudo apt install qemu-system-x86 qemu-utils"
    abora_info "  Fedora:        sudo dnf install qemu-kvm qemu-img"
    abora_info "  Arch:          sudo pacman -S qemu-full"
    abora_info "  NixOS:         nix profile install nixpkgs#qemu"
fi

# ── Disk space ───────────────────────────────────────────────────────────────
# nixpkgs plus a handful of edition ISOs adds up fast; a build failing two
# hours in because the disk filled up is a much worse first impression than
# a warning up front.
if command -v df >/dev/null 2>&1; then
    free_kb=$(df -Pk "$repo_root" 2>/dev/null | awk 'NR==2 {print $4}')
    if [[ -n "${free_kb:-}" ]]; then
        free_gb=$((free_kb / 1024 / 1024))
        if [[ "$free_gb" -lt 20 ]]; then
            warn "only ~${free_gb} GiB free at $repo_root — a full ISO build (with the Nix store) wants 20+ GiB free"
        else
            ok "~${free_gb} GiB free at $repo_root"
        fi
    fi
fi

# ── System ───────────────────────────────────────────────────────────────────
# The flake only ever targets x86_64-linux (see flake.nix's `system =`); on
# anything else, being told that clearly beats a confusing eval error.
kernel="$(uname -s 2>/dev/null || echo unknown)"
arch="$(uname -m 2>/dev/null || echo unknown)"
if [[ "$kernel" == "Linux" && "$arch" == "x86_64" ]]; then
    ok "running on Linux/x86_64 (matches the flake's target system)"
else
    warn "running on ${kernel}/${arch} — this flake only targets x86_64-linux; building elsewhere (incl. under emulation) is unsupported"
fi

printf '\n'
if [[ "$failures" -gt 0 ]]; then
    abora_error "$failures thing(s) need fixing before you can build Abora OS. See above."
    exit 1
elif [[ "$warnings" -gt 0 ]]; then
    abora_warn "$warnings thing(s) worth a look, but you can likely proceed. Try: make check"
    exit 0
else
    abora_success "You're set. Try: make check, then make iso"
    exit 0
fi
