#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
catalog_lib="${ABORA_APP_CATALOG_LIB:-$script_dir/abora-app-catalog.sh}"

if [[ ! -f "$catalog_lib" && -f /etc/abora/app-catalog.sh ]]; then
    catalog_lib="/etc/abora/app-catalog.sh"
fi

# shellcheck source=/dev/null
source "$catalog_lib"

config_dir="${ABORA_SYSTEM_CONFIG:-/etc/nixos}"
abora_dir="${config_dir}/abora"
apps_list="${abora_dir}/apps.list"
apps_module="${abora_dir}/apps.nix"
flake_target="${ABORA_FLAKE_CONFIG_NAME:-abora}"
default_repo_ref="${ABORA_REPO_REF:-main}"

info() {
    printf '[*] %s\n' "$1"
}

error_msg() {
    printf '[x] %s\n' "$1" >&2
}

usage() {
    cat <<'EOF'
Usage:
  abora-apps catalog
  abora-apps installed
  abora-apps set [app-id...]
  abora-apps add <app-id...>
  abora-apps remove <app-id...>
  abora-apps bundle <favorites|essentials|social|creator|developer>
EOF
}

is_installed_system() {
    [[ -d "$abora_dir" && -f "$config_dir/flake.nix" ]]
}

run_as_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"
        return 0
    fi

    error_msg "This command needs root privileges."
    exit 1
}

ensure_layout() {
    if ! is_installed_system; then
        error_msg "App installs work on an installed Abora system, not the live image."
        exit 1
    fi

    mkdir -p "$abora_dir"

    if [[ ! -f "$apps_list" ]]; then
        : > "$apps_list"
    fi

    if [[ ! -f "$apps_module" ]]; then
        render_apps_module
    fi
}

read_selected_ids() {
    if [[ ! -f "$apps_list" ]]; then
        return 0
    fi

    grep -v '^[[:space:]]*$' "$apps_list" 2>/dev/null | grep -v '^[[:space:]]*#' || true
}

write_selected_ids() {
    local tmp=""
    tmp="$(mktemp)"
    printf '%s\n' "$@" | awk 'NF && !seen[$0]++' > "$tmp"
    mv "$tmp" "$apps_list"
}

render_apps_module() {
    local tmp=""
    local app_id=""
    local app_expr=""

    tmp="$(mktemp)"

    {
        printf '{ pkgs, ... }:\n'
        printf '{\n'
        printf '  environment.systemPackages = with pkgs; [\n'
        while IFS= read -r app_id; do
            [[ -n "$app_id" ]] || continue
            app_expr="$(abora_catalog_expr "$app_id")" || continue
            printf '    %s\n' "$app_expr"
        done < <(read_selected_ids)
        printf '  ];\n'
        printf '}\n'
    } > "$tmp"

    mv "$tmp" "$apps_module"
}

rebuild_system() {
    info "Rebuilding Abora with the updated app selection"
    nixos-rebuild switch --flake "${config_dir}#${flake_target}"
}

validate_ids() {
    local app_id=""

    for app_id in "$@"; do
        if ! abora_catalog_has_app "$app_id"; then
            error_msg "Unknown app id: $app_id"
            exit 1
        fi
    done
}

catalog_table() {
    local app_id=""
    local app_name=""
    local app_expr=""
    local app_group=""
    local app_description=""
    local app_favorite=""

    while IFS='|' read -r app_id app_name app_expr app_group app_description app_favorite; do
        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$app_id" "$app_name" "$app_group" "$app_description" "$app_favorite"
    done < <(abora_app_catalog)
}

installed_table() {
    local app_id=""
    local app_name=""
    local app_group=""
    local app_description=""

    while IFS= read -r app_id; do
        [[ -n "$app_id" ]] || continue
        app_name="$(abora_catalog_name "$app_id" 2>/dev/null || printf '%s' "$app_id")"
        app_group="$(abora_catalog_group "$app_id" 2>/dev/null || printf 'Custom')"
        app_description="$(abora_catalog_description "$app_id" 2>/dev/null || printf 'Managed by Abora')"
        printf '%s\t%s\t%s\n' "$app_name" "$app_group" "$app_description"
    done < <(read_selected_ids)
}

set_selection() {
    run_as_root bash -lc '
        set -euo pipefail
        source "'"$catalog_lib"'"
        config_dir="'"$config_dir"'"
        abora_dir="${config_dir}/abora"
        apps_list="${abora_dir}/apps.list"
        apps_module="${abora_dir}/apps.nix"
        flake_target="'"$flake_target"'"

        mkdir -p "$abora_dir"
        : > "$apps_list"
        printf "%s\n" "$@" | awk "NF && !seen[\$0]++" > "$apps_list"

        tmp="$(mktemp)"
        {
            printf "{ pkgs, ... }:\n"
            printf "{\n"
            printf "  environment.systemPackages = with pkgs; [\n"
            while IFS= read -r app_id; do
                [[ -n "$app_id" ]] || continue
                app_expr="$(abora_catalog_expr "$app_id")" || continue
                printf "    %s\n" "$app_expr"
            done < "$apps_list"
            printf "  ];\n"
            printf "}\n"
        } > "$tmp"
        mv "$tmp" "$apps_module"

        nixos-rebuild switch --flake "${config_dir}#${flake_target}"
    ' _ "$@"
}

main() {
    local command="${1:-}"
    local selected=()
    local app_id=""

    case "$command" in
        catalog)
            catalog_table
            ;;
        installed)
            installed_table
            ;;
        set)
            shift || true
            validate_ids "$@"
            ensure_layout
            set_selection "$@"
            ;;
        add)
            shift || true
            validate_ids "$@"
            ensure_layout
            while IFS= read -r app_id; do
                [[ -n "$app_id" ]] || continue
                selected+=("$app_id")
            done < <(read_selected_ids)
            selected+=("$@")
            set_selection "${selected[@]}"
            ;;
        remove)
            shift || true
            validate_ids "$@"
            ensure_layout
            while IFS= read -r app_id; do
                [[ -n "$app_id" ]] || continue
                case " $* " in
                    *" $app_id "*) ;;
                    *) selected+=("$app_id") ;;
                esac
            done < <(read_selected_ids)
            set_selection "${selected[@]}"
            ;;
        bundle)
            shift || true
            if [[ -z "${1:-}" ]]; then
                usage
                exit 1
            fi
            ensure_layout
            while IFS= read -r app_id; do
                [[ -n "$app_id" ]] || continue
                selected+=("$app_id")
            done < <(read_selected_ids)
            while IFS= read -r app_id; do
                [[ -n "$app_id" ]] || continue
                selected+=("$app_id")
            done < <(abora_catalog_bundle_ids "$1")
            set_selection "${selected[@]}"
            ;;
        "" | help | --help | -h)
            usage
            ;;
        *)
            error_msg "Unknown command: $command"
            usage
            exit 1
            ;;
    esac
}

main "$@"
