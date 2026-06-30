#!/usr/bin/env bash
set -euo pipefail

config_dir="${ABORA_SYSTEM_CONFIG:-/etc/nixos}"
abora_dir="$config_dir/abora"
mango_dir="$abora_dir/mango"
mango_config="$mango_dir/config.conf"
bad_mango_store='/nix/store/assets/mango/config.conf'

usage() {
    cat <<'EOF'
Usage: abora-repair-flake-purity [--mango]

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
    git -C "$config_dir" add \
        abora/mango/config.conf \
        abora/abora-options.nix \
        abora/installed-base.nix \
        abora/desktops/mangowm.nix \
        2>/dev/null || true
fi

printf 'Abora MangoWM flake purity repair complete.\n'
printf 'Mango config asset: %s\n' "$mango_config"
printf '\nRun:\n'
printf '  sudo nixos-rebuild switch --flake %s#abora\n' "$config_dir"
