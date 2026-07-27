#!/usr/bin/env bash

package_in_snap() {
    backend_run snap list "$1" >/dev/null 2>&1
}

snap_install() {
    run_with_spinner "Installing $1 with Snap" backend_run_root snap install "$1"
}

snap_search() {
    backend_run snap find "$1"
}

snap_remove() {
    run_with_spinner "Removing $1 from Snap" backend_run_root snap remove "$1"
}

snap_list() {
    backend_run snap list
}

snap_run() {
    backend_exec snap run "$1"
}

snap_update() {
    run_with_spinner "Updating Snap packages" backend_run_root snap refresh
}
