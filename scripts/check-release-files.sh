#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_dir"

required_paths() {
    cat <<'EOF'
VERSION
nix/modules/abora-options.nix
nix/modules/installed-base.nix
nix/modules/anix.nix
nix/modules/desktops
nix/pkgs/mango.nix
nix/pkgs/modularity.nix
scripts/abora-update.sh
scripts/abora-installer.sh
scripts/abora-repair-flake-purity.sh
scripts/abora-ui.sh
scripts/abora-config.sh
scripts/abora.sh
scripts/abora-desktop.sh
scripts/abora-doctor.sh
scripts/abora-recovery.sh
scripts/abora-welcome.sh
scripts/anix.sh
scripts/abora-app-catalog.sh
scripts/abora-apps.sh
scripts/abora-support-report.sh
scripts/abora-hardware-test.sh
scripts/abora-desktop-profiles.sh
scripts/abora-session-setup.sh
scripts/abora-theme-sync.sh
assets/mango/config.conf
assets/abora-title.txt
assets/fastfetch-logo.txt
assets/fastfetch-config.jsonc
assets/bootloader/background.png
assets/bootloader/theme.txt
assets/plymouth/abora.plymouth
assets/plymouth/abora.script
assets/Effects/LaunchingAbora.mp3
assets/wallpapers/collection
assets/wallpapers/collection/oceandusk.png
assets/wallpaper-themes
EOF
}

missing=0
while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if [[ ! -e "$path" ]]; then
        printf 'missing required release file: %s\n' "$path" >&2
        missing=1
    fi
done < <(required_paths)

if [[ "$missing" -ne 0 ]]; then
    printf 'Release file check failed. Do not tag or ship this checkout.\n' >&2
    exit 1
fi

printf 'All updater-required release files are present.\n'
