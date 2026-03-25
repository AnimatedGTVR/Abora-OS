#!/usr/bin/env bash

native_pm_resolve() {
    local requested="${1:-native}"

    if [[ "$requested" == "native" ]]; then
        detect_native_pm
        return
    fi

    if is_native_provider "$requested"; then
        printf '%s\n' "$requested"
        return
    fi

    die "unknown native package manager: $requested"
}

native_alias_package() {
    local package="$1"
    local pm="$2"

    case "$pm:$package" in
        apt:fastfetch) echo "fastfetch" ;;
        dnf:fastfetch) echo "fastfetch" ;;
        pacman:fastfetch) echo "fastfetch" ;;
        xbps:fastfetch) echo "fastfetch" ;;
        zypper:fastfetch) echo "fastfetch" ;;
        apk:fastfetch) echo "fastfetch" ;;
        brew:fastfetch) echo "fastfetch" ;;
        nix:fastfetch) echo "fastfetch" ;;
        apt:bat) echo "batcat" ;;
        apt:fd) echo "fd-find" ;;
        *) echo "$package" ;;
    esac
}

native_run_with_error() {
    local pm="$1"
    local action="$2"
    shift 2

    "$@" || die "native[$pm] $action failed"
}

native_requires_root() {
    case "$1" in
        apt|dnf|pacman|xbps|zypper|apk|emerge) return 0 ;;
        brew|nix) return 1 ;;
        *) return 0 ;;
    esac
}

package_in_apt() {
    local package="$1"
    local pm resolved

    pm="$(native_pm_resolve "${2:-native}")" || return 1
    resolved="$(native_alias_package "$package" "$pm")"

    case "$pm" in
        apt) backend_run dpkg -s "$resolved" >/dev/null 2>&1 ;;
        dnf) backend_run rpm -q "$resolved" >/dev/null 2>&1 ;;
        pacman) backend_run pacman -Q "$resolved" >/dev/null 2>&1 ;;
        xbps) backend_run xbps-query -Rs "^$resolved$" >/dev/null 2>&1 ;;
        zypper) backend_run rpm -q "$resolved" >/dev/null 2>&1 ;;
        apk) backend_run apk info -e "$resolved" >/dev/null 2>&1 ;;
        emerge)
            if backend_has_cmd qlist; then
                backend_run qlist -I "$resolved" >/dev/null 2>&1
            else
                # shellcheck disable=SC2016
                backend_run sh -lc 'ls /var/db/pkg/* 2>/dev/null | grep -F "/$1-" >/dev/null 2>&1' sh "$resolved"
            fi
            ;;
        brew) backend_run brew list --formula "$resolved" >/dev/null 2>&1 || backend_run brew list "$resolved" >/dev/null 2>&1 ;;
        nix) backend_run nix-env -q "$resolved" >/dev/null 2>&1 ;;
    esac
}

apt_install() {
    local package="$1"
    local pm resolved

    pm="$(native_pm_resolve "${2:-native}")"
    resolved="$(native_alias_package "$package" "$pm")"

    case "$pm" in
        apt)
            native_run_with_error "$pm" "install $resolved" run_with_spinner "Installing $resolved with APT" backend_run_root apt-get install -y "$resolved"
            ;;
        dnf)
            native_run_with_error "$pm" "install $resolved" run_with_spinner "Installing $resolved with DNF" backend_run_root dnf install -y "$resolved"
            ;;
        pacman)
            native_run_with_error "$pm" "install $resolved" run_with_spinner "Installing $resolved with Pacman" backend_run_root pacman -S --noconfirm "$resolved"
            ;;
        xbps)
            native_run_with_error "$pm" "install $resolved" run_with_spinner "Installing $resolved with XBPS" backend_run_root xbps-install -Sy "$resolved"
            ;;
        zypper)
            native_run_with_error "$pm" "install $resolved" run_with_spinner "Installing $resolved with Zypper" backend_run_root zypper --non-interactive install "$resolved"
            ;;
        apk)
            native_run_with_error "$pm" "install $resolved" run_with_spinner "Installing $resolved with APK" backend_run_root apk add "$resolved"
            ;;
        emerge)
            native_run_with_error "$pm" "install $resolved" run_with_spinner "Installing $resolved with Portage" backend_run_root emerge --ask=n "$resolved"
            ;;
        brew)
            native_run_with_error "$pm" "install $resolved" run_with_spinner "Installing $resolved with Homebrew" backend_run brew install "$resolved"
            ;;
        nix)
            native_run_with_error "$pm" "install $resolved" run_with_spinner "Installing $resolved with Nix" backend_run nix-env -iA "nixpkgs.$resolved"
            ;;
    esac
}

apt_search() {
    local query="$1"
    local pm

    pm="$(native_pm_resolve "${2:-native}")"

    case "$pm" in
        apt) backend_run apt-cache search "$query" || die "native[$pm] search failed" ;;
        dnf) backend_run dnf search "$query" || die "native[$pm] search failed" ;;
        pacman) backend_run pacman -Ss "$query" || die "native[$pm] search failed" ;;
        xbps) backend_run xbps-query -Rs "$query" || die "native[$pm] search failed" ;;
        zypper) backend_run zypper search "$query" || die "native[$pm] search failed" ;;
        apk) backend_run apk search "$query" || die "native[$pm] search failed" ;;
        emerge) backend_run emerge --search "$query" || die "native[$pm] search failed" ;;
        brew) backend_run brew search "$query" || die "native[$pm] search failed" ;;
        nix) backend_run nix search nixpkgs "$query" || die "native[$pm] search failed" ;;
    esac
}

