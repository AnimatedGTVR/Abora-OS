#!/usr/bin/env bash
set -euo pipefail

script_path="${BASH_SOURCE[0]}"
while [[ -L "$script_path" ]]; do
    script_parent="$(cd -P "$(dirname "$script_path")" && pwd)"
    script_target="$(readlink "$script_path")"
    [[ "$script_target" == /* ]] && script_path="$script_target" || script_path="$script_parent/$script_target"
done
package_root="$(cd "$(dirname "$script_path")/.." && pwd)"
if [[ -x "$package_root/src/bin/tinypm" ]]; then
    source_root="$package_root/src"
elif [[ -x "$package_root/bin/tinypm" ]]; then
    source_root="$package_root"
else
    printf 'TinyPM installer: runtime files were not found.\n' >&2
    exit 1
fi

prefix="${TINYPM_PREFIX:-$HOME/.tinypm}"
bin_dir="$prefix/bin"
lib_dir="$prefix/lib/tinypm"
share_dir="$prefix/share/tinypm"
local_bin="$HOME/.local/bin"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/tinypm"
config_file="$config_dir/config"
selected_flavor="${TINYPM_FLAVOR:-default}"
forced_native_pm=""
non_interactive=0

if [[ -z "${NO_COLOR:-}" ]] && { [[ -n "${FORCE_COLOR:-}" ]] || [[ -t 1 && "${TERM:-dumb}" != "dumb" ]]; }; then
    c_reset=$'\033[0m'; c_bold=$'\033[1m'; c_cyan=$'\033[1;36m'; c_green=$'\033[1;32m'
else
    c_reset=''; c_bold=''; c_cyan=''; c_green=''
fi

flavor_root() {
    printf '%s\n' "$source_root/share/tinypm/flavors/$selected_flavor"
}

flavor_file() {
    local candidate
    candidate="$(flavor_root)/$1"
    [[ -r "$candidate" ]] || return 1
    printf '%s\n' "$candidate"
}

load_flavor() {
    local file
    FLAVOR_NAME="TinyPM"
    FLAVOR_TAGLINE=""
    file="$(flavor_file flavor.conf 2>/dev/null || true)"
    # shellcheck disable=SC1090
    [[ -z "$file" ]] || . "$file"
}

detect_native_pm() {
    local item command
    for item in \
        apt:apt-get dnf:dnf pacman:pacman xbps:xbps-install zypper:zypper \
        apk:apk emerge:emerge eopkg:eopkg swupd:swupd slackpkg:slackpkg \
        opkg:opkg urpmi:urpmi guix:guix brew:brew nix:nix-env
    do
        command="${item#*:}"
        command -v "$command" >/dev/null 2>&1 && { printf '%s\n' "${item%%:*}"; return; }
    done
    return 1
}

valid_native_pm() {
    case "$1" in
        auto|apt|dnf|pacman|xbps|zypper|apk|emerge|eopkg|swupd|slackpkg|opkg|urpmi|guix|brew|nix) return 0 ;;
        *) return 1 ;;
    esac
}

usage() {
    cat <<'EOF'
TinyPM v0.8 installer

Usage:
  ./scripts/install.sh [--auto] [--native <manager>] [--flavor <name>] [-y]
EOF
}

parse_options() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --flavor=*) selected_flavor="${1#*=}"; shift ;;
            --flavor) shift; [[ $# -gt 0 ]] || { printf 'Missing flavor name.\n' >&2; exit 2; }; selected_flavor="$1"; shift ;;
            --native=*) forced_native_pm="${1#*=}"; shift ;;
            --native) shift; [[ $# -gt 0 ]] || { printf 'Missing native manager.\n' >&2; exit 2; }; forced_native_pm="$1"; shift ;;
            --auto) forced_native_pm="auto"; shift ;;
            -y|--yes|--non-interactive) non_interactive=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) printf 'Unknown installer option: %s\n' "$1" >&2; exit 2 ;;
        esac
    done

    [[ -z "$forced_native_pm" ]] || valid_native_pm "$forced_native_pm" || {
        printf 'Unsupported native manager: %s\n' "$forced_native_pm" >&2
        exit 2
    }
    [[ "$selected_flavor" == default || -d "$(flavor_root)" ]] || {
        printf 'Unknown flavor: %s\n' "$selected_flavor" >&2
        exit 2
    }
}

choose_native_pm() {
    local detected
    detected="$(detect_native_pm 2>/dev/null || echo auto)"
    if [[ -n "$forced_native_pm" && "$forced_native_pm" != auto ]]; then
        printf '%s\n' "$forced_native_pm"
    else
        printf '%s\n' "$detected"
    fi
}

print_banner() {
    local logo="$source_root/share/tinypm/logo.txt"
    [[ "$selected_flavor" == default ]] || logo="$(flavor_file logo.txt 2>/dev/null || echo "$logo")"
    if [[ "$non_interactive" -eq 0 && -r "$logo" ]]; then
        printf '%s' "$c_cyan" >&2
        cat "$logo" >&2
        printf '%s\n' "$c_reset" >&2
    fi
    printf '%s%s installer%s\n' "$c_bold$c_cyan" "$FLAVOR_NAME" "$c_reset"
    [[ -z "$FLAVOR_TAGLINE" ]] || printf '%s\n' "$FLAVOR_TAGLINE"
}

install_runtime() {
    mkdir -p "$bin_dir" "$local_bin" "$config_dir"

    # Remove layouts and commands left by pre-V4 development versions.
    rm -rf "${bin_dir:?}/lib" "$bin_dir/share" "$bin_dir/assets" "$bin_dir/flavors"
    rm -f "$bin_dir/Forge" "$bin_dir/Parcel" "$bin_dir/version" "$bin_dir/_spinner"
    rm -f "$local_bin/Forge" "$local_bin/Parcel" "$local_bin/version" "$local_bin/_spinner"

    rm -rf "$lib_dir" "$share_dir"
    mkdir -p "$lib_dir" "$share_dir"
    cp -R "$source_root/lib/tinypm/." "$lib_dir/"
    cp "$source_root/share/tinypm/catalog.tsv" "$source_root/share/tinypm/aliases.tsv" \
        "$source_root/share/tinypm/logo.txt" "$share_dir/"
    cp -R "$source_root/share/tinypm/flavors" "$share_dir/"
    cp -R "$source_root/share/tinypm/completions" "$share_dir/"
    cp "$source_root/bin/tinypm" "$source_root/bin/syspm" "$bin_dir/"
    chmod +x "$bin_dir/tinypm" "$bin_dir/syspm"

    local command
    for command in tiny grab grab-add-repo grab-de; do
        ln -sfn tinypm "$bin_dir/$command"
    done
    for command in tinypm tiny grab grab-add-repo grab-de; do
        ln -sfn "$bin_dir/$command" "$local_bin/$command"
    done
    ln -sfn "$bin_dir/syspm" "$local_bin/syspm"

    # Install optional shell metadata in each shell's conventional user path.
    mkdir -p "$data_home/bash-completion/completions" "$data_home/zsh/site-functions"
    ln -sfn "$share_dir/completions/tinypm.bash" "$data_home/bash-completion/completions/tinypm"
    for command in tiny grab grab-add-repo grab-de syspm; do
        ln -sfn tinypm "$data_home/bash-completion/completions/$command"
    done
    ln -sfn "$share_dir/completions/_tinypm" "$data_home/zsh/site-functions/_tinypm"

    mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions"
    for command in tinypm tiny grab grab-add-repo grab-de syspm; do
        ln -sfn "$share_dir/completions/tinypm.fish" \
            "${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions/$command.fish"
    done
}

write_config() {
    printf 'native_pm=%s\n' "$1" >"$config_file"
    printf 'tinypm_flavor=%s\n' "$selected_flavor" >>"$config_file"
}

add_path_line() {
    local shell_rc="$1"
    # shellcheck disable=SC2016
    grep -q 'HOME/.local/bin' "$shell_rc" 2>/dev/null || printf '\n# TinyPM\nexport PATH="$HOME/.local/bin:$PATH"\n' >>"$shell_rc"
}

configure_path() {
    add_path_line "$HOME/.bashrc"
    if command -v zsh >/dev/null 2>&1 || [[ -e "$HOME/.zshrc" ]]; then add_path_line "$HOME/.zshrc"; fi
    if [[ -e "$HOME/.profile" ]]; then add_path_line "$HOME/.profile"; fi
}

main() {
    local selected_pm
    parse_options "$@"
    load_flavor
    selected_pm="$(choose_native_pm)"
    print_banner
    install_runtime
    write_config "$selected_pm"
    configure_path

    printf '%s[ok]%s Installed to %s\n' "$c_green" "$c_reset" "$prefix"
    printf 'Native manager: %s\n' "$selected_pm"
    printf 'Commands: %s\n' "$local_bin"
    # shellcheck disable=SC2016
    printf 'Try: export PATH="$HOME/.local/bin:$PATH" && grab --dry-run curl\n'
}

main "$@"
