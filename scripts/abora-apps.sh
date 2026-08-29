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
    ABORA_FAINT=$'\033[38;5;237m'
    ABORA_GREEN=$'\033[38;5;77m'
    ABORA_RED=$'\033[38;5;203m'
    ABORA_YELLOW=$'\033[38;5;222m'
    abora_banner()   { printf '\n  %b%s%b  %b%s%b\n\n' "$ABORA_WHITE" "${1:-}" "$ABORA_NC" "$ABORA_DIM" "${2:-}" "$ABORA_NC"; }
    abora_info()     { printf '  %b·%b  %s\n' "$ABORA_CYAN" "$ABORA_NC" "$1"; }
    abora_success()  { printf '  \033[38;5;77m✓\033[0m  \033[38;5;77m%s\033[0m\n' "$1"; }
    abora_warn()     { printf '  \033[38;5;222m!\033[0m  \033[38;5;222m%s\033[0m\n' "$1"; }
    abora_error()    { printf '  \033[38;5;203m✗\033[0m  \033[38;5;203m%s\033[0m\n' "$1" >&2; }
    abora_step()     { printf '  \033[38;5;44m▸\033[0m  %s\n' "$1"; }
    abora_dim_line() { printf '  \033[38;5;242m%s\033[0m\n' "$1"; }
    abora_rule()     { printf '  %b%s%b\n' "$ABORA_DIM" "────────────────────────────────────────" "$ABORA_NC"; }
    abora_cols()     { printf '80\n'; }
    abora_trunc()    { printf '%s' "$1"; }
fi

# Unlike abora-ui.sh (cosmetics only), the app catalog is real data this
# script cannot function without -- there's no meaningful "fallback"
# catalog to fabricate. But a raw "No such file or directory" from a bare
# `source` is still a worse failure mode than a clear, actionable error,
# so fail loudly through the UI layer (now guaranteed available above)
# instead of crashing with an unhandled bash error.
if [[ ! -f "$catalog_lib" ]]; then
    abora_error "App catalog not found: ${catalog_lib}"
    abora_dim_line "Expected it at \$ABORA_APP_CATALOG_LIB, ${script_dir}/abora-app-catalog.sh, or /etc/abora/app-catalog.sh."
    exit 1
fi
# shellcheck source=/dev/null
source "$catalog_lib"

config_dir="${ABORA_SYSTEM_CONFIG:-/etc/nixos}"
abora_dir="${config_dir}/abora"
apps_list="${abora_dir}/apps.list"
apps_module="${abora_dir}/apps.nix"
flake_target="${ABORA_FLAKE_CONFIG_NAME:-abora}"
default_repo_ref="${ABORA_REPO_REF:-edge}"

usage() {
    abora_banner "App Manager" "Install and remove apps on your Abora system."
    printf '  %bUsage%b\n\n' "$ABORA_WHITE" "$ABORA_NC"
    printf '  %babora apps catalog%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Browse all available apps by category."
    printf '\n'
    printf '  %babora apps search <term>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Search apps by name, ID, or description."
    printf '\n'
    printf '  %babora apps info <app-id>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show details about a specific app."
    printf '\n'
    printf '  %babora apps installed%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  List apps currently installed on this system."
    printf '\n'
    printf '  %babora apps add <app-id...> [--no-rebuild] [--dry-run]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Add one or more apps (rebuilds unless --no-rebuild is given)."
    printf '\n'
    printf '  %babora apps remove <app-id...> [--no-rebuild] [--dry-run]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Remove one or more apps (rebuilds unless --no-rebuild is given)."
    printf '\n'
    printf '  %babora apps set [app-id...] [--no-rebuild] [--dry-run]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Replace the full app list."
    printf '\n'
    printf '  %babora apps bundle <name> [--no-rebuild] [--dry-run]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Add a curated bundle: favorites essentials social creator developer gaming system"
    printf '\n'
    printf '  %babora apps rebuild%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Apply the current app list (nixos-rebuild switch)."
    printf '\n'
    printf '  %babora apps custom <list|info|update>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Update standalone packages such as Modularity Stable."
    printf '\n'
}

