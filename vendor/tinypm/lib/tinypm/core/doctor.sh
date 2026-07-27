#!/usr/bin/env bash
# shellcheck disable=SC2154

doctor_command_path() {
    local name="$1"
    if command -v "$name" >/dev/null 2>&1; then
        command -v "$name"
        return
    fi
    if [[ -e "$HOME/.local/bin/$name" ]]; then
        printf '%s\n' "$HOME/.local/bin/$name"
        return
    fi
    printf '%s\n' missing
}

doctor_add_path_line() {
    local shell_rc="$1"

    if ! grep -q 'HOME/.local/bin' "$shell_rc" 2>/dev/null; then
        printf "\n# TinyPM\nexport PATH=\"\$HOME/.local/bin:\$PATH\"\n" >> "$shell_rc"
    fi
}

doctor_fix_runtime() {
    local local_bin="$HOME/.local/bin"

    mkdir -p "$local_bin"

    ln -sfn "$script_dir/tinypm"  "$local_bin/tinypm"
    ln -sfn "$script_dir/tinypm"  "$local_bin/tiny"
    ln -sfn "$script_dir/tinypm"  "$local_bin/grab"
    ln -sfn "$script_dir/tinypm"  "$local_bin/grab-add-repo"
    ln -sfn "$script_dir/tinypm"  "$local_bin/grab-de"
    if [[ -x "$script_dir/syspm" ]]; then
        ln -sfn "$script_dir/syspm" "$local_bin/syspm"
    fi

    # Update every shell rc the user has, not just bash: a zsh user otherwise
    # never gets ~/.local/bin on PATH and sees "command not found".
    doctor_add_path_line "$HOME/.bashrc"
    if command -v zsh >/dev/null 2>&1 || [[ -e "$HOME/.zshrc" ]]; then
        doctor_add_path_line "$HOME/.zshrc"
    fi
    if [[ -e "$HOME/.profile" ]]; then
        doctor_add_path_line "$HOME/.profile"
    fi

    ui_success 'Doctor fix applied: launchers refreshed.'
}

selftest() {
    local failures=0
    local native_pm="none"

    ui_heading 'TinyPM selftest'
    printf '%s\n' '------------------------------------------------------------'

    [[ -x "$script_dir/tinypm" ]] || { echo '[fail] missing tinypm entrypoint'; failures=$((failures+1)); }
    [[ -r "$lib_dir/core/version.sh" ]] || { echo '[fail] missing version module'; failures=$((failures+1)); }

    if detect_native_pm >/dev/null 2>&1; then
        native_pm="$(detect_native_pm)"
        echo "[ok] native package manager detected: $native_pm"
    else
        echo '[warn] no native package manager detected'
    fi

    if backend_has_cmd flatpak; then
        echo '[ok] flatpak detected'
    else
        echo '[warn] flatpak missing'
    fi

    if backend_has_cmd snap; then
        echo '[ok] snap detected'
    else
        echo '[warn] snap missing'
    fi

    if discover_apps >/dev/null 2>&1; then
        echo '[ok] catalog parse works'
    else
        echo '[fail] catalog parse failed'
        failures=$((failures+1))
    fi

    if native_alias_catalog_valid; then
        echo '[ok] package alias catalog is valid'
    else
        echo '[fail] package alias catalog is missing or invalid'
        failures=$((failures+1))
    fi

    if [[ -f "$(tinypm_catalog_file)" ]]; then
        local catalog_size
        catalog_size="$(awk 'END{print NR}' "$(tinypm_catalog_file)")"
        echo "[ok] catalog entries: $catalog_size"
    fi

    if [[ "$failures" -eq 0 ]]; then
        ui_success 'selftest passed'
        return 0
    fi

    echo "[fail] selftest failed: $failures issue(s)"
    return 1
}

doctor() {
    local path_state="missing"
    local flatpak_state="missing"
    local snap_state="missing"
    local native_state="missing"
    local native_pm="none"

    if [[ "${doctor_fix:-0}" -eq 1 ]]; then
        doctor_fix_runtime
    fi

    case ":${PATH:-}:" in
        *":$HOME/.local/bin:"*) path_state="present" ;;
    esac

    if backend_has_cmd flatpak; then
        flatpak_state="available"
    fi

    if backend_has_cmd snap; then
        snap_state="available"
    fi

    if detect_native_pm >/dev/null 2>&1; then
        native_pm="$(detect_native_pm)"
        native_state="$(native_pm_label "$native_pm")"
    fi

    ui_heading 'TinyPM doctor'
    printf '%s\n' '------------------------------------------------------------'
    printf '  %-16s %s\n' 'script_dir'   "$script_dir"
    printf '  %-16s %s\n' 'path'         "$path_state"
    printf '  %-16s %s\n' 'tinypm'       "$(doctor_command_path tinypm)"
    printf '  %-16s %s\n' 'tiny'         "$(doctor_command_path tiny)"
    printf '  %-16s %s\n' 'grab'         "$(doctor_command_path grab)"
    printf '  %-16s %s\n' 'grab-add-repo' "$(doctor_command_path grab-add-repo)"
    printf '  %-16s %s\n' 'grab-de'      "$(doctor_command_path grab-de)"
    printf '  %-16s %s\n' 'syspm'        "$(doctor_command_path syspm)"
    printf '  %-16s %s\n' 'backend_mode' "$([[ "$use_host_backend" -eq 1 ]] && echo host || echo local)"
    printf '  %-16s %s\n' 'auth_mode'    "$(backend_auth_mode)"
    printf '  %-16s %s\n' 'native_pm'    "$native_pm"
    printf '  %-16s %s\n' 'state_db'     "$(active_state_db)"
    printf '  %-16s %s\n' 'flatpak'      "$flatpak_state"
    printf '  %-16s %s\n' 'snap'         "$snap_state"
    printf '  %-16s %s\n' 'native'       "$native_state"
}
