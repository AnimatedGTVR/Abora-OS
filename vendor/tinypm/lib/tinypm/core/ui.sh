#!/usr/bin/env bash
# shellcheck disable=SC2154

usage() {
    case "${prog_name:-tinypm}" in
        grab) grab_usage; return ;;
        grab-add-repo) repo_usage; return ;;
        grab-de) de_usage; return ;;
    esac

    ui_heading "$(tinypm_version_label)"
    [[ -n "$tinypm_tagline" ]] && printf '%s\n' "$tinypm_tagline"
    cat <<EOF2

Usage:
  grab [provider] <package...>
  grab <command> [arguments...]
  grab --dry-run [provider] <package...>
  grab-add-repo [provider] <repo> [name]
  grab-de <desktop>
  tinypm install [provider] <package...>
  tinypm remove  [provider] <package...>
  tinypm update | upgrade [provider]
  tinypm search  [provider] <query>
  tinypm info    <package>
  tinypm explain [provider] <package>
  tinypm check   <package>
  tinypm list    [provider]
  tinypm run | start [-f|-flat|-flatpak|-s] <app>
  tinypm add-repo <repo> [name]
  tinypm de <desktop>
  tinypm managed
  tinypm pin <package>
  tinypm unpin <package>
  tinypm pinned
  tinypm bundle list
  tinypm bundle <category> [-f|-s|-n]
  tinypm sync <manifest-file>
  tinypm sync --generate [output-file]
  tinypm history [N]
  tinypm undo [--yes]
  tinypm apps
  tinypm discover [query]
  tinypm export-state [file]
  tinypm import-state <file>
  tinypm check-update [--notify] [--quiet]
  tinypm self-update [--yes]
  tinypm selftest
  tinypm doctor [--fix]
  tinypm version
  tiny --version
  grab firefox vlc gimp
  grab update
  grab search firefox
  syspm update

Quick aliases:
  tinypm i <pkg...>      # install
  tinypm s <query>       # search
  tinypm r <pkg...>      # remove
  tinypm u               # update
  tinypm ls              # list
  tinypm v               # version
  tinypm h [N]           # history
  tinypm undo            # preview the last reversible transaction
  tinypm p <pkg>         # pin
  tinypm b <category>    # bundle
  tinypm c <pkg>         # check package status
  tinypm cu              # check for a TinyPM update
  tinypm su              # update TinyPM itself

Flags:
  -f, -flat, -flatpak    use Flatpak
  -s, --snp, --snap      use Snap
  -n, --nat, --native    use detected native manager
  --brew                 force Homebrew backend
  --nix                  force Nix backend
  --apk                   force Alpine APK backend
  --apt, --dnf, --pacman force that native backend
  -d, --dry-run          show plan without installing

Native PM detection supports:
  apt, dnf, pacman, xbps, zypper, apk, emerge, eopkg, swupd,
  slackpkg, opkg, urpmi, guix, brew, nix

Add a source (like add-apt-repository):
  grab-add-repo ppa:hepp3n/cosmic-epoch     # apt
  grab update
  grab cosmic-session
  grab-add-repo https://nixos.org/channels/nixos-unstable unstable   # Abora/Nix

Install a desktop environment:
  grab-de cosmic        # also: gnome, plasma, xfce
  grab-de gnome
  On Nix/Abora, grab-de prints the configuration.nix lines to add.

Notes:
  If multiple backends are installed, grab asks which source to use.
  add-repo routes to the native backend (PPA on apt, channel on Nix, tap on brew, ...).
  discover is a curated catalog, not every package everywhere.
  syspm routes TinyPM through the native system package manager only.
  grab firefox vlc gimp          # install multiple at once
  grab --dry-run firefox vlc     # preview without changing anything
  tinypm check firefox           # probe all backends + catalog
  tinypm upgrade                 # alias for update
  tinypm bundle Gaming           # install a whole category
  tinypm sync packages.txt       # install from manifest
  tinypm pin firefox             # skip during updates
  tinypm check-update --notify   # notify when TinyPM itself has an update
EOF2
}

