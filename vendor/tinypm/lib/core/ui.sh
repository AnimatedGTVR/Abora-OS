#!/usr/bin/env bash
# shellcheck disable=SC2154

usage() {
    printf '%s\n' "$tinypm_system_name"
    printf 'Core engine: %s\n' "$tinypm_engine_name"
    [[ -n "$tinypm_tagline" ]] && printf '%s\n' "$tinypm_tagline"
    cat <<EOF2

Usage:
  $tinypm_engine_name --version
  grab <package>
  grab [-f|-flat|-flatpak|-s|-n] <package>
  tinypm install [-f|-flat|-flatpak|-s|-n|--brew|--nix] <package>
  tinypm search [-f|-flat|-flatpak|-s|-n|--brew|--nix] <query>
  tinypm remove [-f|-flat|-flatpak|-s|-n|--brew|--nix] <package>
  tinypm list [-f|-flat|-flatpak|-s|-n|--brew|--nix]
  tinypm run [-f|-flat|-flatpak|-s] <app>
  tinypm start [-f|-flat|-flatpak|-s] <app>
  tinypm update [-f|-flat|-flatpak|-s|-n|--brew|--nix]
  tinypm info <package>
  tinypm managed
  tinypm export-state [file]
  tinypm import-state <file>
  tinypm selftest
  tinypm apps
  tinypm discover [query]
  tinypm doctor [--fix]
  tinypm version
  tiny --version
  $tinypm_engine_name --version
  grab firefox
  syspm update

Quick aliases:
  tinypm i <pkg>         # install
  tinypm s <query>       # search
  tinypm r <pkg>         # remove
  tinypm u               # update
  tinypm ls              # list
  tinypm v               # version

Primary command:
  grab [-f|-flat|-flatpak|-s|-n] <package>

Flags:
  -f, -flat, -flatpak    use Flatpak
  -s, --snp, --snap      use Snap
  -n, --nat, --native    use detected native manager
  --brew                 force Homebrew backend
  --nix                  force Nix backend

Native PM detection supports:
  apt, dnf, pacman, xbps, zypper, apk, emerge, brew, nix

Notes:
  If multiple backends are installed, grab asks which source to use.
  discover is a curated catalog, not every package everywhere.
  syspm routes TinyPM through the native system package manager only.
EOF2
}

run_with_spinner() {
    local message="$1"
    shift

    if [[ $# -gt 0 ]] && declare -F "$1" >/dev/null 2>&1; then
        local func_name="$1"
        shift

        export use_host_backend
        while read -r _ _ exported_func; do
            # shellcheck disable=SC2163
            export -f "$exported_func"
        done < <(declare -F)

        # shellcheck disable=SC2016
        "$spinner" "$message" -- bash -lc 'func_name="$1"; shift; "$func_name" "$@"' bash "$func_name" "$@"
        return
    fi

    "$spinner" "$message" -- "$@"
}
