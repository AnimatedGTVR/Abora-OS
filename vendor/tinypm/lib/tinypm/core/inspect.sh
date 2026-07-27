#!/usr/bin/env bash
# shellcheck disable=SC2154

# Read-only package inspection and install planning. These are normal TinyPM
# features; they do not need a second "engine" executable or identity.

package_check() {
    local package="${1:-}"
    local native_pm="" native_status flatpak_status snap_status
    local catalog_hits=0

    [[ -n "$package" ]] || die "check requires a package name"
    native_pm="$(detect_native_pm 2>/dev/null || true)"

    ui_heading "Package check: $package"
    printf '  %-14s  %s\n' "BACKEND" "STATUS"
    printf '  %-14s  %s\n' "---------" "------"

    if [[ -n "$native_pm" ]]; then
        native_status="not installed (backend available)"
        package_in_apt "$package" "$native_pm" 2>/dev/null && native_status="installed"
        printf '  %-14s  %s\n' "$native_pm" "$native_status"
    else
        printf '  %-14s  no native package manager detected\n' "native"
    fi

    if backend_has_cmd flatpak; then
        flatpak_status="not installed (backend available)"
        package_in_flatpak "$package" 2>/dev/null && flatpak_status="installed"
        printf '  %-14s  %s\n' "flatpak" "$flatpak_status"
    else
        printf '  %-14s  backend not available\n' "flatpak"
    fi

    if backend_has_cmd snap; then
        snap_status="not installed (backend available)"
        package_in_snap "$package" 2>/dev/null && snap_status="installed"
        printf '  %-14s  %s\n' "snap" "$snap_status"
    else
        printf '  %-14s  backend not available\n' "snap"
    fi

    while IFS=$'\t' read -r name category source pkg _description; do
        if [[ "${pkg,,}" == "${package,,}" || "${name,,}" == "${package,,}" ]]; then
            [[ "$catalog_hits" -gt 0 ]] || printf '\n  Catalog matches:\n'
            printf '    %-22s %-12s %-8s %s\n' "$name" "$category" "$source" "$pkg"
            catalog_hits=$((catalog_hits + 1))
        fi
    done < "$(tinypm_catalog_file)"

    if [[ "$catalog_hits" -eq 0 ]]; then
        printf '\n  Not found in the curated catalog. Try: tinypm search %s\n' "$package"
    fi
}

install_plan() {
    local requested="${1:-auto}"
    shift
    local packages=("$@")
    local native_pm="" resolved_provider label flag=""
    local index=0 package

    [[ "${#packages[@]}" -gt 0 ]] || die "dry-run requires at least one package name"
    native_pm="$(detect_native_pm 2>/dev/null || true)"

    case "$requested" in
        flatpak) resolved_provider="flatpak"; label="Flatpak"; flag=" -f" ;;
        snap) resolved_provider="snap"; label="Snap"; flag=" -s" ;;
        native)
            [[ -n "$native_pm" ]] || die "no native package manager was detected"
            resolved_provider="$native_pm"; label="$(native_pm_label "$native_pm") (native)"; flag=" -n"
            ;;
        apt|dnf|pacman|xbps|zypper|apk|emerge|eopkg|swupd|slackpkg|opkg|urpmi|guix|brew|nix)
            resolved_provider="$requested"; label="$(native_pm_label "$requested") (native)"; flag=" --$requested"
            ;;
        auto)
            if [[ -n "$native_pm" ]]; then
                resolved_provider="$native_pm"; label="$(native_pm_label "$native_pm") (native, automatic)"
            elif backend_has_cmd flatpak; then
                resolved_provider="flatpak"; label="Flatpak (automatic)"
            elif backend_has_cmd snap; then
                resolved_provider="snap"; label="Snap (automatic)"
            else
                die "no package provider is available"
            fi
            ;;
        *) die "unknown provider: $requested" ;;
    esac

    ui_heading "Install plan (no changes will be made)"
    printf '  Provider: %s\n' "$label"
    printf '  Packages: %d\n\n' "${#packages[@]}"
    for package in "${packages[@]}"; do
        index=$((index + 1))
        printf '  [%d] %s\n' "$index" "$package"
    done
    printf '\n  To execute: grab%s %s\n' "$flag" "${packages[*]}"

    # Keep this referenced so shellcheck and future output changes can use the
    # exact resolved provider without reimplementing resolution.
    : "$resolved_provider"
}

