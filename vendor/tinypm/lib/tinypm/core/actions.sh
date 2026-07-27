#!/usr/bin/env bash
# shellcheck disable=SC2154

install_pkg() {
    local package="$1"
    local provider

    provider="$(pick_install_provider "${2:-auto}")"

    case "$provider" in
        flatpak) install_flatpak "$package" || return ;;
        snap) snap_install "$package" || return ;;
        *)
            if is_native_provider "$provider"; then
                if [[ "$provider" == "nix" ]] && anix_available; then
                    anix_install_pkg "$package" || return
                else
                    apt_install "$package" "$provider" || return
                fi
            else
                die "unknown provider: $provider"
            fi
            ;;
    esac

    record_tracked_package "$package" "$provider"
    record_history "install" "$package" "$provider"
}

package_installed_with() {
    local package="$1" provider="$2"

    case "$provider" in
        flatpak) backend_has_cmd flatpak && package_in_flatpak "$package" ;;
        snap) backend_has_cmd snap && package_in_snap "$package" ;;
        *)
            is_native_provider "$provider" || return 1
            native_pm_available "$provider" && package_in_apt "$package" "$provider"
            ;;
    esac
}

search_pkg() {
    local query="$1"
    local provider native_pm printed=0

    provider="$(normalize_provider "${2:-auto}")"

    case "$provider" in
        flatpak)
            ensure_provider_available flatpak
            flatpak_search "$query"
            ;;
        snap)
            ensure_provider_available snap
            snap_search "$query"
            ;;
        auto)
            ensure_provider_available auto
            native_pm="$(detect_native_pm 2>/dev/null || true)"
            if [[ -n "$native_pm" ]]; then
                echo "== $(native_pm_label "$native_pm") =="
                apt_search "$query" "$native_pm"
                printed=1
            fi
            if backend_has_cmd flatpak; then
                [[ "$printed" -eq 1 ]] && echo
                echo "== Flatpak =="
                flatpak_search "$query"
                printed=1
            fi
            if backend_has_cmd snap; then
                [[ "$printed" -eq 1 ]] && echo
                echo "== Snap =="
                snap_search "$query"
                printed=1
            fi
            ;;
        *)
            if is_native_provider "$provider"; then
                ensure_provider_available "$provider"
                apt_search "$query" "$provider"
            else
                die "unknown provider: $provider"
            fi
            ;;
    esac
}

remove_provider_for() {
    local package="$1" provider
    if [[ "$(normalize_provider "${2:-auto}")" == "auto" ]] && provider="$(tracked_provider_for "$package" 2>/dev/null)"; then
        :
    else
        provider="$(pick_installed_provider "$package" "${2:-auto}")"
    fi
    printf '%s\n' "$provider"
}

remove_pkg() {
    local package="$1"
    local provider

    provider="$(remove_provider_for "$package" "${2:-auto}")"

    case "$provider" in
        flatpak) flatpak_remove "$package" || return ;;
        snap) snap_remove "$package" || return ;;
        *)
            if is_native_provider "$provider"; then
                if [[ "$provider" == "nix" ]] && anix_available; then
                    anix_remove_pkg "$package" || return
                else
                    apt_remove "$package" "$provider" || return
                fi
            else
                die "unknown provider: $provider"
            fi
            ;;
    esac

    forget_tracked_package "$package"
    record_history "remove" "$package" "$provider"
}

list_pkgs() {
    local provider native_pm printed=0

    provider="$(normalize_provider "${1:-auto}")"

    case "$provider" in
        flatpak)
            ensure_provider_available flatpak
            flatpak_list
            ;;
        snap)
            ensure_provider_available snap
            snap_list
            ;;
        auto)
            ensure_provider_available auto
            native_pm="$(detect_native_pm 2>/dev/null || true)"
            if [[ -n "$native_pm" ]]; then
                echo "== $(native_pm_label "$native_pm") =="
                apt_list "$native_pm"
                printed=1
            fi
            if backend_has_cmd flatpak; then
                [[ "$printed" -eq 1 ]] && echo
                echo "== Flatpak =="
                flatpak_list
                printed=1
            fi
            if backend_has_cmd snap; then
                [[ "$printed" -eq 1 ]] && echo
                echo "== Snap =="
                snap_list
                printed=1
            fi
            ;;
        *)
            if is_native_provider "$provider"; then
                ensure_provider_available "$provider"
                apt_list "$provider"
            else
                die "unknown provider: $provider"
            fi
            ;;
    esac
}

run_pkg() {
    local package="$1"
    local provider

    if [[ "$(normalize_provider "${2:-auto}")" == "auto" ]] && provider="$(tracked_provider_for "$package" 2>/dev/null)"; then
        :
    else
        provider="$(pick_runner_provider "$package" "${2:-auto}")"
    fi

    case "$provider" in
        flatpak) flatpak_run "$package" ;;
        snap) snap_run "$package" ;;
    esac
}