is_installed_system() {
    [[ -d "$abora_dir" && -f "$config_dir/flake.nix" ]]
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

stage_config_for_flake() {
    if command -v git >/dev/null 2>&1 \
        && [[ -d "$config_dir" ]] \
        && run_as_root git -C "$config_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        run_as_root git -C "$config_dir" add -A >/dev/null 2>&1 || true
    fi
}

explain_nix_failure() {
    local log_file="$1"

    [[ -f "$log_file" ]] || return 0

    if grep -Eqi 'fetcher-cache.*sqlite|sqlite.*disk I/O|disk I/O error' "$log_file"; then
        printf '\n'
        abora_warn "Nix reported a local fetch-cache disk I/O error."
        abora_dim_line "This is usually a damaged user Nix cache or a full/busy disk, not a bad app entry."
        abora_dim_line "Try: abora gaming repair-cache"
        abora_dim_line "Manual fallback: rm -f ~/.cache/nix/fetcher-cache-v*.sqlite*"
        abora_dim_line "Then check free space with: df -h"
        printf '\n'
    elif grep -Eqi 'no space left on device|ENOSPC' "$log_file"; then
        printf '\n'
        abora_warn "The rebuild appears to have run out of disk space."
        abora_dim_line "Free space or run garbage collection, then retry: sudo nix-collect-garbage -d"
        printf '\n'
    fi
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

backup_app_state() {
    local backup_dir="$1"

    mkdir -p "$backup_dir"
    if [[ -f "$apps_list" ]]; then
        cp "$apps_list" "$backup_dir/apps.list"
    else
        : > "$backup_dir/apps.list.missing"
    fi
    if [[ -f "$apps_module" ]]; then
        cp "$apps_module" "$backup_dir/apps.nix"
    else
        : > "$backup_dir/apps.nix.missing"
    fi
}

restore_app_state() {
    local backup_dir="$1"

    if [[ -f "$backup_dir/apps.list" ]]; then
        run_as_root cp "$backup_dir/apps.list" "$apps_list"
    else
        run_as_root rm -f "$apps_list"
    fi
    if [[ -f "$backup_dir/apps.nix" ]]; then
        run_as_root cp "$backup_dir/apps.nix" "$apps_module"
    else
        run_as_root rm -f "$apps_module"
    fi
}

rebuild_or_restore_app_state() {
    local backup_dir="$1"

    if rebuild_system; then
        rm -rf "$backup_dir"
        return 0
    fi

    restore_app_state "$backup_dir"
    rm -rf "$backup_dir"
    abora_warn "Restored the previous app selection because the rebuild failed."
    return 1
}

# app_expr is never user-supplied text -- it's whatever abora_catalog_expr()
# returns for a validated app_id (see validate_ids below, which checks every
# id against the catalog before it's ever written to apps_list), so writing
# it straight into this Nix list is safe: the only text that ends up here is
# text this repo's own app catalog already ships.
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
            # validate_ids only guarantees an id was in the catalog at the
            # moment it was added -- the catalog itself can drop or rename
            # an app across releases, and this silently dropped it from
            # the rebuilt apps.nix ever after with no indication anywhere.
            # `abora apps installed` still lists it (it reads apps.list
            # directly, not apps.nix), so a user could see an app as
            # "installed" while it was never actually part of
            # environment.systemPackages on the last several rebuilds.
            # Warn instead of silently continuing.
            if ! app_expr="$(abora_catalog_expr "$app_id")"; then
                # abora_warn prints to stdout, and this whole loop's stdout
                # is redirected into $tmp (the Nix file being generated) --
                # redirect the warning to stderr explicitly, or it corrupts
                # apps.nix with this warning text instead of just dropping
                # the app cleanly.
                abora_warn "Skipping '${app_id}': no longer in the app catalog. Remove it with: abora apps remove ${app_id}" >&2
                continue
            fi
            printf '    %s\n' "$app_expr"
        done < <(read_selected_ids)
        printf '  ];\n'
        printf '}\n'
    } > "$tmp"
    run_as_root mv "$tmp" "$apps_module"
}

