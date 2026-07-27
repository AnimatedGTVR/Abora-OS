#!/usr/bin/env bash
# shellcheck disable=SC2154
#
# Desktop-environment installer. `grab de <name>` turns a logical DE name
# (cosmic, gnome, plasma, xfce) into the right install for the active backend.
# On Nix/Abora a DE is declarative, so we print the configuration.nix snippet
# instead of running nix-env (which would only drop binaries, not a session).

de_canonical() {
    case "$1" in
        cosmic|cosmic-epoch|cosmic-de|cosmic-session) echo cosmic ;;
        gnome|gnome3|gnome-shell) echo gnome ;;
        kde|plasma|kde-plasma|plasma6) echo plasma ;;
        xfce|xfce4) echo xfce ;;
        *) return 1 ;;
    esac
}

de_label() {
    case "$1" in
        cosmic) echo "COSMIC" ;;
        gnome) echo "GNOME" ;;
        plasma) echo "KDE Plasma" ;;
        xfce) echo "Xfce" ;;
        *) echo "$1" ;;
    esac
}

de_supported_list() {
    echo "cosmic, gnome, plasma, xfce"
}

# Map a TinyPM desktop to the name ANIX's `anix set desktop` accepts.
# Returns non-zero for desktops ANIX has no option for (e.g. cosmic), so those
# fall back to the printed declarative instructions.
de_anix_name() {
    case "$1" in
        gnome) echo gnome ;;
        plasma) echo plasma ;;
        xfce) echo xfce ;;
        *) return 1 ;;
    esac
}

# Returns "<packages>|<display-manager.service>" for a DE on a native PM.
# An empty service half means the meta target already provides a greeter
# (or the distro picks one), so we do not force-enable anything.
de_spec() {
    case "$1:$2" in
        cosmic:pacman) echo "cosmic|cosmic-greeter.service" ;;
        cosmic:dnf)    echo "@cosmic-desktop|cosmic-greeter.service" ;;
        cosmic:apt)    echo "cosmic-session|" ;;
        cosmic:zypper) echo "pattern:cosmic|" ;;
        cosmic:apk)    echo "cosmic|" ;;
        cosmic:xbps)   echo "cosmic|" ;;

        gnome:pacman)  echo "gnome gdm|gdm.service" ;;
        gnome:dnf)     echo "@gnome-desktop|gdm.service" ;;
        gnome:apt)     echo "gnome-core gdm3|gdm3.service" ;;
        gnome:zypper)  echo "pattern:gnome|" ;;
        gnome:apk)     echo "gnome gdm|" ;;
        gnome:xbps)    echo "gnome gdm|" ;;

        plasma:pacman) echo "plasma sddm|sddm.service" ;;
        plasma:dnf)    echo "@kde-desktop|sddm.service" ;;
        plasma:apt)    echo "kde-plasma-desktop sddm|sddm.service" ;;
        plasma:zypper) echo "pattern:kde|" ;;
        plasma:apk)    echo "plasma-desktop sddm|" ;;
        plasma:xbps)   echo "kde5|" ;;

        xfce:pacman)   echo "xfce4 xfce4-goodies lightdm lightdm-gtk-greeter|lightdm.service" ;;
        xfce:dnf)      echo "@xfce-desktop|lightdm.service" ;;
        xfce:apt)      echo "xfce4 lightdm|lightdm.service" ;;
        xfce:zypper)   echo "pattern:xfce|" ;;
        xfce:apk)      echo "xfce4 lightdm|" ;;
        xfce:xbps)     echo "xfce4 lightdm|" ;;

        *) return 1 ;;
    esac
}

de_run_install() {
    local pm="$1"
    local target="$2"

    # shellcheck disable=SC2086
    case "$pm" in
        apt) backend_run_root apt-get install -y $target ;;
        dnf) backend_run_root dnf install -y $target ;;
        pacman) backend_run_root pacman -S --noconfirm $target ;;
        zypper)
            case "$target" in
                pattern:*) backend_run_root zypper --non-interactive install -t pattern "${target#pattern:}" ;;
                *) backend_run_root zypper --non-interactive install $target ;;
            esac
            ;;
        apk) backend_run_root apk add $target ;;
        xbps) backend_run_root xbps-install -Sy $target ;;
        *) return 1 ;;
    esac
}

de_native_install() {
    local de="$1"
    local pm="$2"
    local spec target dm

    spec="$(de_spec "$de" "$pm")" \
        || die "$(de_label "$de") is not mapped for $(native_pm_label "$pm") yet"
    target="${spec%%|*}"
    dm="${spec#*|}"

    native_run_with_error "$pm" "install $(de_label "$de")" \
        run_with_spinner "Installing $(de_label "$de") with $(native_pm_label "$pm")" \
        de_run_install "$pm" "$target"

    if [[ -n "$dm" ]]; then
        if backend_run_root systemctl enable "$dm" 2>/dev/null; then
            printf 'Enabled display manager %s\n' "$dm"
        else
            printf 'Note: could not enable %s automatically. Run: sudo systemctl enable %s\n' "$dm" "$dm"
        fi
    fi

    printf '%s installed. Reboot and choose %s at the login screen.\n' "$(de_label "$de")" "$(de_label "$de")"
}

# NixOS desktops are declarative. We emit the exact configuration.nix lines and
# the rebuild command rather than installing imperatively.
de_nix_instructions() {
    local de="$1"
    local snippet

    case "$de" in
        cosmic)
            snippet='  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;'
            ;;
        gnome)
            snippet='  services.xserver.enable = true;
  services.desktopManager.gnome.enable = true;
  services.displayManager.gdm.enable = true;'
            ;;
        plasma)
            snippet='  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = true;'
            ;;
        xfce)
            snippet='  services.xserver.enable = true;
  services.xserver.desktopManager.xfce.enable = true;
  services.displayManager.lightdm.enable = true;'
            ;;
    esac

    cat <<EOF
On NixOS, desktop environments are declarative -- not installed with nix-env.
Add these lines to /etc/nixos/configuration.nix (inside the { ... } block):

$snippet

Then rebuild and reboot:

  sudo nixos-rebuild switch
  reboot

Choose $(de_label "$de") at the greeter.
EOF
    [[ "$de" == "cosmic" ]] && printf '\nNote: COSMIC needs nixpkgs 25.05 or newer.\n'
}

install_de() {
    local name="$1"
    local requested="${2:-auto}"
    local de pm

    [[ -n "$name" ]] || die "de requires a desktop environment name"
    de="$(de_canonical "$name")" \
        || die "unknown desktop environment: $name (supported: $(de_supported_list))"

    if [[ "$(normalize_provider "$requested")" == "auto" || "$requested" == "native" ]]; then
        pm="$(detect_native_pm)" || die "no supported native package manager was detected"
    elif is_native_provider "$requested"; then
        pm="$(native_pm_resolve "$requested")"
    else
        die "desktop environments install through the native backend (got: $requested)"
    fi

    ensure_provider_available "$pm"

    if [[ "$pm" == "nix" ]]; then
        local anix_de
        if anix_available && anix_de="$(de_anix_name "$de")"; then
            anix_set_desktop "$anix_de"
            printf '%s set as the ANIX desktop.\n' "$(de_label "$de")"
            return
        fi
        de_nix_instructions "$de"
        return
    fi

    de_native_install "$de" "$pm"
}
