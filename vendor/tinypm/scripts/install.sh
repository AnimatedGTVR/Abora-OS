#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${TINYPM_PREFIX:-$HOME/.tinypm}"
BIN_DIR="$PREFIX/bin"
LOCAL_BIN="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tinypm"
CONFIG_FILE="$CONFIG_DIR/config"
DEFAULT_FLAVOR="default"

forced_native_pm=""
non_interactive=0
selected_flavor="${TINYPM_FLAVOR:-$DEFAULT_FLAVOR}"

flavor_root() {
    printf '%s\n' "$HERE/flavors/$selected_flavor"
}

flavor_file() {
    local relative_path="$1"
    local candidate

    candidate="$(flavor_root)/$relative_path"
    [[ -r "$candidate" ]] && {
        printf '%s\n' "$candidate"
        return 0
    }

    return 1
}

resolved_logo_file() {
    flavor_file logo.txt || printf '%s\n' "$HERE/share/logo.txt"
}

resolved_catalog_file() {
    flavor_file catalog.tsv || printf '%s\n' "$HERE/share/catalog.tsv"
}

load_flavor_metadata() {
    local config_file

    FLAVOR_NAME="TinyPM V3"
    FLAVOR_ENGINE_NAME="Parcel"
    FLAVOR_TAGLINE=""

    config_file="$(flavor_file flavor.conf || true)"
    # shellcheck disable=SC1090
    [[ -n "$config_file" ]] && . "$config_file"
    return 0
}

print_logo() {
    [[ -r "$(resolved_logo_file)" ]] && { cat "$(resolved_logo_file)" >&2; printf '\n' >&2; }
}

detect_native_pm() {
    command -v apt-get >/dev/null 2>&1 && { echo apt; return; }
    command -v dnf >/dev/null 2>&1 && { echo dnf; return; }
    command -v pacman >/dev/null 2>&1 && { echo pacman; return; }
    command -v xbps-install >/dev/null 2>&1 && { echo xbps; return; }
    command -v zypper >/dev/null 2>&1 && { echo zypper; return; }
    command -v apk >/dev/null 2>&1 && { echo apk; return; }
    command -v emerge >/dev/null 2>&1 && { echo emerge; return; }
    command -v brew >/dev/null 2>&1 && { echo brew; return; }
    command -v nix-env >/dev/null 2>&1 && { echo nix; return; }
    return 1
}

is_valid_native_pm() {
    case "$1" in
        auto|apt|dnf|pacman|xbps|zypper|apk|emerge|brew|nix) return 0 ;;
        *) return 1 ;;
    esac
}

parse_cli_options() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --flavor=*)
                selected_flavor="${1#*=}"
                shift
                ;;
            --flavor)
                shift
                [[ $# -gt 0 ]] || { echo "Missing value for --flavor" >&2; exit 1; }
                selected_flavor="$1"
                shift
                ;;
            -y|--yes|--non-interactive)
                non_interactive=1
                shift
                ;;
            --auto)
                forced_native_pm="auto"
                shift
                ;;
            --native=*)
                forced_native_pm="${1#*=}"
                shift
                ;;
            --native)
                shift
                [[ $# -gt 0 ]] || { echo "Missing value for --native" >&2; exit 1; }
                forced_native_pm="$1"
                shift
                ;;
            -h|--help)
                cat <<'EOH'
TinyPM V3 / Parcel installer

Usage:
  ./install.sh [--auto] [--native <pm>] [--flavor <name>] [--yes]

Native pm values:
  auto, apt, dnf, pacman, xbps, zypper, apk, emerge, brew, nix
EOH
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done

    if [[ -n "$forced_native_pm" ]] && ! is_valid_native_pm "$forced_native_pm"; then
        echo "Invalid native pm: $forced_native_pm" >&2
        exit 1
    fi

    if [[ "$selected_flavor" != "$DEFAULT_FLAVOR" && ! -d "$(flavor_root)" ]]; then
        echo "Unknown flavor: $selected_flavor" >&2
        exit 1
    fi
}

choose_native_pm() {
    local detected
    detected="$(detect_native_pm 2>/dev/null || echo auto)"

    if [[ -n "$forced_native_pm" ]]; then
        if [[ "$forced_native_pm" == "auto" ]]; then
            echo "$detected"
        else
            echo "$forced_native_pm"
        fi
        return
    fi

    if [[ "$non_interactive" -eq 1 ]]; then
        echo "$detected"
        return
    fi

    print_logo
    printf '%s / %s Installer\n' "$FLAVOR_NAME" "$FLAVOR_ENGINE_NAME" >&2
    [[ -n "$FLAVOR_TAGLINE" ]] && printf '%s\n' "$FLAVOR_TAGLINE" >&2
    if [[ "$detected" == "auto" ]]; then
        printf 'No native package manager was detected. %s will still use Flatpak or Snap when available.\n\n' "$FLAVOR_NAME" >&2
    else
        printf 'Detected native source: %s\n\n' "$detected" >&2
    fi
    echo "$detected"
}