update_pkgs() {
    local provider native_pm
    local pinned_list=()

    provider="$(normalize_provider "${1:-auto}")"

    mapfile -t pinned_list < <(list_pinned_packages 2>/dev/null || true)

    if [[ "${#pinned_list[@]}" -gt 0 ]]; then
        printf 'Pinned packages (skipped): %s\n' "${pinned_list[*]}"
    fi

    case "$provider" in
        flatpak)
            ensure_provider_available flatpak
            flatpak_update
            ;;
        snap)
            ensure_provider_available snap
            snap_update
            ;;
        auto)
            ensure_provider_available auto
            native_pm="$(detect_native_pm 2>/dev/null || true)"
            if [[ -n "$native_pm" ]]; then
                apt_update "$native_pm"
            fi
            if backend_has_cmd flatpak; then
                flatpak_update
            fi
            if backend_has_cmd snap; then
                snap_update
            fi
            ;;
        *)
            if is_native_provider "$provider"; then
                ensure_provider_available "$provider"
                apt_update "$provider"
            else
                die "unknown provider: $provider"
            fi
            ;;
    esac

    record_history "update" "all" "${provider:-auto}"
}

add_repo() {
    local spec="$1"
    local name="${2:-}"
    local requested="${3:-auto}"
    local pm

    [[ -n "$spec" ]] || die "add-repo requires a repository spec"

    if [[ "$(normalize_provider "$requested")" == "auto" || "$requested" == "native" ]]; then
        pm="$(detect_native_pm)" || die "no supported native package manager was detected"
    elif is_native_provider "$requested"; then
        pm="$(native_pm_resolve "$requested")"
    else
        die "add-repo is only supported for native package managers (got: $requested)"
    fi

    ensure_provider_available "$pm"
    repo_add "$spec" "$name" "$pm"
    record_history "add-repo" "$spec" "$pm"
}

managed_pkgs() {
    print_tracked_packages
}

info_pkg() {
    local package="$1"
    local tracked_provider="untracked"
    local tracked_added="unknown"
    local available_providers=""
    local native_pm=""
    local pinned_status="no"

    if tracked_provider="$(tracked_provider_for "$package" 2>/dev/null)"; then
        tracked_added="$(tracked_timestamp_for "$package" 2>/dev/null || echo unknown)"
    else
        tracked_provider="untracked"
    fi

    if is_pinned "$package" 2>/dev/null; then
        pinned_status="yes"
    fi

    if backend_has_cmd flatpak && package_in_flatpak "$package"; then
        available_providers="${available_providers} flatpak"
    fi
    if backend_has_cmd snap && package_in_snap "$package"; then
        available_providers="${available_providers} snap"
    fi
    native_pm="$(detect_native_pm 2>/dev/null || true)"
    if [[ -n "$native_pm" ]] && package_in_apt "$package" "$native_pm"; then
        available_providers="${available_providers} $native_pm"
    fi

    printf 'Package:       %s\n' "$package"
    printf 'Tracked:       %s\n' "$tracked_provider"
    if [[ "$tracked_provider" != "untracked" ]]; then
        printf 'Tracked since: %s\n' "$tracked_added"
    fi
    printf 'Pinned:        %s\n' "$pinned_status"
    if [[ -n "$available_providers" ]]; then
        printf 'Installed via:%s\n' "$available_providers"
    else
        printf 'Installed via: not detected\n'
    fi

    # Catalog lookup by package ID or display name
    local hits=0
    while IFS=$'\t' read -r name cat src pkg desc; do
        if [[ "${pkg,,}" == "${package,,}" || "${name,,}" == "${package,,}" ]]; then
            if [[ "$hits" -eq 0 ]]; then
                printf '\nCatalog:\n'
            fi
            printf '  %-22s %-12s %-8s  %s\n' "$name" "$cat" "$src" "$desc"
            hits=$((hits + 1))
        fi
    done < "$(tinypm_catalog_file)"
}

# Pin management

pin_pkg() {
    local package="$1"
    local provider_hint="${2:-auto}"
    local resolved_provider

    resolved_provider="$(tracked_provider_for "$package" 2>/dev/null || echo "${provider_hint}")"
    pin_package "$package" "$resolved_provider"
    record_history "pin" "$package" "$resolved_provider"
    printf 'Pinned %s (%s) — will be skipped during updates.\n' "$package" "$resolved_provider"
}

unpin_pkg() {
    local package="$1"

    unpin_package "$package"
    record_history "unpin" "$package" "n/a"
    printf 'Unpinned %s — will be included in future updates.\n' "$package"
}

