#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
catalog_lib="${ABORA_APP_CATALOG_LIB:-$script_dir/abora-app-catalog.sh}"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"

if [[ ! -f "$catalog_lib" && -f /etc/abora/app-catalog.sh ]]; then
    catalog_lib="/etc/abora/app-catalog.sh"
fi

if [[ ! -f "$ui_lib" && -f /etc/abora/ui.sh ]]; then
    ui_lib="/etc/abora/ui.sh"
fi

# shellcheck source=/dev/null
source "$catalog_lib"
# shellcheck source=/dev/null
source "$ui_lib"

config_dir="${ABORA_SYSTEM_CONFIG:-/etc/nixos}"
abora_dir="${config_dir}/abora"
apps_list="${abora_dir}/apps.list"
apps_module="${abora_dir}/apps.nix"
flake_target="${ABORA_FLAKE_CONFIG_NAME:-abora}"
default_repo_ref="${ABORA_REPO_REF:-main}"

usage() {
    abora_banner "App Manager" "Install and remove apps on your Abora system."
    printf '  %bUsage%b\n\n' "$ABORA_WHITE" "$ABORA_NC"
    printf '  %babora-apps catalog%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Browse all available apps by category."
    printf '\n'
    printf '  %babora-apps search <term>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Search apps by name, ID, or description."
    printf '\n'
    printf '  %babora-apps info <app-id>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show details about a specific app."
    printf '\n'
    printf '  %babora-apps installed%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  List apps currently installed on this system."
    printf '\n'
    printf '  %babora-apps add <app-id...> [--no-rebuild] [--dry-run]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Add one or more apps (rebuilds unless --no-rebuild is given)."
    printf '\n'
    printf '  %babora-apps remove <app-id...> [--no-rebuild] [--dry-run]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Remove one or more apps (rebuilds unless --no-rebuild is given)."
    printf '\n'
    printf '  %babora-apps set [app-id...] [--no-rebuild] [--dry-run]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Replace the full app list."
    printf '\n'
    printf '  %babora-apps bundle <name> [--no-rebuild] [--dry-run]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Add a curated bundle: favorites essentials social creator developer gaming system"
    printf '\n'
    printf '  %babora-apps rebuild%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Apply the current app list (nixos-rebuild switch)."
    printf '\n'
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

    abora_error "This command needs root privileges."
    exit 1
}

ensure_layout() {
    if ! is_installed_system; then
        abora_error "App installs work on an installed Abora system, not the live image."
        exit 1
    fi

    run_as_root mkdir -p "$abora_dir"

    if [[ ! -f "$apps_list" ]]; then
        run_as_root touch "$apps_list"
        run_as_root chmod 644 "$apps_list"
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
    local tmp
    tmp="$(mktemp)"
    chmod 644 "$tmp"
    printf '%s\n' "$@" | awk 'NF && !seen[$0]++' > "$tmp"
    run_as_root mv "$tmp" "$apps_list"
}

render_apps_module() {
    local tmp app_id app_expr
    tmp="$(mktemp)"
    chmod 644 "$tmp"
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
    run_as_root mv "$tmp" "$apps_module"
}

rebuild_system() {
    abora_step "Rebuilding Abora with the updated app selection"
    printf '\n'
    nixos-rebuild switch --flake "${config_dir}#${flake_target}"
}

validate_ids() {
    local app_id
    for app_id in "$@"; do
        if ! abora_catalog_has_app "$app_id"; then
            abora_error "Unknown app id: $app_id"
            exit 1
        fi
    done
}

validate_bundle() {
    local bundle="$1"
    if ! abora_catalog_bundle_ids "$bundle" >/dev/null 2>&1; then
        abora_error "Unknown bundle: $bundle"
        abora_dim_line "Valid bundles: favorites, essentials, social, creator, developer, gaming, system"
        exit 1
    fi
}

# ── Catalog display ───────────────────────────────────────────────────────────

