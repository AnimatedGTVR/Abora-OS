#!/usr/bin/env bash
# shellcheck disable=SC2154

system_os_value() {
    local key="$1"
    backend_run sh -lc '
        key="$1"
        if [ -r /etc/os-release ]; then
            . /etc/os-release
            eval "printf \"%s\" \"\${$key:-}\""
        fi
    ' sh "$key" 2>/dev/null || true
}

system_file_exists() {
    local path="$1"

    if [[ "$use_host_backend" -eq 1 ]]; then
        flatpak-spawn --host test -e "$path" 2>/dev/null
        return
    fi

    [[ -e "$path" ]]
}

system_command_state() {
    local name="$1"
    if backend_has_cmd "$name"; then
        printf 'available'
    else
        printf 'missing'
    fi
}

system_is_abora() {
    local id pretty
    id="$(system_os_value ID)"
    pretty="$(system_os_value PRETTY_NAME)"

    [[ "$id" == "abora" || "$pretty" == *"Abora"* ]] && return 0
    system_file_exists /etc/abora/VERSION
}

system_is_nixos_family() {
    local id id_like
    id="$(system_os_value ID)"
    id_like="$(system_os_value ID_LIKE)"

    [[ "$id" == "nixos" || "$id" == "abora" || "$id_like" == *"nixos"* ]] && return 0
    backend_is_nixos
}

system_layer_name() {
    if system_is_abora; then
        printf 'Abora OS'
    elif system_is_nixos_family; then
        printf 'NixOS'
    else
        printf 'Linux'
    fi
}

system_config_dir() {
    printf '%s\n' "${TINYPM_SYSTEM_CONFIG:-${ANIX_SYSTEM_CONFIG:-/etc/nixos}}"
}

system_flake_state() {
    local config_dir
    config_dir="$(system_config_dir)"

    if system_file_exists "$config_dir/flake.nix"; then
        printf 'present'
    else
        printf 'missing'
    fi
}

system_generation_state() {
    if system_file_exists /run/current-system && system_file_exists /nix/var/nix/profiles/system; then
        printf 'active'
    elif system_file_exists /run/current-system; then
        printf 'runtime-only'
    else
        printf 'unknown'
    fi
}

system_native_strategy() {
    local native_pm
    native_pm="$(detect_native_pm 2>/dev/null || true)"

    if [[ "$native_pm" == "nix" ]]; then
        if system_is_abora; then
            printf 'Nix profile packages, with Abora/ANIX system tools available'
        elif system_is_nixos_family; then
            printf 'Nix profile packages on a NixOS-family system'
        else
            printf 'Nix profile packages'
        fi
    elif [[ -n "$native_pm" ]]; then
        printf '%s native packages' "$(native_pm_label "$native_pm")"
    else
        printf 'Flatpak/Snap only until a native backend is available'
    fi
}

system_print_report() {
    local native_pm
    native_pm="$(detect_native_pm 2>/dev/null || printf 'none')"

    printf '%s system layer\n' "$tinypm_engine_name"
    printf '%s\n' '------------------------------------------------------------'
    printf '  %-18s %s\n' 'system' "$(system_layer_name)"
    printf '  %-18s %s\n' 'os' "$(backend_os_name)"
    printf '  %-18s %s\n' 'native_pm' "$native_pm"
    printf '  %-18s %s\n' 'strategy' "$(system_native_strategy)"
    printf '  %-18s %s\n' 'config_dir' "$(system_config_dir)"
    printf '  %-18s %s\n' 'flake' "$(system_flake_state)"
    printf '  %-18s %s\n' 'generation' "$(system_generation_state)"
    printf '  %-18s %s\n' 'abora' "$(system_command_state abora)"
    printf '  %-18s %s\n' 'anix' "$(system_command_state anix)"
    printf '  %-18s %s\n' 'nix' "$(system_command_state nix)"
    printf '  %-18s %s\n' 'nixos-rebuild' "$(system_command_state nixos-rebuild)"
    printf '\n'
    printf 'Useful next steps:\n'
    if backend_has_cmd anix; then
        printf '  tinypm anix doctor\n'
        printf '  tinypm anix save\n'
    elif system_is_nixos_family; then
        printf '  Install or enable ANIX for safer NixOS profile switching.\n'
    fi
    if backend_has_cmd abora; then
        printf '  tinypm abora doctor\n'
        printf '  tinypm abora update\n'
    fi
    printf '  tinypm doctor\n'
}

system_bridge_command() {
    local tool="$1"
    shift

    if ! backend_has_cmd "$tool"; then
        case "$tool" in
            anix)
                die "anix is not available on this system. On Abora, install or enable the ANIX tools first."
                ;;
            abora)
                die "abora is not available on this system. This bridge works on installed Abora systems."
                ;;
            *)
                die "$tool is not available"
                ;;
        esac
    fi

    if [[ $# -eq 0 ]]; then
        set -- help
    fi

    backend_exec "$tool" "$@"
}