pinned_pkgs() {
    print_pinned_packages
}

# History

show_history() {
    local limit="${1:-50}"
    print_history "$limit"
}

undo_last_transaction() {
    local confirmed="${1:-0}"
    local entry timestamp previous_action package previous_provider reverse_action

    entry="$(last_reversible_history_entry 2>/dev/null || true)"
    [[ -n "$entry" ]] || die "no install or removal is available to undo"
    IFS=$'\t' read -r timestamp previous_action package previous_provider <<<"$entry"

    case "$previous_action" in
        install) reverse_action="remove" ;;
        remove) reverse_action="install" ;;
        *) die "history entry cannot be undone: $previous_action" ;;
    esac

    ui_heading "Undo preview"
    printf '  %-13s %s\n' 'Recorded' "$timestamp"
    printf '  %-13s %s\n' 'Previous' "$previous_action $package"
    printf '  %-13s %s\n' 'Provider' "$(native_pm_label "$previous_provider")"
    printf '  %-13s %s\n' 'Will perform' "$reverse_action $package"

    if [[ "$confirmed" -ne 1 ]]; then
        printf '\nNo changes made. Run: grab undo --yes\n'
        return
    fi

    printf '\n'
    case "$reverse_action" in
        remove) remove_pkg "$package" "$previous_provider" ;;
        install) install_pkg "$package" "$previous_provider" ;;
    esac
    ui_success "Undid $previous_action of $package"
}

# Bundle — install a full catalog category

bundle_list() {
    printf '%-20s %s\n' "CATEGORY" "PACKAGES"
    catalog_entries | awk -F '\t' \
        '{count[$2]++} END { for (cat in count) printf "%-20s %d\n", cat, count[cat] }' \
        | sort
}

bundle_install() {
    local category="$1"
    local provider_pref="${2:-auto}"
    local found=0
    local name cat_col source pkg desc

    while IFS=$'\t' read -r name cat_col source pkg desc; do
        [[ "${cat_col,,}" == "${category,,}" ]] || continue
        found=$((found + 1))

        case "$provider_pref" in
            flatpak) [[ "$source" == "flatpak" ]] || continue ;;
            snap)    [[ "$source" == "snap" ]] || continue ;;
            auto)    ;;
            native|apt|dnf|pacman|xbps|zypper|apk|emerge|eopkg|swupd|slackpkg|opkg|urpmi|guix|brew|nix)
                [[ "$source" != "flatpak" && "$source" != "snap" ]] || continue
                ;;
        esac

        printf '\nInstalling %s (%s)...\n' "$name" "$pkg"
        install_pkg "$pkg" "${source:-${provider_pref:-auto}}" \
            || printf 'Warning: failed to install %s, continuing.\n' "$pkg"
    done < <(catalog_entries)

    if [[ "$found" -eq 0 ]]; then
        printf 'No packages found in category: %s\n' "$category"
        printf 'Available categories:\n'
        catalog_entries | awk -F '\t' '{print $2}' | sort -u | awk '{print "  " $0}'
        return 1
    fi
}

# Sync — install from a package manifest file

sync_install_manifest() {
    local manifest_file="${1:-}"
    local installed=0 failed=0
    local line provider pkg

    [[ -n "$manifest_file" ]] || die "sync requires a manifest file path (or use --generate)"
    [[ -f "$manifest_file" ]] || die "manifest file not found: $manifest_file"

    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line//[[:space:]]/}"
        [[ -n "$line" ]] || continue

        if [[ "$line" == *:* ]]; then
            provider="${line%%:*}"
            pkg="${line#*:}"
        else
            provider="auto"
            pkg="$line"
        fi

        printf 'Syncing %s (%s)...\n' "$pkg" "$provider"
        if install_pkg "$pkg" "$provider"; then
            installed=$((installed + 1))
        else
            printf 'Warning: failed to install %s\n' "$pkg"
            failed=$((failed + 1))
        fi
    done < "$manifest_file"

    printf '\nSync complete: %d installed, %d failed\n' "$installed" "$failed"
}

sync_generate_manifest() {
    local output_file="${1:-tinypm-packages.txt}"

    if ! state_db_exists; then
        printf 'No tracked packages to export.\n'
        return
    fi

    {
        printf '# TinyPM V4 package manifest\n'
        printf '# Generated: %s\n' "$(date -Iseconds)"
        printf '# Format: provider:package\n'
        printf '\n'
        awk -F '\t' '{ print $2 ":" $1 }' "$state_db"
    } >"$output_file"

    local count
    count="$(awk 'END{print NR+0}' "$state_db")"
    printf 'Wrote manifest to %s (%d packages)\n' "$output_file" "$count"
}