show_catalog() {
    local app_id app_name app_expr app_group app_description app_favorite
    local current_group="" total=0 cols name_width desc_width

    cols="$(abora_cols)"
    name_width=18
    desc_width=$((cols - name_width - 22))
    [[ $desc_width -lt 20 ]] && desc_width=20

    while IFS='|' read -r app_id app_name app_expr app_group app_description app_favorite; do
        total=$((total + 1))
    done < <(abora_app_catalog)

    abora_banner "App Catalog" "${total} apps available — run 'abora-apps add <id>' to install."

    while IFS='|' read -r app_id app_name app_expr app_group app_description app_favorite; do
        if [[ "$app_group" != "$current_group" ]]; then
            [[ -n "$current_group" ]] && printf '\n'
            current_group="$app_group"
            printf '  %b%s%b\n' "$ABORA_WHITE" "${app_group^^}" "$ABORA_NC"
            abora_rule
        fi

        local id_col name_col desc_col
        id_col="$(abora_trunc "$app_id" 14)"
        name_col="$(abora_trunc "$app_name" "$name_width")"
        desc_col="$(abora_trunc "$app_description" "$desc_width")"

        printf '  %b·%b  %-14s  %b%-*s%b  %b%s%b' \
            "$ABORA_BLUE" "$ABORA_NC" \
            "$id_col" \
            "$ABORA_DIM" "$name_width" "$name_col" "$ABORA_NC" \
            "$ABORA_FAINT" "$desc_col" "$ABORA_NC"

        if [[ "$app_favorite" == "yes" ]]; then
            printf '  %b★%b' "$ABORA_YELLOW" "$ABORA_NC"
        fi

        printf '\n'
    done < <(abora_app_catalog)

    printf '\n'
}

# ── Search ────────────────────────────────────────────────────────────────────

search_apps() {
    local term="${1,,}"
    local app_id app_name app_expr app_group app_description app_favorite
    local cols name_width desc_width count=0

    cols="$(abora_cols)"
    name_width=18
    desc_width=$((cols - name_width - 22))
    [[ $desc_width -lt 20 ]] && desc_width=20

    while IFS='|' read -r app_id app_name app_expr app_group app_description app_favorite; do
        local haystack="${app_id,,}|${app_name,,}|${app_description,,}"
        [[ "$haystack" == *"$term"* ]] || continue
        count=$((count + 1))

        local id_col name_col desc_col
        id_col="$(abora_trunc "$app_id" 14)"
        name_col="$(abora_trunc "$app_name" "$name_width")"
        desc_col="$(abora_trunc "$app_description" "$desc_width")"

        printf '  %b·%b  %-14s  %b%-*s%b  %b%s%b' \
            "$ABORA_BLUE" "$ABORA_NC" \
            "$id_col" \
            "$ABORA_DIM" "$name_width" "$name_col" "$ABORA_NC" \
            "$ABORA_FAINT" "$desc_col" "$ABORA_NC"

        if [[ "$app_favorite" == "yes" ]]; then
            printf '  %b★%b' "$ABORA_YELLOW" "$ABORA_NC"
        fi
        printf '\n'
    done < <(abora_app_catalog)

    if [[ "$count" -eq 0 ]]; then
        abora_warn "No apps matched '${1}'."
    else
        printf '\n  %b%d result(s)%b\n' "$ABORA_DIM" "$count" "$ABORA_NC"
    fi
    printf '\n'
}

# ── Info ──────────────────────────────────────────────────────────────────────

show_info() {
    local app_id="$1"
    local record app_name app_expr app_group app_description app_favorite

    if ! record="$(abora_catalog_entry "$app_id")"; then
        abora_error "Unknown app: $app_id"
        exit 1
    fi

    IFS='|' read -r _ app_name app_expr app_group app_description app_favorite <<< "$record"

    local status="${ABORA_DIM}not installed${ABORA_NC}"
    local id
    while IFS= read -r id; do
        if [[ "$id" == "$app_id" ]]; then
            status="${ABORA_GREEN}installed${ABORA_NC}"
            break
        fi
    done < <(read_selected_ids 2>/dev/null || true)

    abora_banner "App Info" "$app_name"
    printf '  %bID%b           %s\n'  "$ABORA_WHITE" "$ABORA_NC" "$app_id"
    printf '  %bName%b         %s\n'  "$ABORA_WHITE" "$ABORA_NC" "$app_name"
    printf '  %bCategory%b     %s\n'  "$ABORA_WHITE" "$ABORA_NC" "$app_group"
    printf '  %bNix package%b  %s\n'  "$ABORA_WHITE" "$ABORA_NC" "$app_expr"
    printf '  %bStatus%b       %b\n'  "$ABORA_WHITE" "$ABORA_NC" "$status"
    printf '\n'
    abora_dim_line "$app_description"
    printf '\n'
}

# ── Installed display ─────────────────────────────────────────────────────────