apt_remove() {
    local package="$1"
    local pm resolved

    pm="$(native_pm_resolve "${2:-native}")"
    resolved="$(native_alias_package "$package" "$pm")"

    case "$pm" in
        apt)
            native_run_with_error "$pm" "remove $resolved" run_with_spinner "Removing $resolved from APT" backend_run_root apt-get remove -y "$resolved"
            ;;
        dnf)
            native_run_with_error "$pm" "remove $resolved" run_with_spinner "Removing $resolved from DNF" backend_run_root dnf remove -y "$resolved"
            ;;
        pacman)
            native_run_with_error "$pm" "remove $resolved" run_with_spinner "Removing $resolved from Pacman" backend_run_root pacman -Rns --noconfirm "$resolved"
            ;;
        xbps)
            native_run_with_error "$pm" "remove $resolved" run_with_spinner "Removing $resolved from XBPS" backend_run_root xbps-remove -Ry "$resolved"
            ;;
        zypper)
            native_run_with_error "$pm" "remove $resolved" run_with_spinner "Removing $resolved from Zypper" backend_run_root zypper --non-interactive remove "$resolved"
            ;;
        apk)
            native_run_with_error "$pm" "remove $resolved" run_with_spinner "Removing $resolved from APK" backend_run_root apk del "$resolved"
            ;;
        emerge)
            native_run_with_error "$pm" "remove $resolved" run_with_spinner "Removing $resolved from Portage" backend_run_root emerge --ask=n --depclean "$resolved"
            ;;
        brew)
            native_run_with_error "$pm" "remove $resolved" run_with_spinner "Removing $resolved from Homebrew" backend_run brew uninstall "$resolved"
            ;;
        nix)
            native_run_with_error "$pm" "remove $resolved" run_with_spinner "Removing $resolved from Nix" backend_run nix-env -e "$resolved"
            ;;
    esac
}

apt_list() {
    local pm

    pm="$(native_pm_resolve "${1:-native}")"

    case "$pm" in
        apt) backend_run dpkg-query -W || die "native[$pm] list failed" ;;
        dnf) backend_run dnf list installed || die "native[$pm] list failed" ;;
        pacman) backend_run pacman -Q || die "native[$pm] list failed" ;;
        xbps) backend_run xbps-query -l || die "native[$pm] list failed" ;;
        zypper) backend_run zypper search --installed-only || die "native[$pm] list failed" ;;
        apk) backend_run apk info || die "native[$pm] list failed" ;;
        emerge)
            if backend_has_cmd qlist; then
                backend_run qlist -I || die "native[$pm] list failed"
            else
                backend_run sh -lc 'find /var/db/pkg -mindepth 2 -maxdepth 2 -type d -printf "%f\n" 2>/dev/null | sort' || die "native[$pm] list failed"
            fi
            ;;
        brew) backend_run brew list || die "native[$pm] list failed" ;;
        nix) backend_run nix-env -q || die "native[$pm] list failed" ;;
    esac
}

apt_update() {
    local pm

    pm="$(native_pm_resolve "${1:-native}")"

    case "$pm" in
        apt)
            native_run_with_error "$pm" update run_with_spinner "Updating APT package lists" backend_run_root apt-get update
            native_run_with_error "$pm" upgrade run_with_spinner "Upgrading APT packages" backend_run_root apt-get upgrade -y
            ;;
        dnf)
            native_run_with_error "$pm" upgrade run_with_spinner "Upgrading DNF packages" backend_run_root dnf upgrade -y
            ;;
        pacman)
            native_run_with_error "$pm" upgrade run_with_spinner "Upgrading Pacman packages" backend_run_root pacman -Syu --noconfirm
            ;;
        xbps)
            native_run_with_error "$pm" upgrade run_with_spinner "Upgrading XBPS packages" backend_run_root xbps-install -Syu
            ;;
        zypper)
            native_run_with_error "$pm" refresh run_with_spinner "Refreshing Zypper metadata" backend_run_root zypper --non-interactive refresh
            native_run_with_error "$pm" update run_with_spinner "Upgrading Zypper packages" backend_run_root zypper --non-interactive update
            ;;
        apk)
            native_run_with_error "$pm" refresh run_with_spinner "Refreshing APK indexes" backend_run_root apk update
            native_run_with_error "$pm" upgrade run_with_spinner "Upgrading APK packages" backend_run_root apk upgrade
            ;;
        emerge)
            native_run_with_error "$pm" sync run_with_spinner "Syncing Portage" backend_run_root emerge --sync
            native_run_with_error "$pm" upgrade run_with_spinner "Upgrading Portage world set" backend_run_root emerge -uDN --with-bdeps=y @world
            ;;
        brew)
            native_run_with_error "$pm" update run_with_spinner "Updating Homebrew" backend_run brew update
            native_run_with_error "$pm" upgrade run_with_spinner "Upgrading Homebrew packages" backend_run brew upgrade
            ;;
        nix)
            native_run_with_error "$pm" update run_with_spinner "Updating Nix channels" backend_run nix-channel --update
            native_run_with_error "$pm" upgrade run_with_spinner "Upgrading Nix profile" backend_run nix-env -u '*'
            ;;
    esac
}
