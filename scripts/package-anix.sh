#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
out_dir="${ABORA_OUT_DIR:-$repo_dir/out}"
package_dir="${ABORA_PACKAGE_DIR:-$out_dir/packages}"
version_id="${ABORA_VERSION_ID:-}"
anix_version=""
stage_dir=""
tmp_dir=""

if [[ -z "$version_id" && -f "$repo_dir/VERSION" ]]; then
  version_id="$(tr -d '\n' < "$repo_dir/VERSION")"
fi

version_id="$(printf '%s' "$version_id" | tr -cd '[:alnum:]._-')"
[[ -n "$version_id" ]] || version_id="dev"
case "$version_id" in
  [Vv]*) version_tag="$version_id" ;;
  *) version_tag="v$version_id" ;;
esac

anix_version="$(
  awk -F'"' '/^anix_version=/{print $2; exit}' "$repo_dir/scripts/anix.sh"
)"
anix_version="$(printf '%s' "${anix_version:-unknown}" | tr -cd '[:alnum:]._-')"
[[ -n "$anix_version" ]] || anix_version="unknown"
case "$anix_version" in
  [Vv]*) anix_tag="$anix_version" ;;
  *) anix_tag="v$anix_version" ;;
esac

mkdir -p "$package_dir"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
stage_dir="$tmp_dir/anix"

mkdir -p \
  "$stage_dir/bin" \
  "$stage_dir/share/anix/docs/wiki" \
  "$stage_dir/share/anix"

install -Dm0755 "$repo_dir/scripts/anix.sh" "$stage_dir/share/anix/anix.sh"
install -Dm0644 "$repo_dir/scripts/abora-ui.sh" "$stage_dir/share/anix/abora-ui.sh"
install -Dm0644 "$repo_dir/nix/modules/anix.nix" "$stage_dir/share/anix/anix-module.nix"
install -Dm0644 "$repo_dir/docs/wiki/ANIX-V1.md" "$stage_dir/share/anix/docs/wiki/ANIX-V1.md"
install -Dm0644 "$repo_dir/docs/wiki/TinyPM-V4.md" "$stage_dir/share/anix/docs/wiki/TinyPM-V4.md"
install -Dm0644 "$repo_dir/docs/wiki/Abora-Tools.md" "$stage_dir/share/anix/docs/wiki/Abora-Tools.md"
install -Dm0644 "$repo_dir/docs/wiki/Recovery.md" "$stage_dir/share/anix/docs/wiki/Recovery.md"

if [[ -d "$repo_dir/vendor/tinypm" ]]; then
  mkdir -p "$stage_dir/share/anix/tinypm"
  cp -a "$repo_dir/vendor/tinypm/." "$stage_dir/share/anix/tinypm/"
fi

if [[ -d "$repo_dir/assets/wallpapers/collection" ]]; then
  mkdir -p "$stage_dir/share/anix/wallpapers"
  cp -a "$repo_dir/assets/wallpapers/collection/." "$stage_dir/share/anix/wallpapers/"
fi

if [[ -f "$repo_dir/assets/Effects/v3StartingAbora.mp3" ]]; then
  mkdir -p "$stage_dir/share/anix/effects"
  install -Dm0644 "$repo_dir/assets/Effects/v3StartingAbora.mp3" \
    "$stage_dir/share/anix/effects/v3StartingAbora.mp3"
fi

cat > "$stage_dir/bin/anix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

bin_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
prefix="$(CDPATH= cd -- "$bin_dir/.." && pwd)"
share_dir="$prefix/share/anix"

export ANIX_UI_LIB="$share_dir/abora-ui.sh"
export ANIX_DOCS_DIR="$share_dir/docs/wiki"
export ANIX_TINYPM_SOURCE="$share_dir/tinypm"
export ANIX_WALLPAPER_DIR="$share_dir/wallpapers"
export ANIX_SOUND_FILE="$share_dir/effects/v3StartingAbora.mp3"

exec bash "$share_dir/anix.sh" "$@"
EOF
chmod +x "$stage_dir/bin/anix"

cat > "$stage_dir/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
prefix="${PREFIX:-$HOME/.local}"

mkdir -p "$prefix/bin" "$prefix/share/anix"
install -Dm0755 "$script_dir/bin/anix" "$prefix/bin/anix"
cp -a "$script_dir/share/anix/." "$prefix/share/anix/"

printf 'Installed ANIX into %s\n' "$prefix"
printf 'Add %s/bin to PATH if needed, then run: anix --help\n' "$prefix"
printf 'For NixOS flakes, import the module from: %s/share/anix/anix-module.nix\n' "$prefix"
EOF
chmod +x "$stage_dir/install.sh"

cat > "$stage_dir/README.md" <<'EOF'
# ANIX

ANIX is a friendly NixOS profile and rebuild helper.

## Quick Install

Run:

```sh
./install.sh
```

This installs:

- `bin/anix`
- `share/anix/anix-module.nix`
- bundled docs
- bundled TinyPM source for `anix tinypm install`

## Flake Usage

With this repository directly:

```nix
{
  inputs.abora.url = "github:AnimatedGTVR/abora-os";

  outputs = { nixpkgs, abora, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        abora.nixosModules.anix
        ({ pkgs, ... }: {
          environment.systemPackages = [ abora.packages.${pkgs.system}.anix ];
        })
      ];
    };
  };
}
```
EOF

package_name="anix-${anix_tag}-abora-${version_tag}.tar.gz"
package_path="$package_dir/$package_name"
rm -f "$package_path"

tar \
  --exclude='.git' \
  --exclude='*.swp' \
  --exclude='*.tmp' \
  -czf "$package_path" \
  -C "$tmp_dir" \
  anix

printf '%s\n' "$package_path"
