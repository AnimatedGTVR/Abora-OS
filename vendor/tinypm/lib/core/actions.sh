#!/usr/bin/env bash
# shellcheck disable=SC2154

install_pkg() {
    local package="$1"
    local provider

    provider="$(pick_install_provider "${2:-auto}")"

    case "$provider" in
        flatpak) install_flatpak "$package" ;;
        snap) snap_install "$package" ;;
        *)
            if is_native_provider "$provider"; then
                apt_install "$package" "$provider"
            else
                die "unknown provider: $provider"
            fi
            ;;
    esac

    record_tracked_package "$package" "$provider"
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

remove_pkg() {
    local package="$1"
    local provider

    if [[ "$(normalize_provider "${2:-auto}")" == "auto" ]] && provider="$(tracked_provider_for "$package" 2>/dev/null)"; then
        :
    else
        provider="$(pick_installed_provider "$package" "${2:-auto}")"
    fi

    case "$provider" in
        flatpak) flatpak_remove "$package" ;;
        snap) snap_remove "$package" ;;
        *)
            if is_native_provider "$provider"; then
                apt_remove "$package" "$provider"
            else
                die "unknown provider: $provider"
            fi
            ;;
    esac

    forget_tracked_package "$package"
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

    provider="$(normalize_provider "${1:-auto}")"

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

    if tracked_provider="$(tracked_provider_for "$package" 2>/dev/null)"; then
        tracked_added="$(tracked_timestamp_for "$package" 2>/dev/null || echo unknown)"
    else
        tracked_provider="untracked"
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
    echo "Package: $package"
    echo "Tracked by TinyPM: $tracked_provider"
    if [[ "$tracked_provider" != "untracked" ]]; then
        echo "Tracked since: $tracked_added"
    fi
    if [[ -n "$available_providers" ]]; then
        echo "Installed via:${available_providers}"
    else
        echo "Installed via: not detected"
    fi
}
