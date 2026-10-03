#!/usr/bin/env python3
"""Build a standalone ANIX tarball for non-NixOS/non-Abora users.

The archive is a self-contained bin/ + share/ tree with its own install.sh, so
`anix` and its docs/languages bundle work outside the Abora ISO entirely (the
generated bin/anix wrapper sets ANIX_* env vars pointing at the bundled
share/anix/ paths instead of relying on /etc/abora). TinyPM is a separate Rust
CLI distributed through its own release archives, not bundled here.

The bundled bin/anix and install.sh stay shell for now because they launch
anix.sh, which is still Bash; they move when ANIX does.

Writes out/packages/anix-<anix-tag>-abora-<abora-tag>.tar.gz and prints its path.

Environment overrides (empty counts as unset):
  ABORA_OUT_DIR      output root (default <repo>/out)
  ABORA_PACKAGE_DIR  default $ABORA_OUT_DIR/packages
  ABORA_VERSION_ID   Abora version instead of VERSION
"""

from __future__ import annotations

import sys
from pathlib import Path

from abora_release import abora_version_tag, component_tag, env, repo_root
from tarball import Entry, tree_entries, write_tar_gz

EXCLUDE = (".git", "*.swp", "*.tmp")

# (repo path, path under anix/share/anix/, mode)
REQUIRED_FILES = (
    ("scripts/anix.sh", "anix.sh", 0o755),
    ("scripts/abora-ui.sh", "abora-ui.sh", 0o644),
    ("nix/modules/anix.nix", "anix-module.nix", 0o644),
    ("docs/wiki/ANIX-V1.md", "docs/wiki/ANIX-V1.md", 0o644),
    ("docs/wiki/TinyPM.md", "docs/wiki/TinyPM.md", 0o644),
    ("docs/wiki/Abora-Tools.md", "docs/wiki/Abora-Tools.md", 0o644),
    ("docs/wiki/Recovery.md", "docs/wiki/Recovery.md", 0o644),
    ("docs/wiki/ANIX-V2-Languages.md", "docs/wiki/ANIX-V2-Languages.md", 0o644),
    ("docs/wiki/Abora-Gaming.md", "docs/wiki/Abora-Gaming.md", 0o644),
)

ANIX_WRAPPER = """\
#!/usr/bin/env bash
set -euo pipefail

bin_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
prefix="$(CDPATH= cd -- "$bin_dir/.." && pwd)"
share_dir="$prefix/share/anix"

# anix.sh reads ABORA_UI_LIB (not a per-script ANIX_-prefixed name -- every
# script in this repo shares that one convention). Harmless as an unset var
# in practice, since anix.sh's own fallback ($script_dir/abora-ui.sh)
# always resolves correctly here anyway (anix.sh and abora-ui.sh are
# always installed side by side), but naming it correctly avoids relying
# on that coincidence.
export ABORA_UI_LIB="$share_dir/abora-ui.sh"
export ANIX_DOCS_DIR="$share_dir/docs/wiki"
export ANIX_SYSTEM_LANGUAGE_DIR="$share_dir/languages"
export ANIX_WALLPAPER_DIR="$share_dir/wallpapers"
export ANIX_SOUND_FILE="$share_dir/effects/v3StartingAbora.mp3"
export PATH="$share_dir/tools:$PATH"

exec bash "$share_dir/anix.sh" "$@"
"""

INSTALL_SCRIPT = """\
#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
prefix="${PREFIX:-$HOME/.local}"

mkdir -p "$prefix/bin" "$prefix/share/anix"
install -Dm0755 "$script_dir/bin/anix" "$prefix/bin/anix"
cp -a "$script_dir/share/anix/." "$prefix/share/anix/"

printf 'Installed ANIX into %s\\n' "$prefix"
printf 'Add %s/bin to PATH if needed, then run: anix --help\\n' "$prefix"
printf 'For NixOS flakes, import the module from: %s/share/anix/anix-module.nix\\n' "$prefix"
"""

README = """\
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
- bundled ANIX v2 language manifests
- bundled ModuCPP ANIX adapter helper

TinyPM is a separate Rust CLI (`tinypm`/`grab`) with its own release
archives -- see the TinyPM docs bundled here (`share/anix/docs/wiki/TinyPM.md`)
for how to install it alongside ANIX.

## Flake Usage

With this repository directly:

```nix
{
  inputs.abora.url = "github:AnimatedGTVR/Abora-OS";

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
"""


def main() -> int:
    repo = repo_root(__file__)
    out_dir = Path(env("ABORA_OUT_DIR") or repo / "out")
    package_dir = Path(env("ABORA_PACKAGE_DIR") or out_dir / "packages")

    version_tag = abora_version_tag(repo, env("ABORA_VERSION_ID"))
    anix_tag = component_tag(repo / "scripts/anix.sh", r"^anix_version=")

    for source, _, _ in REQUIRED_FILES:
        if not (repo / source).is_file():
            print(f"ANIX package source file not found: {repo / source}", file=sys.stderr)
            return 1

    share = "anix/share/anix"
    entries = [
        Entry("anix"),
        Entry("anix/bin"),
        Entry("anix/bin/anix", mode=0o755, data=ANIX_WRAPPER.encode()),
        Entry("anix/install.sh", mode=0o755, data=INSTALL_SCRIPT.encode()),
        Entry("anix/README.md", mode=0o644, data=README.encode()),
        Entry("anix/share"),
        Entry(share),
        Entry(f"{share}/docs"),
        Entry(f"{share}/docs/wiki"),
        Entry(f"{share}/languages"),
        Entry(f"{share}/tools"),
    ]
    entries += [Entry(f"{share}/{target}", repo / source, mode) for source, target, mode in REQUIRED_FILES]

    languages = repo / "assets/anix-languages"
    if languages.is_dir():
        entries += tree_entries(languages, f"{share}/languages")

    moducpp = repo / "tools/moducpp-anix"
    if moducpp.is_file():
        entries.append(Entry(f"{share}/tools/moducpp-anix", moducpp, 0o755))

    wallpapers = repo / "assets/wallpapers/collection"
    if wallpapers.is_dir():
        entries.append(Entry(f"{share}/wallpapers"))
        entries += tree_entries(wallpapers, f"{share}/wallpapers")

    sound = repo / "assets/Effects/v3StartingAbora.mp3"
    if sound.is_file():
        entries.append(Entry(f"{share}/effects"))
        entries.append(Entry(f"{share}/effects/v3StartingAbora.mp3", sound, 0o644))

    package_dir.mkdir(parents=True, exist_ok=True)
    package_path = package_dir / f"anix-{anix_tag}-abora-{version_tag}.tar.gz"
    package_path.unlink(missing_ok=True)
    write_tar_gz(package_path, entries, exclude=EXCLUDE)

    print(package_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
