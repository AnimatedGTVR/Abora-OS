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
    local resolved

    resolved="$(awk -F '\t' -v provider="$pm" -v requested="$package" \
        '$1 == provider && $2 == requested { print $3; exit }' "$(tinypm_alias_file)" 2>/dev/null || true)"
    printf '%s\n' "${resolved:-$package}"
}

native_alias_reason() {
    local package="$1" pm="$2" reason
    reason="$(awk -F '\t' -v provider="$pm" -v requested="$package" \
        '$1 == provider && $2 == requested { print $4; exit }' "$(tinypm_alias_file)" 2>/dev/null || true)"
    printf '%s\n' "${reason:-No alias is needed; the requested name is passed through unchanged}"
}

native_alias_catalog_valid() {
    local alias_file
    alias_file="$(tinypm_alias_file)"
    [[ -r "$alias_file" ]] || return 1
    awk -F '\t' '
        /^#/ || NF == 0 { next }
        NF < 4 { bad=1 }
        { key=$1 SUBSEP $2; if (seen[key]++) bad=1 }
        END { exit bad }
    ' "$alias_file"
}

native_package_identity() {
    local package="$1" pm
    pm="$(native_pm_resolve "${2:-native}")"
    printf '%s:%s\n' "$pm" "$(native_alias_package "$package" "$pm")"
}

native_install_preview() {
    local package="$1" pm="$2" escaped
    printf -v escaped '%q' "$package"
    case "$pm" in
        apt) printf 'apt-get install -y %s\n' "$escaped" ;;
        dnf) printf 'dnf install -y %s\n' "$escaped" ;;
        pacman) printf 'pacman -S --noconfirm %s\n' "$escaped" ;;
        xbps) printf 'xbps-install -Sy %s\n' "$escaped" ;;
        zypper) printf 'zypper --non-interactive install %s\n' "$escaped" ;;
        apk) printf 'apk add %s\n' "$escaped" ;;
        emerge) printf 'emerge --ask=n %s\n' "$escaped" ;;
        eopkg) printf 'eopkg install -y %s\n' "$escaped" ;;
        swupd) printf 'swupd bundle-add %s\n' "$escaped" ;;
        slackpkg) printf 'slackpkg -batch=on -default_answer=y install %s\n' "$escaped" ;;
        opkg) printf 'opkg install %s\n' "$escaped" ;;
        urpmi) printf 'urpmi --auto %s\n' "$escaped" ;;
        guix) printf 'guix install %s\n' "$escaped" ;;
        brew) printf 'brew install %s\n' "$escaped" ;;
        nix) printf 'nix-env -iA nixpkgs.%s\n' "$escaped" ;;
    esac
}

native_package_description() {
    local package="$1" pm="$2"
    case "$pm" in
        apt)
            backend_run apt-cache show "$package" 2>/dev/null \
                | awk -F ': ' '$1 == "Description" { print $2; exit }'
            ;;
        dnf)
            backend_run dnf info "$package" 2>/dev/null \
                | awk '/^Summary[[:space:]]*:/ { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }'
            ;;
        pacman)
            backend_run pacman -Si "$package" 2>/dev/null \
                | awk '/^Description[[:space:]]*:/ { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }'
            ;;
        xbps)
            backend_run xbps-query -RS "$package" 2>/dev/null \
                | awk '/^short_desc:/ { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }'
            ;;
        zypper)
            backend_run zypper --non-interactive info "$package" 2>/dev/null \
                | awk '/^Summary[[:space:]]*:/ { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }'
            ;;
        apk)
            backend_run apk info -d "$package" 2>/dev/null \
                | awk '/ description:$/ { getline; print; exit }'
            ;;
        emerge)
            backend_run emerge --search "$package" 2>/dev/null \
                | awk '/^[[:space:]]*Description:/ { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }'
            ;;
        eopkg)
            backend_run eopkg info "$package" 2>/dev/null \
                | awk '/^Summary[[:space:]]*:/ { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }'
            ;;
        slackpkg)
            backend_run slackpkg info "$package" 2>/dev/null \
                | awk '/^[[:space:]]*PACKAGE DESCRIPTION:/ { getline; sub(/^[^:]*:[[:space:]]*/, ""); print; exit }'
            ;;
        opkg)
            backend_run opkg info "$package" 2>/dev/null \
                | awk '/^Description:/ { sub(/^Description:[[:space:]]*/, ""); print; exit }'
            ;;
        urpmi)
            backend_run urpmq -i "$package" 2>/dev/null \
                | awk '/^Summary[[:space:]]*:/ { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }'
            ;;
        guix)
            backend_run guix show "$package" 2>/dev/null \
                | awk '/^[[:space:]]*synopsis:/ { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }'
            ;;
        brew)
            backend_run brew desc "$package" 2>/dev/null \
                | awk '{ sub(/^[^:]*:[[:space:]]*/, ""); print; exit }'
            ;;
        nix)
            backend_run nix-env -qa --description "$package" 2>/dev/null \
                | awk '{$1=""; sub(/^[[:space:]]*/, ""); print; exit }'
            ;;
        swupd)
            return 0
            ;;
    esac
}