show_installed() {
    local app_id app_name app_group app_description
    local count=0 cols name_width desc_width

    cols="$(abora_cols)"
    name_width=18
    desc_width=$((cols - name_width - 22))
    [[ $desc_width -lt 20 ]] && desc_width=20

    while IFS= read -r app_id; do
        [[ -n "$app_id" ]] || continue
        count=$((count + 1))
    done < <(read_selected_ids)

    if [[ "$count" -eq 0 ]]; then
        abora_banner "Installed Apps" "No apps installed yet."
        abora_dim_line "Run 'abora-apps catalog' to browse what's available."
        printf '\n'
        return 0
    fi

    abora_banner "Installed Apps" "${count} app(s) managed by Abora."

    while IFS= read -r app_id; do
        [[ -n "$app_id" ]] || continue
        app_name="$(abora_catalog_name "$app_id" 2>/dev/null || printf '%s' "$app_id")"
        app_group="$(abora_catalog_group "$app_id" 2>/dev/null || printf 'Custom')"
        app_description="$(abora_catalog_description "$app_id" 2>/dev/null || printf 'Managed by Abora')"

        local id_col name_col desc_col
        id_col="$(abora_trunc "$app_id" 14)"
        name_col="$(abora_trunc "$app_name" "$name_width")"
        desc_col="$(abora_trunc "$app_description" "$desc_width")"

        printf '  %b·%b  %-14s  %b%-*s%b  %b%s%b\n' \
            "$ABORA_GREEN" "$ABORA_NC" \
            "$id_col" \
            "$ABORA_DIM" "$name_width" "$name_col" "$ABORA_NC" \
            "$ABORA_FAINT" "$desc_col" "$ABORA_NC"
    done < <(read_selected_ids)

    printf '\n'
}

# ── Change helpers ────────────────────────────────────────────────────────────

print_changed_apps() {
    local action="$1"; shift
    local names=() name list=""
    for id in "$@"; do
        name="$(abora_catalog_name "$id" 2>/dev/null || printf '%s' "$id")"
        names+=("$name")
    done
    for name in "${names[@]}"; do
        [[ -n "$list" ]] && list+=", "
        list+="$name"
    done
    abora_success "${action}: ${list}"
}

show_dry_run() {
    local action="$1" no_rebuild="$2"; shift 2
    abora_step "Dry run — no changes will be made"
    printf '\n'

    if [[ "$action" == "set" ]]; then
        if [[ $# -eq 0 ]]; then
            printf '  %bWould clear all installed apps%b\n' "$ABORA_WHITE" "$ABORA_NC"
        else
            printf '  %bWould replace app list with:%b\n' "$ABORA_WHITE" "$ABORA_NC"
            for id in "$@"; do
                local name
                name="$(abora_catalog_name "$id" 2>/dev/null || printf '%s' "$id")"
                printf '    %b·%b  %s %b(%s)%b\n' \
                    "$ABORA_CYAN" "$ABORA_NC" \
                    "$name" \
                    "$ABORA_DIM" "$id" "$ABORA_NC"
            done
        fi
    else
        local color marker
        case "$action" in
            remove) color="$ABORA_RED";   marker="-" ;;
            *)      color="$ABORA_GREEN"; marker="+" ;;
        esac
        printf '  %bWould %s:%b\n' "$ABORA_WHITE" "$action" "$ABORA_NC"
        for id in "$@"; do
            local name
            name="$(abora_catalog_name "$id" 2>/dev/null || printf '%s' "$id")"
            printf '    %b%s%b  %s %b(%s)%b\n' \
                "$color" "$marker" "$ABORA_NC" \
                "$name" \
                "$ABORA_DIM" "$id" "$ABORA_NC"
        done
    fi

    printf '\n'
    if [[ "$no_rebuild" == "false" ]]; then
        abora_info "Would run: nixos-rebuild switch --flake ${config_dir}#${flake_target}"
    else
        abora_info "Would write to apps.list only (skipping rebuild)"
    fi
    printf '\n'
}

