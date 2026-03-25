#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154

spinner="$script_dir/_spinner"
version_cmd="$script_dir/version"
use_host_backend=0
tinypm_system_name="TinyPM V3"
tinypm_engine_name="Parcel"
tinypm_version="3.0.0"
tinypm_tagline=""

tinypm_active_flavor() {
    local flavor="${TINYPM_FLAVOR:-}"

    if [[ -z "$flavor" ]] && declare -F tinypm_config_get >/dev/null 2>&1; then
        flavor="$(tinypm_config_get tinypm_flavor 2>/dev/null || true)"
    fi

    printf '%s\n' "${flavor:-default}"
}

tinypm_load_flavor_metadata() {
    local config_file

    tinypm_system_name="TinyPM V3"
    tinypm_engine_name="Parcel"
    tinypm_tagline=""

    config_file="$(tinypm_flavor_file flavor.conf 2>/dev/null || true)"
    [[ -n "$config_file" ]] || return 0

    # shellcheck disable=SC1090
    . "$config_file"

    [[ -n "${FLAVOR_NAME:-}" ]] && tinypm_system_name="$FLAVOR_NAME"
    [[ -n "${FLAVOR_ENGINE_NAME:-}" ]] && tinypm_engine_name="$FLAVOR_ENGINE_NAME"
    [[ -n "${FLAVOR_TAGLINE:-}" ]] && tinypm_tagline="$FLAVOR_TAGLINE"
}

tinypm_flavor_file() {
    local relative_path="$1"
    local candidate

    candidate="$script_dir/flavors/$(tinypm_active_flavor)/$relative_path"

    [[ -r "$candidate" ]] || return 1
    printf '%s\n' "$candidate"
}

tinypm_logo_file() {
    tinypm_flavor_file logo.txt || printf '%s\n' "$script_dir/share/logo.txt"
}

tinypm_catalog_file() {
    tinypm_flavor_file catalog.tsv || printf '%s\n' "$script_dir/share/catalog.tsv"
}

tinypm_version_label() {
    printf '%s\n' "$tinypm_system_name / $tinypm_engine_name v$tinypm_version"
}

tinypm_load_flavor_metadata

if [[ "${container:-}" == "flatpak" ]] && command -v flatpak-spawn >/dev/null 2>&1; then
    use_host_backend=1
fi

die() {
    echo "Parcel: $*" >&2
    exit 1
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

backend_run() {
    if [[ "$use_host_backend" -eq 1 ]]; then
        flatpak-spawn --host "$@"
        return
    fi

    "$@"
}

backend_exec() {
    if [[ "$use_host_backend" -eq 1 ]]; then
        exec flatpak-spawn --host "$@"
    fi

    exec "$@"
}

host_run() {
    if [[ "$use_host_backend" -eq 1 ]]; then
        flatpak-spawn --host "$@"
        return
    fi

    "$@"
}

host_has_cmd() {
    local cmd="$1"

    if [[ "$use_host_backend" -eq 1 ]]; then
        local escaped_cmd
        printf -v escaped_cmd '%q' "$cmd"
        flatpak-spawn --host sh -lc "command -v $escaped_cmd >/dev/null 2>&1" 2>/dev/null
        return
    fi

    command -v "$cmd" >/dev/null 2>&1
}

graphical_session_available() {
    [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]
}

backend_run_root() {
    if [[ "$use_host_backend" -eq 1 ]]; then
        if graphical_session_available && host_has_cmd pkexec; then
            flatpak-spawn --host env \
                DISPLAY="${DISPLAY:-}" \
                WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
                XAUTHORITY="${XAUTHORITY:-}" \
                DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" \
                XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
                pkexec "$@"
            return
        fi

        if host_has_cmd sudo; then
            flatpak-spawn --host sudo "$@"
            return
        fi

        flatpak-spawn --host "$@"
        return
    fi

    if graphical_session_available && has_cmd pkexec; then
        env \
            DISPLAY="${DISPLAY:-}" \
            WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}" \
            XAUTHORITY="${XAUTHORITY:-}" \
            DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-}" \
            XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}" \
            pkexec "$@"
        return
    fi

    if has_cmd sudo; then
        sudo "$@"
        return
    fi

    "$@"
}

backend_auth_mode() {
    if [[ "$use_host_backend" -eq 1 ]]; then
        if graphical_session_available && host_has_cmd pkexec; then
            printf '%s\n' 'pkexec'
            return
        fi
        if host_has_cmd sudo; then
            printf '%s\n' 'sudo'
            return
        fi
        printf '%s\n' 'direct'
        return
    fi

    if graphical_session_available && has_cmd pkexec; then
        printf '%s\n' 'pkexec'
    elif has_cmd sudo; then
        printf '%s\n' 'sudo'
    else
        printf '%s\n' 'direct'
    fi
}