native_run_with_error() {
    local pm="$1"
    local action="$2"
    shift 2

    if ! "$@"; then
        ui_error "native[$pm] $action failed"
        return 1
    fi
}

native_requires_root() {
    case "$1" in
        apt|dnf|pacman|xbps|zypper|apk|emerge|eopkg|swupd|slackpkg|opkg|urpmi) return 0 ;;
        guix|brew|nix) return 1 ;;
        *) return 0 ;;
    esac
}

# shellcheck disable=SC2016
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
        eopkg) backend_run eopkg list-installed 2>/dev/null | awk '{print $1}' | grep -Fxq "$resolved" ;;
        swupd) backend_run swupd bundle-list 2>/dev/null | grep -Fxq "$resolved" ;;
        slackpkg) backend_run sh -c 'set -- /var/log/packages/"$1"-*; [ -e "$1" ]' sh "$resolved" 2>/dev/null ;;
        opkg) backend_run opkg status "$resolved" 2>/dev/null | grep -q '^Status:.* installed' ;;
        urpmi) backend_run rpm -q "$resolved" >/dev/null 2>&1 ;;
        guix) backend_run guix package --list-installed 2>/dev/null | awk '{print $1}' | grep -Fxq "$resolved" ;;
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
        eopkg)
            native_run_with_error "$pm" "install $resolved" run_with_spinner "Installing $resolved with eopkg" backend_run_root eopkg install -y "$resolved"
            ;;
        swupd)
            native_run_with_error "$pm" "install $resolved" run_with_spinner "Adding $resolved with swupd" backend_run_root swupd bundle-add "$resolved"
            ;;
        slackpkg)
            native_run_with_error "$pm" "install $resolved" run_with_spinner "Installing $resolved with slackpkg" backend_run_root slackpkg -batch=on -default_answer=y install "$resolved"
            ;;
        opkg)
            native_run_with_error "$pm" "install $resolved" run_with_spinner "Installing $resolved with opkg" backend_run_root opkg install "$resolved"
            ;;
        urpmi)
            native_run_with_error "$pm" "install $resolved" run_with_spinner "Installing $resolved with URPMI" backend_run_root urpmi --auto "$resolved"
            ;;
        guix)
            native_run_with_error "$pm" "install $resolved" run_with_spinner "Installing $resolved with Guix" backend_run guix install "$resolved"
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
        eopkg) backend_run eopkg search "$query" || die "native[$pm] search failed" ;;
        swupd) backend_run swupd search "$query" || die "native[$pm] search failed" ;;
        slackpkg) backend_run slackpkg search "$query" || die "native[$pm] search failed" ;;
        opkg) backend_run opkg find "*$query*" || die "native[$pm] search failed" ;;
        urpmi) backend_run urpmq -y "$query" || die "native[$pm] search failed" ;;
        guix) backend_run guix search "$query" || die "native[$pm] search failed" ;;
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
        eopkg)
            native_run_with_error "$pm" "remove $resolved" run_with_spinner "Removing $resolved with eopkg" backend_run_root eopkg remove -y "$resolved"
            ;;
        swupd)
            native_run_with_error "$pm" "remove $resolved" run_with_spinner "Removing $resolved with swupd" backend_run_root swupd bundle-remove "$resolved"
            ;;
        slackpkg)
            native_run_with_error "$pm" "remove $resolved" run_with_spinner "Removing $resolved with slackpkg" backend_run_root slackpkg -batch=on -default_answer=y remove "$resolved"
            ;;
        opkg)
            native_run_with_error "$pm" "remove $resolved" run_with_spinner "Removing $resolved with opkg" backend_run_root opkg remove "$resolved"
            ;;
        urpmi)
            native_run_with_error "$pm" "remove $resolved" run_with_spinner "Removing $resolved with URPMI" backend_run_root urpme --auto "$resolved"
            ;;
        guix)
            native_run_with_error "$pm" "remove $resolved" run_with_spinner "Removing $resolved with Guix" backend_run guix remove "$resolved"
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
        eopkg) backend_run eopkg list-installed || die "native[$pm] list failed" ;;
        swupd) backend_run swupd bundle-list || die "native[$pm] list failed" ;;
        slackpkg) backend_run slackpkg search '.*\[ installed \].*' || die "native[$pm] list failed" ;;
        opkg) backend_run opkg list-installed || die "native[$pm] list failed" ;;
        urpmi) backend_run rpm -qa || die "native[$pm] list failed" ;;
        guix) backend_run guix package --list-installed || die "native[$pm] list failed" ;;
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
        eopkg)
            native_run_with_error "$pm" update run_with_spinner "Updating eopkg repositories" backend_run_root eopkg update-repo
            native_run_with_error "$pm" upgrade run_with_spinner "Upgrading eopkg packages" backend_run_root eopkg upgrade -y
            ;;
        swupd)
            native_run_with_error "$pm" update run_with_spinner "Updating Clear Linux" backend_run_root swupd update
            ;;
        slackpkg)
            native_run_with_error "$pm" update run_with_spinner "Updating slackpkg metadata" backend_run_root slackpkg -batch=on -default_answer=y update
            native_run_with_error "$pm" upgrade run_with_spinner "Upgrading Slackware packages" backend_run_root slackpkg -batch=on -default_answer=y upgrade-all
            ;;
        opkg)
            native_run_with_error "$pm" update run_with_spinner "Updating opkg metadata" backend_run_root opkg update
            ui_warn "OpenWrt discourages mass opkg upgrades because they can soft-brick a device; metadata was refreshed only"
            ;;
        urpmi)
            native_run_with_error "$pm" update run_with_spinner "Updating URPMI metadata" backend_run_root urpmi.update -a
            native_run_with_error "$pm" upgrade run_with_spinner "Upgrading URPMI packages" backend_run_root urpmi --auto-update --auto
            ;;
        guix)
            native_run_with_error "$pm" pull run_with_spinner "Updating Guix channels" backend_run guix pull
            native_run_with_error "$pm" upgrade run_with_spinner "Upgrading Guix profile" backend_run guix upgrade
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

# Refresh repository metadata without upgrading installed packages. This is
# used after grab-add-repo; adding a source must not trigger a full OS upgrade.
native_refresh() {
    local pm

    pm="$(native_pm_resolve "${1:-native}")"

    case "$pm" in
        apt) backend_run_root apt-get update ;;
        dnf) backend_run_root dnf makecache -y ;;
        pacman) backend_run_root pacman -Sy --noconfirm ;;
        xbps) backend_run_root xbps-install -S ;;
        zypper) backend_run_root zypper --non-interactive refresh ;;
        apk) backend_run_root apk update ;;
        emerge) backend_run_root emerge --sync ;;
        eopkg) backend_run_root eopkg update-repo ;;
        swupd) backend_run_root swupd check-update ;;
        slackpkg) backend_run_root slackpkg -batch=on -default_answer=y update ;;
        opkg) backend_run_root opkg update ;;
        urpmi) backend_run_root urpmi.update -a ;;
        guix) backend_run guix pull ;;
        brew) backend_run brew update ;;
        nix) backend_run nix-channel --update ;;
    esac
}
