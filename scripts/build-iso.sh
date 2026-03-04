#!/usr/bin/env sh
set -eu

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
profile_dir="$repo_dir/distro/archiso"
work_dir="${ABORA_WORK_DIR:-$repo_dir/work}"
out_dir="${ABORA_OUT_DIR:-$repo_dir/out}"
source_wallpaper="$repo_dir/assets/wallpaper.png"
staged_wallpaper_dir="$profile_dir/airootfs/usr/share/wallpapers/Abora"
staged_branding_dir="$profile_dir/airootfs/usr/share/abora"

if ! command -v mkarchiso >/dev/null 2>&1; then
    echo "mkarchiso not found. Install the archiso package first." >&2
    exit 1
fi

if [ ! -f "$source_wallpaper" ]; then
    echo "Missing default wallpaper: $source_wallpaper" >&2
    exit 1
fi

mkdir -p "$work_dir" "$out_dir"
mkdir -p "$staged_wallpaper_dir" "$staged_branding_dir"

cp "$source_wallpaper" "$staged_wallpaper_dir/default.png"
cp "$source_wallpaper" "$staged_branding_dir/default-wallpaper.png"

exec mkarchiso -v -w "$work_dir" -o "$out_dir" "$profile_dir"
