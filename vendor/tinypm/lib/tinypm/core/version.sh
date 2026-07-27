#!/usr/bin/env bash
# shellcheck disable=SC2154

print_version_report() {
    local native_pm="none" native_status="missing"
    local flatpak_status="missing" snap_status="missing"
    local os_name kernel_name arch_name flavor_key

    native_pm="$(detect_native_pm 2>/dev/null || echo none)"
    [[ "$native_pm" == "none" ]] || native_status="$(native_pm_label "$native_pm")"
    backend_has_cmd flatpak && flatpak_status="available"
    backend_has_cmd snap && snap_status="available"

    os_name="$(backend_os_name)"
    kernel_name="$(backend_run uname -r 2>/dev/null || echo unknown)"
    arch_name="$(backend_run uname -m 2>/dev/null || echo unknown)"
    flavor_key="$(tinypm_active_flavor)"

    if [[ -r "$(tinypm_logo_file)" && -t 1 ]]; then
        printf '%s' "$c_cyan"
        cat "$(tinypm_logo_file)"
        printf '%s\n' "$c_reset"
    fi

    ui_heading "$(tinypm_version_label)"
    [[ -n "$tinypm_tagline" ]] && printf '%s%s%s\n' "$c_dim" "$tinypm_tagline" "$c_reset"
    printf '%s\n' '----------------------------------------'
    printf '  %s%-12s%s %s\n' "$c_cyan" 'OS' "$c_reset" "$os_name"
    printf '  %s%-12s%s %s (%s)\n' "$c_cyan" 'Kernel' "$c_reset" "$kernel_name" "$arch_name"
    printf '  %s%-12s%s %s\n' "$c_cyan" 'Native' "$c_reset" "$native_status"
    printf '  %s%-12s%s flatpak=%s snap=%s\n' "$c_cyan" 'Optional' "$c_reset" "$flatpak_status" "$snap_status"
    printf '  %s%-12s%s %s\n' "$c_cyan" 'Flavor' "$c_reset" "$flavor_key"
    printf '  %s%-12s%s %s\n' "$c_cyan" 'Tracked' "$c_reset" "$(tracked_package_count 2>/dev/null || echo 0)"
    printf '  %s%-12s%s %s\n' "$c_cyan" 'Catalog' "$c_reset" "$(catalog_count 2>/dev/null || echo 0)"
}

tinypm_update_source_url() {
    printf '%s\n' "${TINYPM_UPDATE_INFO_URL:-https://raw.githubusercontent.com/AnimatedGTVR/TinyPM/main/src/lib/tinypm/core/common.sh}"
}

tinypm_update_archive_url() {
    printf '%s\n' "${TINYPM_UPDATE_ARCHIVE_URL:-https://github.com/AnimatedGTVR/TinyPM/archive/refs/heads/main.tar.gz}"
}

tinypm_fetch_url() {
    local url="$1"
    if backend_has_cmd curl; then
        backend_run curl -fsSL "$url"
    elif backend_has_cmd wget; then
        backend_run wget -qO- "$url"
    else
        die "curl or wget is required to check TinyPM updates"
    fi
}

tinypm_latest_version() {
    tinypm_fetch_url "$(tinypm_update_source_url)" \
        | awk -F '=' '
            ($1 == "version" || $1 == "tinypm_version") && !found {
                value=$2
                gsub(/["[:space:]]/, "", value)
                print value
                found=1
            }
            END { exit(found ? 0 : 1) }
        '
}

tinypm_version_lt() {
    local a="$1" b="$2" first
    [[ "$a" == "$b" ]] && return 1
    first="$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n1)"
    [[ "$first" == "$a" ]]
}

tinypm_notify_update() {
    local latest="$1"
    if backend_has_cmd notify-send && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
        backend_run notify-send \
            --app-name="TinyPM" \
            "TinyPM update available" \
            "TinyPM v${latest} is available. Run: tinypm self-update"
    fi
}

check_tinypm_update() {
    local latest

    latest="$(tinypm_latest_version)" || die "could not read TinyPM update metadata"

    if tinypm_version_lt "$tinypm_version" "$latest"; then
        [[ "${update_notify:-0}" -eq 1 ]] && tinypm_notify_update "$latest"
        if [[ "${update_quiet:-0}" -ne 1 ]]; then
            ui_heading "TinyPM update available"
            printf '  %-12s %s\n' 'installed' "v${tinypm_version}"
            printf '  %-12s %s\n' 'available' "v${latest}"
            printf '\nRun: tinypm self-update\n'
        fi
        return 0
    fi

    [[ "${update_quiet:-0}" -eq 1 ]] || ui_success "TinyPM is up to date (v${tinypm_version})"
    return 1
}

tinypm_install_prefix() {
    if [[ -n "${TINYPM_PREFIX:-}" ]]; then
        printf '%s\n' "$TINYPM_PREFIX"
    elif [[ "$runtime_root" == "$HOME"/* ]]; then
        printf '%s\n' "$runtime_root"
    else
        printf '%s\n' "$HOME/.tinypm"
    fi
}

self_update_tinypm() {
    local latest="" prefix tmp archive_dir installer flavor native_pm

    latest="$(tinypm_latest_version 2>/dev/null || true)"
    if [[ -n "$latest" ]]; then
        if ! tinypm_version_lt "$tinypm_version" "$latest"; then
            ui_success "TinyPM is already current (v${tinypm_version})"
            return 0
        fi
    fi

    if [[ "${self_update_yes:-0}" -ne 1 && -t 0 ]]; then
        printf 'Install TinyPM update'
        [[ -n "$latest" ]] && printf ' v%s' "$latest"
        printf '? [y/N] '
        read -r answer
        case "${answer,,}" in
            y|yes) ;;
            *) die "self-update cancelled" ;;
        esac
    fi

    prefix="$(tinypm_install_prefix)"
    flavor="$(tinypm_active_flavor)"
    native_pm="$(tinypm_config_get native_pm 2>/dev/null || echo auto)"
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/tinypm-update.XXXXXX")"
    trap 'rm -rf "$tmp"' RETURN

    if tinypm_fetch_url "$(tinypm_update_archive_url)" >"$tmp/tinypm.tar.gz"; then
        tar -xzf "$tmp/tinypm.tar.gz" -C "$tmp"
        archive_dir="$(find "$tmp" -maxdepth 1 -type d -name 'TinyPM-*' | head -n1)"
        installer="$archive_dir/scripts/install.sh"
        [[ -f "$installer" ]] || die "downloaded TinyPM archive did not include scripts/install.sh"
        TINYPM_PREFIX="$prefix" TINYPM_FLAVOR="$flavor" \
            backend_run bash "$installer" --flavor "$flavor" --native "$native_pm" --yes
        ui_success "TinyPM updated in $prefix"
        return 0
    fi

    if [[ -f /etc/abora/tinypm/install.sh ]]; then
        ui_warn "remote update failed; reinstalling the bundled Abora TinyPM copy"
        TINYPM_PREFIX="$prefix" TINYPM_FLAVOR="$flavor" \
            backend_run bash /etc/abora/tinypm/install.sh --flavor "$flavor" --native "$native_pm" --yes
        ui_success "TinyPM reinstalled in $prefix"
        return 0
    fi

    die "TinyPM update failed and no bundled fallback was found"
}
