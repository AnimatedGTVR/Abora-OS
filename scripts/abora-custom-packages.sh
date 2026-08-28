#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"
if [[ ! -f "$ui_lib" && -f /etc/abora/ui.sh ]]; then
    ui_lib="/etc/abora/ui.sh"
fi

if [[ -f "$ui_lib" ]]; then
    # shellcheck source=/dev/null
    source "$ui_lib"
else
    # Minimal fallback UI -- used when abora-ui.sh isn't available (e.g. a
    # bare checkout before install, or a corrupted /etc/abora).
    ABORA_DIM=$'\033[38;5;242m'
    ABORA_NC=$'\033[0m'
    ABORA_CYAN=$'\033[38;5;44m'
    ABORA_WHITE=$'\033[1;97m'
    ABORA_BLUE=$'\033[38;5;33m'
    abora_banner()   { printf '\n  %b%s%b  %b%s%b\n\n' "$ABORA_WHITE" "${1:-}" "$ABORA_NC" "$ABORA_DIM" "${2:-}" "$ABORA_NC"; }
    abora_info()     { printf '  %b·%b  %s\n' "$ABORA_CYAN" "$ABORA_NC" "$1"; }
    abora_success()  { printf '  \033[38;5;77m✓\033[0m  \033[38;5;77m%s\033[0m\n' "$1"; }
    abora_error()    { printf '  \033[38;5;203m✗\033[0m  \033[38;5;203m%s\033[0m\n' "$1" >&2; }
    abora_step()     { printf '  \033[38;5;44m▸\033[0m  %s\n' "$1"; }
    abora_dim_line() { printf '  \033[38;5;242m%s\033[0m\n' "$1"; }
fi

config_dir="${ABORA_SYSTEM_CONFIG:-/etc/nixos}"
abora_dir="${config_dir}/abora"
state_dir="${abora_dir}/custom-packages"
flake_target="${ABORA_FLAKE_CONFIG_NAME:-abora}"

# Every temp file/dir this script creates (the downloaded zip, the
# extraction dir) is registered here and removed exactly once when the
# process exits, for any reason. This used to be two separate `trap ...
# RETURN` calls, one in update_package() and one in
# install_modularity_zip() -- broken two different ways: (1) `trap ...
# RETURN` never fires when a function ends via `exit` (only on a normal
# `return`/falling off the end), and virtually every error path here calls
# `exit`, including `set -e`-triggered aborts like a failed download; (2)
# `trap` is not function-scoped in bash, so install_modularity_zip()'s
# RETURN trap silently overwrote update_package()'s, meaning even the
# success path never cleaned up the downloaded zip. Reproduced directly:
# `abora apps custom update modularity-stable --url <url-that-fails>`
# left the downloaded temp file behind in /tmp every time. A single EXIT
# trap fires exactly once no matter how the process ends.
_custom_pkg_cleanup_paths=()
_custom_pkg_register_cleanup() {
    _custom_pkg_cleanup_paths+=("$1")
}
_custom_pkg_cleanup() {
    local p
    for p in "${_custom_pkg_cleanup_paths[@]+"${_custom_pkg_cleanup_paths[@]}"}"; do
        rm -rf "$p" 2>/dev/null || true
    done
}
trap _custom_pkg_cleanup EXIT

usage() {
    abora_banner "Custom Packages" "Update standalone Abora packages outside normal Nixpkgs."
    printf '  %bUsage%b\n\n' "$ABORA_WHITE" "$ABORA_NC"
    printf '  %babora apps custom list%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show standalone packages Abora knows how to update."
    printf '\n'
    printf '  %babora apps custom info <id>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show package status and update instructions."
    printf '\n'
    printf '  %bsudo abora apps custom update modularity-stable --zip <file>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Install or update Modularity Stable from a downloaded Linux zip."
    printf '\n'
    printf '  %bsudo abora apps custom update modularity-stable --url <url>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Download the zip first, then install it."
    printf '\n'
    printf '  %bOptions%b\n\n' "$ABORA_WHITE" "$ABORA_NC"
    printf '  %b--version <version>%b       Save the installed standalone package version.\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b--zip-root <folder>%b      Expected folder inside the zip. Defaults to Modularity-<version>-Linux.\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b--no-rebuild%b             Update files only; run abora apps rebuild later.\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %b--dry-run%b                Validate inputs and print what would happen.\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '\n'
}

run_as_root() {
    if [[ "${ABORA_NO_SUDO:-0}" == "1" ]]; then
        "$@"
        return $?
    fi

    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
        return $?
    fi

    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"
        return $?
    fi

    abora_error "This command needs root privileges."
    exit 1
}

