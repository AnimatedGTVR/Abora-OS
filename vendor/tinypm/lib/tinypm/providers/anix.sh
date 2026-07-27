#!/usr/bin/env bash
# shellcheck disable=SC2154
#
# ANIX bridge. On Abora (a NixOS base) package and desktop state is declarative:
# it lives in /etc/nixos/anix.nix and is applied with a system rebuild. When the
# `anix` tool is present, TinyPM edits that config instead of doing an imperative
# `nix-env` install, so `grab` changes survive rebuilds like a real NixOS system.
#
# Detection is the trigger: on plain NixOS (no anix) or any other distro these
# helpers are never reached, so behavior there is unchanged.
#
# Env overrides:
#   TINYPM_NO_ANIX=1     ignore anix even if installed (use nix-env directly)
#   TINYPM_ANIX_APPLY=0  update the config but do NOT run `anix apply`

anix_available() {
    [[ "${TINYPM_NO_ANIX:-0}" == "1" ]] && return 1
    backend_has_cmd anix
}

anix_apply() {
    if [[ "${TINYPM_ANIX_APPLY:-1}" != "1" ]]; then
        printf 'ANIX config updated. Run "anix apply" to rebuild the system.\n'
        return 0
    fi
    # anix apply runs nixos-rebuild and streams its own (long) output, so it is
    # deliberately not wrapped in the spinner. ANIX_ASSUME_YES skips its prompts.
    ANIX_ASSUME_YES=1 backend_run anix apply || die "anix apply failed"
}

anix_install_pkg() {
    local pkg="$1"

    ANIX_ASSUME_YES=1 backend_run anix package add "$pkg" \
        || die "anix could not add $pkg to the config"
    anix_apply
}

anix_remove_pkg() {
    local pkg="$1"

    ANIX_ASSUME_YES=1 backend_run anix package remove "$pkg" \
        || die "anix could not remove $pkg from the config"
    anix_apply
}

anix_set_desktop() {
    local de="$1"

    ANIX_ASSUME_YES=1 backend_run anix set desktop "$de" \
        || die "anix could not set desktop $de"
    anix_apply
}