rebuild_system() {
    local log_file status

    abora_step "Rebuilding Abora with the updated app selection"
    printf '\n'
    stage_config_for_flake
    log_file="$(mktemp)"
    set +e
    run_as_root nixos-rebuild switch --flake "${config_dir}#${flake_target}" 2>&1 | tee "$log_file"
    status="${PIPESTATUS[0]}"
    set -e
    if [[ "$status" -ne 0 ]]; then
        explain_nix_failure "$log_file"
        rm -f "$log_file"
        return "$status"
    fi
    rm -f "$log_file"
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

selected_has_id() {
    local wanted="$1" app_id
    while IFS= read -r app_id; do
        [[ "$app_id" == "$wanted" ]] && return 0
    done < <(read_selected_ids)
    return 1
}

validate_remove_ids() {
    local app_id
    for app_id in "$@"; do
        if abora_catalog_has_app "$app_id" || selected_has_id "$app_id"; then
            continue
        fi
        abora_error "Unknown app id: $app_id"
        exit 1
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

    abora_banner "App Catalog" "${total} apps available — run 'abora apps add <id>' to install."

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
        abora_dim_line "Run 'abora apps catalog' to browse what's available."
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

    if [[ "$command" == "custom" ]]; then
        if command -v abora-custom-packages >/dev/null 2>&1; then
            exec abora-custom-packages "$@"
        fi
        exec "$script_dir/abora-custom-packages.sh" "$@"
    fi

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

    local app_id total state_backup
    local -a current=() new_list=() bundle_ids=() keeping=()

    case "$command" in
        catalog)
            show_catalog
            ;;
        search)
            if [[ -z "${1:-}" ]]; then
                abora_error "Usage: abora apps search <term>"
                exit 1
            fi
            abora_banner "App Search" "Results for '${1}'."
            search_apps "$1"
            ;;
        info)
            if [[ -z "${1:-}" ]]; then
                abora_error "Usage: abora apps info <app-id>"
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
            if [[ "$dry_run" == "true" ]]; then
                show_dry_run "set" "$no_rebuild" "$@"
                return 0
            fi
            ensure_layout
            abora_banner "App Manager" "Replacing app selection."
            state_backup=""
            [[ "$no_rebuild" == "false" ]] && state_backup="$(mktemp -d)" && backup_app_state "$state_backup"
            write_selected_ids "$@"
            render_apps_module
            if [[ "$no_rebuild" == "false" ]]; then
                rebuild_or_restore_app_state "$state_backup"
            fi
            total="$(read_selected_ids | wc -l | tr -d ' ')"
            abora_success "Done. App selection replaced."
            abora_info "Total installed: $total"
            printf '\n'
            ;;
        add)
            if [[ $# -eq 0 ]]; then
                abora_error "Usage: abora apps add <app-id...>"
                exit 1
            fi
            validate_ids "$@"
            if [[ "$dry_run" == "true" ]]; then
                show_dry_run "add" "$no_rebuild" "$@"
                return 0
            fi
            ensure_layout
            abora_banner "App Manager" "Adding apps to your system."
            state_backup=""
            [[ "$no_rebuild" == "false" ]] && state_backup="$(mktemp -d)" && backup_app_state "$state_backup"
            while IFS= read -r app_id; do
                [[ -n "$app_id" ]] || continue
                current+=("$app_id")
            done < <(read_selected_ids)
            new_list=("${current[@]+"${current[@]}"}" "$@")
            write_selected_ids "${new_list[@]}"
            render_apps_module
            if [[ "$no_rebuild" == "false" ]]; then
                rebuild_or_restore_app_state "$state_backup"
            fi
            total="$(read_selected_ids | wc -l | tr -d ' ')"
            print_changed_apps "Added" "$@"
            abora_info "Total installed: $total"
            printf '\n'
            ;;
        remove)
            if [[ $# -eq 0 ]]; then
                abora_error "Usage: abora apps remove <app-id...>"
                exit 1
            fi
            validate_remove_ids "$@"
            if [[ "$dry_run" == "true" ]]; then
                show_dry_run "remove" "$no_rebuild" "$@"
                return 0
            fi
            ensure_layout
            abora_banner "App Manager" "Removing apps from your system."
            state_backup=""
            [[ "$no_rebuild" == "false" ]] && state_backup="$(mktemp -d)" && backup_app_state "$state_backup"
            local removing_set=" $* "
            while IFS= read -r app_id; do
                [[ -n "$app_id" ]] || continue
                case "$removing_set" in
                    *" $app_id "*) ;;
                    *) keeping+=("$app_id") ;;
                esac
            done < <(read_selected_ids)
            write_selected_ids "${keeping[@]+"${keeping[@]}"}"
            render_apps_module
            if [[ "$no_rebuild" == "false" ]]; then
                rebuild_or_restore_app_state "$state_backup"
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
            while IFS= read -r app_id; do
                [[ -n "$app_id" ]] || continue
                bundle_ids+=("$app_id")
            done < <(abora_catalog_bundle_ids "$1")
            if [[ "$dry_run" == "true" ]]; then
                show_dry_run "add" "$no_rebuild" "${bundle_ids[@]}"
                return 0
            fi
            ensure_layout
            abora_banner "App Manager" "Installing the '${1}' bundle."
            state_backup=""
            [[ "$no_rebuild" == "false" ]] && state_backup="$(mktemp -d)" && backup_app_state "$state_backup"
            while IFS= read -r app_id; do
                [[ -n "$app_id" ]] || continue
                current+=("$app_id")
            done < <(read_selected_ids)
            new_list=("${current[@]+"${current[@]}"}" "${bundle_ids[@]}")
            write_selected_ids "${new_list[@]}"
            render_apps_module
            if [[ "$no_rebuild" == "false" ]]; then
                rebuild_or_restore_app_state "$state_backup"
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