require_installed_system() {
    if [[ ! -d "$abora_dir" || ! -f "$config_dir/flake.nix" ]]; then
        abora_error "Custom package updates work on an installed Abora system, not the live image."
        exit 1
    fi
}

stage_config_for_flake() {
    if command -v git >/dev/null 2>&1 \
        && [[ -d "$config_dir" ]] \
        && run_as_root git -C "$config_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        run_as_root git -C "$config_dir" add -A >/dev/null 2>&1 || true
    fi
}

rebuild_system() {
    abora_step "Rebuilding Abora with updated custom packages"
    printf '\n'
    stage_config_for_flake
    run_as_root nixos-rebuild switch --flake "${config_dir}#${flake_target}"
}

package_known() {
    case "$1" in
        modularity-stable|modularity) return 0 ;;
        *) return 1 ;;
    esac
}

canonical_package_id() {
    case "$1" in
        modularity) printf '%s\n' "modularity-stable" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

show_list() {
    abora_banner "Custom Packages" "Standalone packages with Abora update helpers."
    printf '  %b·%b  %-20s %b%s%b\n' \
        "$ABORA_BLUE" "$ABORA_NC" \
        "modularity-stable" \
        "$ABORA_DIM" "Modularity Stable Linux zip, installed into the Abora vendor tree" "$ABORA_NC"
    printf '\n'
}

state_file_for() {
    printf '%s/%s.env\n' "$state_dir" "$1"
}

show_info() {
    local id="$1" state_file version="not installed" source="unknown" updated="never"
    id="$(canonical_package_id "$id")"
    package_known "$id" || { abora_error "Unknown custom package: $id"; exit 1; }
    state_file="$(state_file_for "$id")"
    if [[ -f "$state_file" ]]; then
        # shellcheck disable=SC1090
        source "$state_file"
        version="${CUSTOM_PACKAGE_VERSION:-$version}"
        source="${CUSTOM_PACKAGE_SOURCE:-$source}"
        updated="${CUSTOM_PACKAGE_UPDATED_AT:-$updated}"
    fi

    abora_banner "Custom Package" "$id"
    printf '  %bName%b       Modularity Stable\n' "$ABORA_WHITE" "$ABORA_NC"
    printf '  %bStatus%b     %s\n' "$ABORA_WHITE" "$ABORA_NC" "$version"
    printf '  %bSource%b     %s\n' "$ABORA_WHITE" "$ABORA_NC" "$source"
    printf '  %bUpdated%b    %s\n' "$ABORA_WHITE" "$ABORA_NC" "$updated"
    printf '  %bInstall%b    %s\n' "$ABORA_WHITE" "$ABORA_NC" "${abora_dir}/vendor/modularity/bin/Modularity"
    printf '\n'
}

download_to_file() {
    local url="$1" output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fL "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$output" "$url"
    else
        abora_error "curl or wget is required to download custom packages."
        exit 1
    fi
}

