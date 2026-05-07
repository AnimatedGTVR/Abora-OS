#!/usr/bin/env bash

abora_app_catalog() {
    cat <<'EOF'
firefox|Firefox|firefox|Essentials|Fast web browser for everyday browsing|yes
chromium|Chromium|chromium|Essentials|Open-source web browser without Google extras|no
vlc|VLC|vlc|Essentials|Video and audio player that handles almost anything|yes
mpv|MPV|mpv|Essentials|Lightweight media player for video and audio|yes
libreoffice|LibreOffice|libreoffice-qt6-fresh|Essentials|Office suite for documents, sheets, and slides|yes
thunderbird|Thunderbird|thunderbird|Essentials|Email and calendar client|yes
keepassxc|KeePassXC|keepassxc|Essentials|Offline password manager with browser integration|yes
bitwarden|Bitwarden|bitwarden|Essentials|Cloud password manager with cross-device sync|no
qbittorrent|qBittorrent|qbittorrent|Essentials|BitTorrent client with a clean interface|no
calibre|Calibre|calibre|Essentials|E-book library manager and reader|no
telegram|Telegram Desktop|telegram-desktop|Social|Cloud messaging app with desktop sync|yes
signal|Signal Desktop|signal-desktop|Social|Private messaging for secure chats|yes
discord|Discord|discord|Social|Voice, video, and text chat for communities|yes
element|Element|element-desktop|Social|Matrix chat client for open, federated messaging|no
slack|Slack|slack|Social|Team communication and workspace chat|no
zoom|Zoom|zoom-us|Social|Video conferencing and meetings|no
obs|OBS Studio|obs-studio|Creator|Recording and streaming studio|yes
gimp|GIMP|gimp|Creator|Image editor for photo and graphic work|yes
krita|Krita|krita|Creator|Digital painting and art studio|yes
inkscape|Inkscape|inkscape|Creator|Vector design and illustration app|no
kdenlive|Kdenlive|kdePackages.kdenlive|Creator|Video editor for clips and timelines|no
audacity|Audacity|audacity|Creator|Audio recorder and editor|yes
blender|Blender|blender|Creator|3D modelling, animation, and rendering|no
handbrake|HandBrake|handbrake|Creator|Video converter and transcoder|no
darktable|Darktable|darktable|Creator|RAW photo editor and digital darkroom|no
rawtherapee|RawTherapee|rawtherapee|Creator|Free and powerful RAW photo processor|no
git|Git|git|Developer|Version control and source history|no
gh|GitHub CLI|gh|Developer|GitHub from the terminal and Abora tools|yes
neovim|Neovim|neovim|Developer|Terminal editor for code and writing|no
helix|Helix|helix|Developer|Modern terminal editor with strong defaults|no
vscodium|VSCodium|vscodium|Developer|Graphical code editor based on VS Code|yes
zed|Zed|zed-editor|Developer|Fast collaborative code editor|no
lapce|Lapce|lapce|Developer|Fast native code editor written in Rust|no
tmux|tmux|tmux|Developer|Terminal multiplexer for persistent sessions|no
alacritty|Alacritty|alacritty|Developer|Fast GPU-accelerated terminal emulator|no
ghostty|Ghostty|ghostty|Developer|Fast, feature-rich terminal built in Zig|no
lazygit|Lazygit|lazygit|Developer|Terminal UI for git commands|no
docker|Docker|docker|Developer|Container engine for building and running apps|no
filezilla|FileZilla|filezilla|Developer|FTP and SFTP file transfer client|no
remmina|Remmina|remmina|Developer|Remote desktop client for RDP, VNC, and SSH|no
steam|Steam|steam|Gaming|Valve's game store and launcher for Linux|yes
lutris|Lutris|lutris|Gaming|Game manager for native, Wine, and emulated titles|yes
heroic|Heroic Games Launcher|heroic|Gaming|Epic Games and GOG launcher for Linux|yes
bottles|Bottles|bottles|Gaming|Run Windows apps and games via Wine|no
mangohud|MangoHud|mangohud|Gaming|In-game performance overlay for FPS, temps, and more|no
gamemode|GameMode|gamemode|Gaming|Optimise system performance while games are running|no
gparted|GParted|gparted|System|Graphical disk partition editor|no
gnome-disk-utility|Disks|gnome-disk-utility|System|Manage drives, partitions, and disk images|no
timeshift|Timeshift|timeshift|System|System snapshot and restore tool|yes
flameshot|Flameshot|flameshot|System|Screenshot tool with annotation support|yes
btop|btop|btop|System|Beautiful resource monitor for CPU, RAM, and network|yes
missioncenter|Mission Center|mission-center|System|GNOME-style system monitor with graphs|no
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
            essentials | social | creator | developer | gaming | system)
                [[ "${app_group,,}" == "$bundle" ]] || continue
                ;;
            *)
                return 1
                ;;
        esac
        printf '%s\n' "$app_id"
    done < <(abora_app_catalog)
}
