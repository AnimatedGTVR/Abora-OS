#!/usr/bin/env bash

package_in_flatpak() {
    backend_run flatpak info "$1" >/dev/null 2>&1
}

flatpak_has_remote() {
    backend_run flatpak remotes --columns=name 2>/dev/null | grep -Fx "$1" >/dev/null 2>&1
}

install_flatpak() {
    local package="$1"

    if [[ "$package" == */* ]]; then
        local remote ref
        remote="${package%%/*}"
        ref="${package#*/}"
        run_with_spinner "Installing $ref from $remote" backend_run flatpak install -y "$remote" "$ref"
        return
    fi

    if run_with_spinner "Installing $package with Flatpak" backend_run flatpak install -y "$package"; then
        return
    fi

    if flatpak_has_remote flathub; then
        run_with_spinner "Retrying $package from Flathub" backend_run flatpak install -y flathub "$package"
        return
    fi

    die "flatpak install failed for $package"
}

flatpak_search() {
    backend_run flatpak search "$1"
}

flatpak_remove() {
    run_with_spinner "Removing $1 from Flatpak" backend_run flatpak uninstall -y "$1"
}

flatpak_list() {
    backend_run flatpak list --app
}

flatpak_run() {
    backend_exec flatpak run "$1"
}

flatpak_update() {
    run_with_spinner "Updating Flatpak packages" backend_run flatpak update -y
}
