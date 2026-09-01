#!/usr/bin/env bash
set -euo pipefail

# Standalone version of the same mango-config-path repair that
# abora-installer.sh's install_mango_config_asset/rewrite_installed_mango_config_paths
# and abora-update.sh's counterparts perform inline. Exists as its own script
# (invoked via `abora repair --mango`, and by check-scripts.sh's pure-eval
# test) so a system whose abora-options.nix/installed-base.nix/desktops/*.nix
# still reference a live-ISO /nix/store path (breaking `nix flake` pure
# evaluation) can be fixed after the fact, without needing a full
# reinstall or update.
config_dir="${ABORA_SYSTEM_CONFIG:-/etc/nixos}"
abora_dir="$config_dir/abora"
mango_dir="$abora_dir/mango"
mango_config="$mango_dir/config.conf"
bad_mango_store='/nix/store/assets/mango/config.conf'

usage() {
    cat <<'EOF'
Usage: abora-repair-flake-purity [--mango]
       abora repair --mango

Repairs installed Abora flake paths that can break pure evaluation.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if [[ "$(id -u)" -ne 0 && ( "$config_dir" == "/etc/nixos" || ! -w "$config_dir" ) ]]; then
    exec sudo env ABORA_SYSTEM_CONFIG="$config_dir" bash "$0" "$@"
fi

mkdir -p "$mango_dir"

if [[ ! -f "$mango_config" ]]; then
    for candidate in \
        "$config_dir/.abora-upstream/assets/mango/config.conf" \
        /etc/abora/mango/config.conf \
        "$config_dir/assets/mango/config.conf"; do
        if [[ -f "$candidate" ]]; then
            cp "$candidate" "$mango_config"
            break
        fi
    done
fi

if [[ ! -f "$mango_config" ]]; then
    : > "$mango_config"
fi

rewrite_mango_path() {
    local file="$1"
    local replacement="$2"

    [[ -f "$file" ]] || return 0
    sed -i \
        -e "s|\"${bad_mango_store}\"|${replacement}|g" \
        -e "s|${bad_mango_store}|${replacement}|g" \
        -e "s|../../assets/mango/config\\.conf|${replacement}|g" \
        -e "s|../../../assets/mango/config\\.conf|${replacement}|g" \
        "$file"
}

rewrite_mango_path "$abora_dir/abora-options.nix" './mango/config.conf'
rewrite_mango_path "$abora_dir/installed-base.nix" './mango/config.conf'

if [[ -d "$abora_dir/desktops" ]]; then
    while IFS= read -r -d '' file; do
        rewrite_mango_path "$file" '../mango/config.conf'
    done < <(
        grep -RIlZ \
            -e "$bad_mango_store" \
            -e '../../assets/mango/config.conf' \
            -e '../../../assets/mango/config.conf' \
            "$abora_dir/desktops" 2>/dev/null || true
    )
fi

if git -C "$config_dir" rev-parse --git-dir >/dev/null 2>&1; then
    # One git-add call per path, not a single multi-path call: git add fails
    # (and stages nothing at all, for any of the paths given) the moment one
    # pathspec doesn't match -- and abora/desktops/mangowm.nix doesn't exist
    # on installs from before nix/modules/desktops became its own directory
    # (see release_uses_modern_layout in abora-update.sh). On exactly the
    # legacy installs this script exists to repair, that missing path was
    # silently voiding staging for mango/config.conf too, even when this
    # script had just created it fresh -- leaving a new, untracked file
    # invisible to `nix flake`'s pure evaluation, the very failure mode
    # being repaired.
    for _repair_path in \
        abora/mango/config.conf \
        abora/abora-options.nix \
        abora/installed-base.nix \
        abora/desktops/mangowm.nix; do
        git -C "$config_dir" add "$_repair_path" 2>/dev/null || true
    done
fi

printf 'Abora MangoWM flake purity repair complete.\n'
printf 'Mango config asset: %s\n' "$mango_config"
printf '\nRun:\n'
printf '  sudo abora config apply\n'
printf 'or:\n'
printf '  sudo nixos-rebuild switch --flake %s#abora\n' "$config_dir"