package_explain() {
    local package="${1:-}" requested="${2:-auto}"
    local provider native_pm resolved reason command description="" availability="available"
    local auto_note=""

    [[ -n "$package" ]] || die "explain requires a package name"
    provider="$(normalize_provider "$requested")"

    case "$provider" in
        auto)
            native_pm="$(detect_native_pm 2>/dev/null || true)"
            if [[ -n "$native_pm" ]]; then
                provider="$native_pm"
                if backend_has_cmd flatpak || backend_has_cmd snap; then
                    auto_note="Native is the non-interactive default; an interactive install may offer other available sources"
                else
                    auto_note="Selected automatically as the available native manager"
                fi
            elif backend_has_cmd flatpak; then
                provider="flatpak"
                auto_note="Selected automatically because no native manager was detected"
            elif backend_has_cmd snap; then
                provider="snap"
                auto_note="Selected automatically because no native manager or Flatpak was detected"
            else
                die "no package provider is available"
            fi
            ;;
        native)
            provider="$(detect_native_pm 2>/dev/null || true)"
            [[ -n "$provider" ]] || die "no native package manager was detected"
            ;;
    esac

    case "$provider" in
        flatpak)
            resolved="$package"
            reason="Flatpak application IDs are passed through unchanged"
            printf -v command 'flatpak install -y %q' "$resolved"
            backend_has_cmd flatpak || availability="not installed"
            if backend_has_cmd flatpak; then
                description="$(backend_run flatpak search --columns=description "$resolved" 2>/dev/null | awk 'NF { print; exit }' || true)"
            fi
            ;;
        snap)
            resolved="$package"
            reason="Snap package names are passed through unchanged"
            printf -v command 'snap install %q' "$resolved"
            backend_has_cmd snap || availability="not installed"
            if backend_has_cmd snap; then
                description="$(backend_run snap info "$resolved" 2>/dev/null | awk '/^summary:/ { sub(/^summary:[[:space:]]*/, ""); print; exit }' || true)"
            fi
            ;;
        *)
            is_native_provider "$provider" || die "unknown provider: $provider"
            resolved="$(native_alias_package "$package" "$provider")"
            reason="$(native_alias_reason "$package" "$provider")"
            command="$(native_install_preview "$resolved" "$provider")"
            native_pm_available "$provider" || availability="not installed"
            if [[ "$availability" == "available" ]]; then
                description="$(native_package_description "$resolved" "$provider" || true)"
            fi
            ;;
    esac

    if [[ -z "$description" ]]; then
        while IFS=$'\t' read -r name _category _source catalog_package catalog_description; do
            if [[ "${catalog_package,,}" == "${resolved,,}" || "${catalog_package,,}" == "${package,,}" || "${name,,}" == "${package,,}" ]]; then
                description="$catalog_description"
                break
            fi
        done < "$(tinypm_catalog_file)"
    fi
    [[ -n "$description" ]] || description="No description is available from the selected provider"

    ui_heading "Package resolution"
    printf '  %s%-13s%s %s\n' "$c_cyan" 'Requested' "$c_reset" "$package"
    printf '  %s%-13s%s %s\n' "$c_cyan" 'Resolved' "$c_reset" "$resolved"
    printf '  %s%-13s%s %s\n' "$c_cyan" 'Provider' "$c_reset" "$(native_pm_label "$provider")"
    printf '  %s%-13s%s %s\n' "$c_cyan" 'Availability' "$c_reset" "$availability"
    printf '  %s%-13s%s %s\n' "$c_cyan" 'Description' "$c_reset" "$description"
    printf '  %s%-13s%s %s\n' "$c_cyan" 'Reason' "$c_reset" "$reason"
    printf '  %s%-13s%s %s\n' "$c_cyan" 'Command' "$c_reset" "$command"
    [[ -z "$auto_note" ]] || printf '  %s%-13s%s %s\n' "$c_cyan" 'Selection' "$c_reset" "$auto_note"
}