main() {
    local command="${1:-}"
    shift || true

    local no_rebuild=false dry_run=false
    local -a args=()
    for arg in "$@"; do
        case "$arg" in
            --no-rebuild) no_rebuild=true ;;
            --dry-run)    dry_run=true; no_rebuild=true ;;
            *)            args+=("$arg") ;;
        esac
    done
    set -- "${args[@]+"${args[@]}"}"

    local app_id total
    local -a current=() new_list=() bundle_ids=() keeping=()

    case "$command" in
        catalog)
            show_catalog
            ;;
        search)
            if [[ -z "${1:-}" ]]; then
                abora_error "Usage: abora-apps search <term>"
                exit 1
            fi
            abora_banner "App Search" "Results for '${1}'."
            search_apps "$1"
            ;;
        info)
            if [[ -z "${1:-}" ]]; then
                abora_error "Usage: abora-apps info <app-id>"
                exit 1
            fi
            show_info "$1"
            ;;
        installed)
            show_installed
            ;;
        rebuild)
            if [[ "$dry_run" == "true" ]]; then
                abora_step "Dry run — no changes will be made"
                printf '\n'
                abora_info "Would run: nixos-rebuild switch --flake ${config_dir}#${flake_target}"
                printf '\n'
                return 0
            fi
            ensure_layout
            abora_banner "App Manager" "Applying current app selection."
            render_apps_module
            rebuild_system
            abora_success "Done. System rebuilt."
            printf '\n'
            ;;
        set)
            validate_ids "$@"
            ensure_layout
            abora_banner "App Manager" "Replacing app selection."
            if [[ "$dry_run" == "true" ]]; then
                show_dry_run "set" "$no_rebuild" "$@"
                return 0
            fi
            write_selected_ids "$@"
            render_apps_module
            if [[ "$no_rebuild" == "false" ]]; then
                rebuild_system
            fi
            total="$(read_selected_ids | wc -l | tr -d ' ')"
            abora_success "Done. App selection replaced."
            abora_info "Total installed: $total"
            printf '\n'
            ;;
        add)
            if [[ $# -eq 0 ]]; then
                abora_error "Usage: abora-apps add <app-id...>"
                exit 1
            fi
            validate_ids "$@"
            ensure_layout
            abora_banner "App Manager" "Adding apps to your system."
            while IFS= read -r app_id; do
                [[ -n "$app_id" ]] || continue
                current+=("$app_id")
            done < <(read_selected_ids)
            new_list=("${current[@]+"${current[@]}"}" "$@")
            if [[ "$dry_run" == "true" ]]; then
                show_dry_run "add" "$no_rebuild" "$@"
                return 0
            fi
            write_selected_ids "${new_list[@]}"
            render_apps_module
            if [[ "$no_rebuild" == "false" ]]; then
                rebuild_system
            fi
            total="$(read_selected_ids | wc -l | tr -d ' ')"
            print_changed_apps "Added" "$@"
            abora_info "Total installed: $total"
            printf '\n'
            ;;
        remove)
            if [[ $# -eq 0 ]]; then
                abora_error "Usage: abora-apps remove <app-id...>"
                exit 1
            fi
            validate_ids "$@"
            ensure_layout
            abora_banner "App Manager" "Removing apps from your system."
            local removing_set=" $* "
            while IFS= read -r app_id; do
                [[ -n "$app_id" ]] || continue
                case "$removing_set" in
                    *" $app_id "*) ;;
                    *) keeping+=("$app_id") ;;
                esac
            done < <(read_selected_ids)
            if [[ "$dry_run" == "true" ]]; then
                show_dry_run "remove" "$no_rebuild" "$@"
                return 0
            fi
            write_selected_ids "${keeping[@]+"${keeping[@]}"}"
            render_apps_module
            if [[ "$no_rebuild" == "false" ]]; then
                rebuild_system
            fi
            total="$(read_selected_ids | wc -l | tr -d ' ')"
            print_changed_apps "Removed" "$@"
            abora_info "Total installed: $total"
            printf '\n'
            ;;
        bundle)
            if [[ -z "${1:-}" ]]; then
                usage
                exit 1
            fi
            validate_bundle "$1"
            ensure_layout
            abora_banner "App Manager" "Installing the '${1}' bundle."
            while IFS= read -r app_id; do
                [[ -n "$app_id" ]] || continue
                current+=("$app_id")
            done < <(read_selected_ids)
            while IFS= read -r app_id; do
                [[ -n "$app_id" ]] || continue
                bundle_ids+=("$app_id")
            done < <(abora_catalog_bundle_ids "$1")
            new_list=("${current[@]+"${current[@]}"}" "${bundle_ids[@]}")
            if [[ "$dry_run" == "true" ]]; then
                show_dry_run "add" "$no_rebuild" "${bundle_ids[@]}"
                return 0
            fi
            write_selected_ids "${new_list[@]}"
            render_apps_module
            if [[ "$no_rebuild" == "false" ]]; then
                rebuild_system
            fi
            total="$(read_selected_ids | wc -l | tr -d ' ')"
            abora_success "Done. The '${1}' bundle has been applied."
            abora_info "Total installed: $total"
            printf '\n'
            ;;
        "" | help | --help | -h)
            usage
            ;;
        *)
            abora_error "Unknown command: $command"
            printf '\n'
            usage
            exit 1
            ;;
    esac
}

main "$@"