write_state() {
    local id="$1" version="$2" source="$3" tmp
    tmp="$(mktemp)"
    chmod 0644 "$tmp"
    {
        printf 'CUSTOM_PACKAGE_ID=%q\n' "$id"
        printf 'CUSTOM_PACKAGE_VERSION=%q\n' "$version"
        printf 'CUSTOM_PACKAGE_SOURCE=%q\n' "$source"
        printf 'CUSTOM_PACKAGE_UPDATED_AT=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$tmp"
    run_as_root mkdir -p "$state_dir"
    run_as_root mv "$tmp" "$(state_file_for "$id")"
}

install_modularity_zip() {
    local zip_path="$1" version="$2" zip_root="$3" source_label="$4" no_rebuild="$5" dry_run="$6"
    local tmp root lib_dir target backup

    [[ -f "$zip_path" ]] || { abora_error "Zip file not found: $zip_path"; exit 1; }
    command -v unzip >/dev/null 2>&1 || { abora_error "unzip is required to install Modularity Stable."; exit 1; }

    tmp="$(mktemp -d)"
    _custom_pkg_register_cleanup "$tmp"
    unzip -q "$zip_path" -d "$tmp"

    root="$tmp/$zip_root"
    if [[ ! -d "$root" ]]; then
        root="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -iname 'Modularity*Linux*' | head -n 1)"
    fi

    [[ -n "$root" && -d "$root" ]] || { abora_error "Could not find a Modularity Linux folder inside the zip."; exit 1; }
    [[ -x "$root/bin/Modularity" ]] || { abora_error "Missing executable inside zip: bin/Modularity"; exit 1; }

    target="${abora_dir}/vendor/modularity"

    abora_banner "Custom Package Update" "Modularity Stable ${version}"
    abora_info "Source: $source_label"
    abora_info "Target: $target"
    printf '\n'

    if [[ "$dry_run" == "true" ]]; then
        abora_success "Dry run passed. The zip layout looks usable."
        [[ "$no_rebuild" == "true" ]] || abora_info "Would run: nixos-rebuild switch --flake ${config_dir}#${flake_target}"
        printf '\n'
        return 0
    fi

    require_installed_system
    backup="${target}.backup.$(date -u +%Y%m%d%H%M%S)"
    if [[ -d "$target" ]]; then
        run_as_root cp -a "$target" "$backup"
    fi

    run_as_root mkdir -p "$target/bin" "$target/lib" "$target/share/modularity"
    run_as_root rm -rf "$target/bin" "$target/lib"
    run_as_root mkdir -p "$target/bin" "$target/lib" "$target/share/modularity"
    run_as_root install -m 0755 "$root/bin/Modularity" "$target/bin/Modularity"

    lib_dir="$root/bin/linux.x86_64/release"
    if [[ -d "$lib_dir" ]]; then
        while IFS= read -r -d '' lib; do
            run_as_root cp "$lib" "$target/lib/"
        done < <(find "$lib_dir" -maxdepth 1 -type f -name '*.so*' -print0)
    fi

    if [[ -d "$root/share/modularity/Resources" ]]; then
        run_as_root rm -rf "$target/share/modularity/Resources"
        run_as_root cp -R "$root/share/modularity/Resources" "$target/share/modularity/Resources"
    fi

    write_state "modularity-stable" "$version" "$source_label"
    abora_success "Modularity Stable files updated."
    [[ ! -d "$backup" ]] || abora_dim_line "Backup: $backup"

    if [[ "$no_rebuild" == "false" ]]; then
        rebuild_system
    else
        abora_info "Skipped rebuild. Run: abora apps rebuild"
    fi
    printf '\n'
}

update_package() {
    local id="${1:-}" zip_path="" url="" version="7.0.0" zip_root="" no_rebuild=false dry_run=false
    [[ -n "$id" ]] || { usage; exit 1; }
    id="$(canonical_package_id "$id")"
    shift || true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --zip)
                shift; [[ $# -gt 0 ]] || { abora_error "--zip needs a file path"; exit 2; }
                zip_path="$1"; shift ;;
            --url)
                shift; [[ $# -gt 0 ]] || { abora_error "--url needs a download URL"; exit 2; }
                url="$1"; shift ;;
            --version)
                shift; [[ $# -gt 0 ]] || { abora_error "--version needs a value"; exit 2; }
                version="$1"; shift ;;
            --zip-root)
                shift; [[ $# -gt 0 ]] || { abora_error "--zip-root needs a folder name"; exit 2; }
                zip_root="$1"; shift ;;
            --no-rebuild) no_rebuild=true; shift ;;
            --dry-run) dry_run=true; no_rebuild=true; shift ;;
            -h|--help) usage; exit 0 ;;
            *) abora_error "Unknown option: $1"; exit 2 ;;
        esac
    done

    package_known "$id" || { abora_error "Unknown custom package: $id"; exit 1; }
    zip_root="${zip_root:-Modularity-${version}-Linux}"

    if [[ -n "$url" ]]; then
        local tmp_zip
        tmp_zip="$(mktemp)"
        _custom_pkg_register_cleanup "$tmp_zip"
        abora_step "Downloading custom package"
        download_to_file "$url" "$tmp_zip"
        zip_path="$tmp_zip"
        install_modularity_zip "$zip_path" "$version" "$zip_root" "$url" "$no_rebuild" "$dry_run"
    elif [[ -n "$zip_path" ]]; then
        install_modularity_zip "$zip_path" "$version" "$zip_root" "$zip_path" "$no_rebuild" "$dry_run"
    else
        abora_error "Provide --zip <file> or --url <url>."
        abora_dim_line "Example: sudo abora apps custom update modularity-stable --zip ~/Downloads/Modularity-7.0.0-Linux.zip"
        exit 2
    fi
}

main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        list) show_list ;;
        info)
            [[ -n "${1:-}" ]] || { abora_error "Usage: abora apps custom info <id>"; exit 1; }
            show_info "$1"
            ;;
        update|install)
            update_package "$@"
            ;;
        help|--help|-h|"") usage ;;
        *)
            abora_error "Unknown custom package command: $command"
            printf '\n'
            usage
            exit 1
            ;;
    esac
}

main "$@"
