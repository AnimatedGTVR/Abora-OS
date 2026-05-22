#!/usr/bin/env bash

flatpak_alias_package() {
    case "${1,,}" in
        zen-browser|zen)        echo "io.github.zen_browser.zen" ;;
        brave)                  echo "com.brave.Browser" ;;
        librewolf)              echo "io.gitlab.librewolf-community.LibreWolf" ;;
        chromium)               echo "org.chromium.Chromium" ;;
        firefox)                echo "org.mozilla.firefox" ;;
        thunderbird)            echo "org.mozilla.Thunderbird" ;;
        bitwarden)              echo "com.bitwarden.desktop" ;;
        libreoffice)            echo "org.libreoffice.LibreOffice" ;;
        obsidian)               echo "md.obsidian.Obsidian" ;;
        signal)                 echo "org.signal.Signal" ;;
        telegram)               echo "org.telegram.desktop" ;;
        discord)                echo "com.discordapp.Discord" ;;
        slack)                  echo "com.slack.Slack" ;;
        element)                echo "im.riot.Riot" ;;
        spotify)                echo "com.spotify.Client" ;;
        audacity)               echo "org.audacityteam.Audacity" ;;
        vlc)                    echo "org.videolan.VLC" ;;
        obs|obs-studio)         echo "com.obsproject.Studio" ;;
        kdenlive)               echo "org.kde.kdenlive" ;;
        handbrake)              echo "fr.handbrake.ghb" ;;
        gimp)                   echo "org.gimp.GIMP" ;;
        inkscape)               echo "org.inkscape.Inkscape" ;;
        krita)                  echo "org.kde.krita" ;;
        blender)                echo "org.blender.Blender" ;;
        darktable)              echo "org.darktable.Darktable" ;;
        vscodium|codium)        echo "com.vscodium.codium" ;;
        zed)                    echo "dev.zed.Zed" ;;
        kate)                   echo "org.kde.kate" ;;
        bottles)                echo "com.usebottles.bottles" ;;
        steam)                  echo "com.valvesoftware.Steam" ;;
        heroic)                 echo "com.heroicgameslauncher.hgl" ;;
        lutris)                 echo "net.lutris.Lutris" ;;
        flameshot)              echo "org.flameshot.Flameshot" ;;
        nextcloud)              echo "com.nextcloud.desktopclient.nextcloud" ;;
        *)                      echo "$1" ;;
    esac
}

package_in_flatpak() {
    local resolved
    resolved="$(flatpak_alias_package "$1")"
    backend_run flatpak info "$resolved" >/dev/null 2>&1
}

flatpak_has_remote() {
    backend_run flatpak remotes --columns=name 2>/dev/null | grep -Fx "$1" >/dev/null 2>&1
}

install_flatpak() {
    local package resolved
    package="$1"
    resolved="$(flatpak_alias_package "$package")"

    if [[ "$resolved" == */* ]]; then
        local remote ref
        remote="${resolved%%/*}"
        ref="${resolved#*/}"
        run_with_spinner "Installing $ref from $remote" backend_run flatpak install -y "$remote" "$ref"
        return
    fi

    if run_with_spinner "Installing $resolved with Flatpak" backend_run flatpak install -y "$resolved"; then
        return
    fi

    if flatpak_has_remote flathub; then
        run_with_spinner "Retrying $resolved from Flathub" backend_run flatpak install -y flathub "$resolved"
        return
    fi

    die "flatpak install failed for $resolved"
}

flatpak_search() {
    backend_run flatpak search "$1"
}

flatpak_remove() {
    local resolved
    resolved="$(flatpak_alias_package "$1")"
    run_with_spinner "Removing $resolved from Flatpak" backend_run flatpak uninstall -y "$resolved"
}

flatpak_list() {
    backend_run flatpak list --app
}

flatpak_run() {
    local resolved
    resolved="$(flatpak_alias_package "$1")"
    backend_exec flatpak run "$resolved"
}

flatpak_update() {
    run_with_spinner "Updating Flatpak packages" backend_run flatpak update -y
}