grab_usage() {
    ui_heading "grab — install software without package-manager trivia"
    cat <<'EOF'

Usage:
  grab [options] <package...>
  grab <command> [arguments...]

Commands:
  install, get       install packages (the default)
  search             find packages
  remove             uninstall packages
  update             update installed software
  list               list installed software
  info, check        inspect package state
  explain            show name, provider, and command resolution
  repo               add a package repository
  de                 install a desktop environment
  doctor             diagnose TinyPM
  undo               preview or reverse the last install/removal

Options:
  --                 treat everything after it as package names
  -n, --native       native distro package manager
  -f, --flatpak      Flatpak
  -s, --snap         Snap
  -d, --dry-run      show the plan without changing anything
  --apk, --apt, --dnf, --pacman, ...  choose an exact native manager

Examples:
  grab firefox vlc
  grab --flatpak org.mozilla.firefox
  grab search neovim
  grab explain gcc++
  grab remove neovim
  grab update
  grab --dry-run curl git
  grab -- udpate     # install a literal package named "udpate"
EOF
}

repo_usage() {
    ui_heading "grab-add-repo — register a native package source"
    cat <<'EOF'

Usage:
  grab-add-repo [provider] <repository> [name]

Examples:
  grab-add-repo ppa:owner/project
  grab-add-repo --apk https://dl-cdn.alpinelinux.org/alpine/edge/community edge
  grab-add-repo --dnf copr:owner/project
  grab-add-repo --nix https://nixos.org/channels/nixos-unstable unstable
EOF
}

de_usage() {
    ui_heading "grab-de — install a desktop environment"
    cat <<'EOF'

Usage:
  grab-de [provider] <cosmic|gnome|plasma|xfce>

NixOS and Abora remain declarative; TinyPM prints or applies the required
configuration instead of creating a broken user-profile desktop.
EOF
}

transaction_summary() {
    local installed="$1" present="$2" duplicates="$3" failed="$4" elapsed="$5"
    local icon='✓' color="$c_green"
    local duplicate_suffix='s'
    if [[ "$failed" -gt 0 ]]; then
        icon='✗'
        color="$c_red"
    fi

    printf '\n%s%s%s %d installed' "$color$c_bold" "$icon" "$c_reset" "$installed"
    [[ "$present" -eq 0 ]] || printf ', %d already installed' "$present"
    [[ "$duplicates" -eq 1 ]] && duplicate_suffix=''
    [[ "$duplicates" -eq 0 ]] || printf ', %d duplicate%s' "$duplicates" "$duplicate_suffix"
    [[ "$failed" -eq 0 ]] || printf ', %d failed' "$failed"
    printf ' %s•%s %ss\n' "$c_dim" "$c_reset" "$elapsed"
}

removal_summary() {
    local removed="$1" skipped="$2" failed="$3" elapsed="$4"
    local icon='✓' color="$c_green"
    if [[ "$failed" -gt 0 ]]; then
        icon='✗'
        color="$c_red"
    fi

    printf '\n%s%s%s %d removed' "$color$c_bold" "$icon" "$c_reset" "$removed"
    [[ "$skipped" -eq 0 ]] || printf ', %d already covered' "$skipped"
    [[ "$failed" -eq 0 ]] || printf ', %d failed' "$failed"
    printf ' %s•%s %ss\n' "$c_dim" "$c_reset" "$elapsed"
}

run_with_spinner() {
    local message="$1"
    shift

    # CI, redirected output, and minimal terminals should run commands directly.
    # This is faster, preserves fake/test backends, and avoids unreadable CRs.
    if [[ "${TINYPM_NO_SPINNER:-0}" -eq 1 || ! -t 1 ]]; then
        ui_info "$message"
        "$@"
        return
    fi

    local stdout_file stderr_file pid status frame index=0
    local pacman_frames=(
        'ᗧ · · ·' '  ᗧ · ·' '·   ᗧ ·' '· ·   ᗧ'
        '· · · ᗣ' '· · ᗣ  ' '· ᗣ   ·' 'ᗣ   · ·'
    )

    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"
    "$@" >"$stdout_file" 2>"$stderr_file" &
    pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        frame="${pacman_frames[$index]}"
        printf '\r\033[2K%s[%s]%s %s' "$c_yellow" "$frame" "$c_reset" "$message"
        index=$(((index + 1) % ${#pacman_frames[@]}))
        sleep 0.1
    done

    if wait "$pid"; then
        status=0
        printf '\r\033[2K%s[  ✓  ]%s %s\n' "$c_green" "$c_reset" "$message"
    else
        status=$?
        printf '\r\033[2K%s[  ✗  ]%s %s\n' "$c_red" "$c_reset" "$message" >&2
    fi

    cat "$stdout_file"
    cat "$stderr_file" >&2
    rm -f "$stdout_file" "$stderr_file"
    return "$status"
}
