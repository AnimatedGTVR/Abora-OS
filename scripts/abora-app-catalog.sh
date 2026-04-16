#!/usr/bin/env bash

abora_app_catalog() {
    cat <<'EOF'
firefox|Firefox|firefox|Essentials|Fast web browser for everyday browsing|yes
vlc|VLC|vlc|Essentials|Video and audio player that handles almost anything|yes
mpv|MPV|mpv|Essentials|Lightweight media player for video and audio|yes
libreoffice|LibreOffice|libreoffice-qt6-fresh|Essentials|Office suite for documents, sheets, and slides|yes
thunderbird|Thunderbird|thunderbird|Essentials|Email and calendar client|yes
keepassxc|KeePassXC|keepassxc|Essentials|Offline password manager with browser integration|yes
qbittorrent|qBittorrent|qbittorrent|Essentials|BitTorrent client with a clean interface|no
calibre|Calibre|calibre|Essentials|E-book library manager and reader|no
telegram|Telegram Desktop|telegram-desktop|Social|Cloud messaging app with desktop sync|yes
signal|Signal Desktop|signal-desktop|Social|Private messaging for secure chats|no
element|Element|element-desktop|Social|Matrix chat client for open, federated messaging|no
obs|OBS Studio|obs-studio|Creator|Recording and streaming studio|yes
gimp|GIMP|gimp|Creator|Image editor for photo and graphic work|yes
krita|Krita|krita|Creator|Digital painting and art studio|yes
inkscape|Inkscape|inkscape|Creator|Vector design and illustration app|no
kdenlive|Kdenlive|kdePackages.kdenlive|Creator|Video editor for clips and timelines|no
audacity|Audacity|audacity|Creator|Audio recorder and editor|yes
blender|Blender|blender|Creator|3D modelling, animation, and rendering|no
handbrake|HandBrake|handbrake|Creator|Video converter and transcoder|no
darktable|Darktable|darktable|Creator|RAW photo editor and digital darkroom|no
git|Git|git|Developer|Version control and source history|no
gh|GitHub CLI|gh|Developer|GitHub from the terminal and Abora tools|yes
neovim|Neovim|neovim|Developer|Terminal editor for code and writing|no
helix|Helix|helix|Developer|Modern terminal editor with strong defaults|no
vscodium|VSCodium|vscodium|Developer|Graphical code editor based on VS Code|yes
lapce|Lapce|lapce|Developer|Fast native code editor written in Rust|no
filezilla|FileZilla|filezilla|Developer|FTP and SFTP file transfer client|no
remmina|Remmina|remmina|Developer|Remote desktop client for RDP, VNC, and SSH|no
EOF
}

abora_catalog_entry() {
    local wanted_id="$1"
    local app_id=""
    local app_name=""
    local app_expr=""
    local app_group=""
    local app_description=""
    local app_favorite=""

    while IFS='|' read -r app_id app_name app_expr app_group app_description app_favorite; do
        [[ "$app_id" == "$wanted_id" ]] || continue
        printf '%s|%s|%s|%s|%s|%s\n' \
            "$app_id" "$app_name" "$app_expr" "$app_group" "$app_description" "$app_favorite"
        return 0
    done < <(abora_app_catalog)

    return 1
}

abora_catalog_has_app() {
    abora_catalog_entry "$1" >/dev/null 2>&1
}

abora_catalog_name() {
    local record=""
    record="$(abora_catalog_entry "$1")" || return 1
    printf '%s\n' "${record#*|}" | cut -d'|' -f1
}

abora_catalog_expr() {
    local record=""
    record="$(abora_catalog_entry "$1")" || return 1
    printf '%s\n' "$record" | cut -d'|' -f3
}

abora_catalog_group() {
    local record=""
    record="$(abora_catalog_entry "$1")" || return 1
    printf '%s\n' "$record" | cut -d'|' -f4
}

abora_catalog_description() {
    local record=""
    record="$(abora_catalog_entry "$1")" || return 1
    printf '%s\n' "$record" | cut -d'|' -f5
}

abora_catalog_is_favorite() {
    local record=""
    record="$(abora_catalog_entry "$1")" || return 1
    [[ "$(printf '%s\n' "$record" | cut -d'|' -f6)" == "yes" ]]
}

abora_catalog_ids() {
    local app_id=""
    local rest=""

    while IFS='|' read -r app_id rest; do
        printf '%s\n' "$app_id"
    done < <(abora_app_catalog)
}

abora_catalog_bundle_ids() {
    local bundle="${1,,}"
    local app_id=""
    local app_name=""
    local app_expr=""
    local app_group=""
    local app_description=""
    local app_favorite=""

    while IFS='|' read -r app_id app_name app_expr app_group app_description app_favorite; do
        case "$bundle" in
            favorites)
                [[ "$app_favorite" == "yes" ]] || continue
                ;;
            essentials | social | creator | developer)
                [[ "${app_group,,}" == "$bundle" ]] || continue
                ;;
            *)
                return 1
                ;;
        esac
        printf '%s\n' "$app_id"
    done < <(abora_app_catalog)
}
