#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$script_dir"
while [[ "$repo_dir" != "/" && ! -f "$repo_dir/flake.nix" ]]; do
    repo_dir="$(dirname "$repo_dir")"
done
[[ -f "$repo_dir/flake.nix" ]] || { echo "Could not find Abora repo root." >&2; exit 1; }
cd "$repo_dir"

# This list mirrors abora-update.sh's required_upstream_paths() for a
# release-tagged checkout (the newest layout, so every conditional
# release_has_*/release_uses_* path there applies). Run this before tagging
# a release: if a file listed here is missing from the checkout, any
# existing installed Abora system that later runs `sudo abora update` against
# this tag will fail validate_upstream_checkout() and refuse to update --
# catching that here, at tag time, is much cheaper than a user hitting it.
required_paths() {
    cat <<'EOF'
VERSION
nix/modules/abora-options.nix
nix/modules/installed-base.nix
nix/modules/anix.nix
nix/modules/desktops
nix/pkgs/mango.nix
nix/pkgs/scenefx-0_5.nix
nix/pkgs/modularity.nix
nix/pkgs/moducpp-anix.nix
nix/pkgs/abora-update-resolver.nix
nix/pkgs/abora-update-resolver-deps.json
nix/pkgs/abora-plan-tool.nix
nix/pkgs/abora-plan-tool-deps.json
scripts/abora-update.sh
scripts/abora-installer.sh
scripts/abora-repair-flake-purity.sh
scripts/abora-ui.sh
scripts/abora-config.sh
scripts/abora.sh
scripts/abora-build.sh
scripts/abora-adopt-nixos.sh
scripts/abora-desktop.sh
scripts/abora-gaming.sh
scripts/abora-welcome-gui.py
scripts/abora-config-gui.py
scripts/abora-gaming-welcome-gui.py
scripts/abora-doctor.sh
scripts/abora-recovery.sh
scripts/abora-welcome.sh
scripts/anix.sh
scripts/abora-app-catalog.sh
scripts/abora-apps.sh
scripts/abora-custom-packages.sh
scripts/abora-support-report.sh
scripts/abora-hardware-test.sh
scripts/abora-desktop-profiles.sh
scripts/abora-session-setup.sh
scripts/abora-dotfiles-import.sh
scripts/abora-theme-sync.sh
scripts/abora-check-full.sh
scripts/abora-setup-launcher.sh
docs/wiki/Abora-Gaming.md
docs/wiki/ANIX-V2-Languages.md
docs/wiki/Updating-Abora.md
tools/moducpp-anix
tools/abora-update-resolver/AboraUpdateResolver.csproj
tools/abora-update-resolver/Program.cs
tools/abora-plan-tool/AboraPlanTool.csproj
tools/abora-plan-tool/Program.cs
assets/mango/config.conf
assets/anix-languages
scripts/abora-setup.desktop
assets/abora-title.txt
assets/Abora-LOGO.png
assets/Abora-Text.png
assets/fastfetch-logo.txt
assets/fastfetch-config.jsonc
assets/bootloader/background.png
assets/bootloader/theme.txt
assets/plymouth/abora.plymouth
assets/plymouth/abora.script
assets/Effects/LaunchingAbora.mp3
assets/wallpapers/collection
assets/wallpapers/collection/aurora-lofoten.jpg
assets/wallpaper-themes
vendor/modularity
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