backend_has_cmd() {
    local cmd="$1"

    if [[ "$use_host_backend" -eq 1 ]]; then
        local escaped_cmd
        printf -v escaped_cmd '%q' "$cmd"
        flatpak-spawn --host sh -lc "command -v $escaped_cmd >/dev/null 2>&1" 2>/dev/null
        return
    fi

    command -v "$cmd" >/dev/null 2>&1
}

backend_os_name() {
    if [[ "$use_host_backend" -eq 1 ]]; then
        # shellcheck disable=SC2016
        flatpak-spawn --host sh -lc '
            if command -v lsb_release >/dev/null 2>&1; then
                lsb_release -d | cut -f2
            elif [ -r /etc/os-release ]; then
                . /etc/os-release
                printf "%s\n" "${PRETTY_NAME:-$NAME}"
            else
                uname -s
            fi
        '
        return
    fi

    if command -v lsb_release >/dev/null 2>&1; then
        lsb_release -d | cut -f2
    elif [[ -r /etc/os-release ]]; then
        . /etc/os-release
        printf "%s\n" "${PRETTY_NAME:-$NAME}"
    else
        uname -s
    fi
}

backend_is_nixos() {
    if [[ "$use_host_backend" -eq 1 ]]; then
        # shellcheck disable=SC2016
        flatpak-spawn --host sh -lc '
            if [ -r /etc/os-release ]; then
                . /etc/os-release
                [ "${ID:-}" = "nixos" ]
            else
                exit 1
            fi
        ' 2>/dev/null
        return
    fi

    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        [[ "${ID:-}" == "nixos" ]]
        return
    fi

    return 1
}

native_pm_command() {
    case "$1" in
        apt) printf '%s\n' apt-get ;;
        dnf) printf '%s\n' dnf ;;
        pacman) printf '%s\n' pacman ;;
        xbps) printf '%s\n' xbps-install ;;
        zypper) printf '%s\n' zypper ;;
        apk) printf '%s\n' apk ;;
        emerge) printf '%s\n' emerge ;;
        brew) printf '%s\n' brew ;;
        nix) printf '%s\n' nix-env ;;
        *) return 1 ;;
    esac
}

native_pm_available() {
    local pm="$1"
    local cmd

    cmd="$(native_pm_command "$pm")" || return 1
    backend_has_cmd "$cmd"
}

detect_native_pm() {
    local configured

    configured="$(tinypm_config_get native_pm 2>/dev/null || true)"
    if [[ -n "$configured" && "$configured" != "auto" ]] && native_pm_available "$configured"; then
        printf '%s\n' "$configured"
        return 0
    fi

    # Abora rides on NixOS, so prefer Nix when the host identifies as NixOS.
    if backend_is_nixos && native_pm_available nix; then
        printf '%s\n' nix
        return 0
    fi

    for pm in apt dnf pacman xbps zypper apk emerge brew nix; do
        if native_pm_available "$pm"; then
            printf '%s\n' "$pm"
            return 0
        fi
    done

    return 1
}

native_pm_label() {
    case "$1" in
        apt) printf '%s\n' 'APT' ;;
        dnf) printf '%s\n' 'DNF' ;;
        pacman) printf '%s\n' 'Pacman' ;;
        xbps) printf '%s\n' 'XBPS' ;;
        zypper) printf '%s\n' 'Zypper' ;;
        apk) printf '%s\n' 'APK' ;;
        emerge) printf '%s\n' 'Portage' ;;
        brew) printf '%s\n' 'Homebrew' ;;
        nix) printf '%s\n' 'Nix' ;;
        *) printf '%s\n' "$1" ;;
    esac
}

is_native_provider() {
    case "$1" in
        native|apt|dnf|pacman|xbps|zypper|apk|emerge|brew|nix) return 0 ;;
        *) return 1 ;;
    esac
}

normalize_provider() {
    case "${1:-auto}" in
        flatpack) echo "flatpak" ;;
        native) echo "native" ;;
        *) echo "${1:-auto}" ;;
    esac
}

provider_from_flag() {
    case "${1:-}" in
        -f|-flat|-flatpak) echo "flatpak" ;;
        -s|--snp|--snap) echo "snap" ;;
        -n|--nat|--native) echo "native" ;;
        f|flat) echo "flatpak" ;;
        s|snp) echo "snap" ;;
        n|nat) echo "native" ;;
        --brew) echo "brew" ;;
        --nix) echo "nix" ;;
        auto|flatpak|snap|native|apt|dnf|pacman|xbps|zypper|apk|emerge|brew|nix|flatpack)
            normalize_provider "$1"
            ;;
        *) return 1 ;;
    esac
}

available_install_providers() {
    local native_pm

    native_pm="$(detect_native_pm 2>/dev/null || true)"
    if [[ -n "$native_pm" ]]; then
        printf 'native:%s\n' "$native_pm"
    fi
    if backend_has_cmd flatpak; then
        printf 'flatpak:flatpak\n'
    fi
    if backend_has_cmd snap; then
        printf 'snap:snap\n'
    fi
}