install_runtime() {
    local cmd

    mkdir -p "$BIN_DIR" "$LOCAL_BIN" "$CONFIG_DIR"

    cp -R "$HERE/lib" "$BIN_DIR/"
    cp -R "$HERE/share" "$BIN_DIR/"
    cp -R "$HERE/assets" "$BIN_DIR/"
    [[ -d "$HERE/flavors" ]] && cp -R "$HERE/flavors" "$BIN_DIR/"
    cp -f "$HERE/_spinner" "$BIN_DIR/_spinner"
    cp -f "$HERE/tinypm" "$BIN_DIR/tinypm"
    cp -f "$HERE/version" "$BIN_DIR/version"
    cp -f "$HERE/Parcel" "$BIN_DIR/Parcel"
    if [[ -f "$HERE/syspm.sh" ]]; then
        cp -f "$HERE/syspm.sh" "$BIN_DIR/syspm"
    fi

    cp -f "$(resolved_logo_file)" "$BIN_DIR/share/logo.txt"
    cp -f "$(resolved_catalog_file)" "$BIN_DIR/share/catalog.tsv"

    chmod +x "$BIN_DIR/_spinner" "$BIN_DIR/tinypm" "$BIN_DIR/version" "$BIN_DIR/Parcel"
    [[ -f "$BIN_DIR/syspm" ]] && chmod +x "$BIN_DIR/syspm"

    ln -sfn "$BIN_DIR/tinypm" "$BIN_DIR/tiny"
    ln -sfn "$BIN_DIR/tinypm" "$BIN_DIR/grab"

    ln -sfn "$BIN_DIR/tinypm" "$LOCAL_BIN/tinypm"
    ln -sfn "$BIN_DIR/tinypm" "$LOCAL_BIN/tiny"
    ln -sfn "$BIN_DIR/tinypm" "$LOCAL_BIN/grab"
    ln -sfn "$BIN_DIR/Parcel" "$LOCAL_BIN/Parcel"
    [[ -f "$BIN_DIR/syspm" ]] && ln -sfn "$BIN_DIR/syspm" "$LOCAL_BIN/syspm"
    ln -sfn "$BIN_DIR/version" "$LOCAL_BIN/version"
    ln -sfn "$BIN_DIR/_spinner" "$LOCAL_BIN/_spinner"
}

write_config() {
    printf 'native_pm=%s\n' "$1" > "$CONFIG_FILE"
    printf 'tinypm_flavor=%s\n' "$selected_flavor" >> "$CONFIG_FILE"
}

ensure_local_bin_on_path() {
    local shell_rc="$HOME/.bashrc"
    [[ -n "${ZSH_VERSION:-}" ]] && shell_rc="$HOME/.zshrc"

    if ! grep -q 'HOME/.local/bin' "$shell_rc" 2>/dev/null; then
        printf "\n# TinyPM\nexport PATH=\"\$HOME/.local/bin:\$PATH\"\n" >>"$shell_rc"
    fi
}

main() {
    local selected_pm

    parse_cli_options "$@"
    load_flavor_metadata
    selected_pm="$(choose_native_pm)"

    install_runtime
    write_config "$selected_pm"
    ensure_local_bin_on_path

    printf '\n%s installed to %s\n' "$FLAVOR_NAME" "$BIN_DIR"
    printf 'Primary native source: %s\n' "$selected_pm"
    printf 'Flavor: %s\n' "$selected_flavor"
    printf 'Commands linked into %s\n' "$LOCAL_BIN"
    printf '\nOpen a new terminal or run:\n'
    printf '  hash -r\n'
    printf "  export PATH=\"\$HOME/.local/bin:\$PATH\"\n"
    printf '\nThen test:\n'
    printf "  \"\$HOME/.tinypm/bin/tinypm\" help\n"
    printf "  \"\$HOME/.tinypm/bin/tinypm\" selftest\n"
    printf "  \"\$HOME/.tinypm/bin/tinypm\" doctor --fix\n"
    printf '  grab firefox\n'
    printf '  syspm update\n'
}

main "$@"