prompt_install_provider() {
    local package="$1"
    shift
    local options=("$@")
    local choice index label provider native_pm

    [[ -t 0 && -t 1 ]] || {
        printf '%s\n' "${options[0]%%:*}"
        return 0
    }

    printf '\nParcel install routing for %s\n' "$package" >&2
    printf 'Multiple package sources are available. Choose one:\n' >&2

    index=1
    for choice in "${options[@]}"; do
        provider="${choice%%:*}"
        native_pm="${choice#*:}"
        case "$provider" in
            native) label="Native ($(native_pm_label "$native_pm"))" ;;
            flatpak) label="Flatpak" ;;
            snap) label="Snap" ;;
            *) label="$provider" ;;
        esac
        printf '  %s. %s\n' "$index" "$label" >&2
        index=$((index + 1))
    done

    while true; do
        printf 'Install via [1-%s]: ' "${#options[@]}" >&2
        IFS= read -r choice || {
            printf '%s\n' "${options[0]%%:*}"
            return 0
        }
        case "$choice" in
            ''|*[!0-9]*) ;;
            *)
                if [[ "$choice" -ge 1 && "$choice" -le "${#options[@]}" ]]; then
                    printf '%s\n' "${options[$((choice - 1))]%%:*}"
                    return 0
                fi
                ;;
        esac
        printf 'Please choose a valid source.\n' >&2
    done
}

ensure_provider_available() {
    local provider
    provider="$(normalize_provider "$1")"

    case "$provider" in
        flatpak) backend_has_cmd flatpak || die "flatpak is not installed" ;;
        snap) backend_has_cmd snap || die "snap is not installed" ;;
        auto)
            detect_native_pm >/dev/null 2>&1 || backend_has_cmd flatpak || backend_has_cmd snap || die "no native package manager, flatpak, or snap backend is available"
            ;;
        *)
            if is_native_provider "$provider"; then
                if [[ "$provider" == "native" ]]; then
                    detect_native_pm >/dev/null 2>&1 || die "no supported native package manager was detected"
                else
                    native_pm_available "$provider" || die "$provider is not installed"
                fi
            else
                die "unknown provider: $provider"
            fi
            ;;
    esac
}

pick_install_provider() {
    local requested native_pm
    local options=()
    requested="$(normalize_provider "${1:-auto}")"

    case "$requested" in
        flatpak|snap)
            ensure_provider_available "$requested"
            echo "$requested"
            ;;
        auto)
            native_pm="$(detect_native_pm 2>/dev/null || true)"
            if [[ -n "$native_pm" ]]; then
                options+=("native:$native_pm")
            fi
            if backend_has_cmd flatpak; then
                options+=("flatpak:flatpak")
            fi
            if backend_has_cmd snap; then
                options+=("snap:snap")
            fi

            case "${#options[@]}" in
                0) die "no native package manager, flatpak, or snap backend is available" ;;
                1) echo "${options[0]%%:*}" ;;
                *) prompt_install_provider "${package:-package}" "${options[@]}" ;;
            esac
            ;;
        *)
            if is_native_provider "$requested"; then
                ensure_provider_available "$requested"
                if [[ "$requested" == "native" ]]; then
                    detect_native_pm
                else
                    echo "$requested"
                fi
            else
                die "unknown provider: $requested"
            fi
            ;;
    esac
}

pick_installed_provider() {
    local package="$1"
    local requested
    requested="$(normalize_provider "${2:-auto}")"

    case "$requested" in
        flatpak|snap)
            ensure_provider_available "$requested"
            echo "$requested"
            ;;
        auto)
            if backend_has_cmd flatpak && package_in_flatpak "$package"; then
                echo "flatpak"
            elif backend_has_cmd snap && package_in_snap "$package"; then
                echo "snap"
            elif package_in_apt "$package" 2>/dev/null; then
                detect_native_pm
            elif detect_native_pm >/dev/null 2>&1; then
                detect_native_pm
            elif backend_has_cmd flatpak; then
                echo "flatpak"
            elif backend_has_cmd snap; then
                echo "snap"
            else
                die "no native package manager, flatpak, or snap backend is available"
            fi
            ;;
        *)
            if is_native_provider "$requested"; then
                ensure_provider_available "$requested"
                if [[ "$requested" == "native" ]]; then
                    detect_native_pm
                else
                    echo "$requested"
                fi
            else
                die "unknown provider: $requested"
            fi
            ;;
    esac
}

pick_runner_provider() {
    local package="$1"
    local requested
    requested="$(normalize_provider "${2:-auto}")"

    case "$requested" in
        flatpak|snap)
            ensure_provider_available "$requested"
            echo "$requested"
            ;;
        auto)
            if backend_has_cmd flatpak && package_in_flatpak "$package"; then
                echo "flatpak"
            elif backend_has_cmd snap && package_in_snap "$package"; then
                echo "snap"
            else
                die "run requires flatpak or snap for $package"
            fi
            ;;
        *)
            if is_native_provider "$requested"; then
                die "run is not supported for native packages"
            fi
            die "unknown provider: $requested"
            ;;
    esac
}
