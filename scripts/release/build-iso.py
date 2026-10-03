#!/usr/bin/env python3
"""Build Abora ISO(s) with Nix and copy them into out/iso/.

Environment overrides (empty counts as unset):
  ABORA_EDITION      cosmic (default), hyprland, gnome, kde, other, or all
  ABORA_OUT_DIR      output root (default <repo>/out)
  ABORA_ISO_DIR      default $ABORA_OUT_DIR/iso
  ABORA_NIX_OUT_DIR  where Nix result links go (default $ABORA_OUT_DIR/nix)
  ABORA_VERSION_ID   Abora version instead of VERSION
  NIX_CONFIG         default enables nix-command and flakes

Each ISO is named abora-<edition>-<YYYY.MM.DD>-x86_64-<tag>.iso; older ISOs of
the same edition and tag are replaced. A cosmic build also writes the
pre-multi-edition name abora-<date>-x86_64-<tag>.iso.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from abora_release import abora_version_tag, env, repo_root

EDITIONS = ("cosmic", "hyprland", "gnome", "kde", "other")


class BuildError(Exception):
    pass


def locate_iso(build_link: Path) -> Path | None:
    if build_link.is_file():
        resolved = build_link.resolve()
        if resolved.is_file():
            return resolved
        if build_link.name.endswith(".iso"):
            return build_link
    if build_link.is_dir():
        for current, dirnames, filenames in os.walk(build_link, followlinks=True):
            dirnames.sort()
            for filename in sorted(filenames):
                path = Path(current) / filename
                if filename.endswith(".iso") and path.is_file():
                    return path
    return None


def build_one(repo: Path, edition: str, iso_dir: Path, nix_out_dir: Path, build_date: str, version_tag: str) -> None:
    package = f"iso-{edition}"
    nix_target = f"{repo}#packages.x86_64-linux.{package}"
    build_link = nix_out_dir / f"{package}-result"

    print(f"Building target: {nix_target}", flush=True)
    if build_link.is_symlink() or build_link.is_file():
        build_link.unlink()

    status = subprocess.run(
        [
            "nix", "build", nix_target,
            "--print-build-logs",
            "--show-trace",
            "--out-link", str(build_link),
            "--option", "substituters", "https://cache.nixos.org",
            "--option", "max-jobs", "auto",
            "--cores", "0",
        ]
    ).returncode
    if status != 0:
        raise SystemExit(status)

    if not build_link.exists():
        raise BuildError(f"Nix build completed but output link was not created: {build_link}")

    iso_source = locate_iso(build_link)
    if iso_source is None:
        raise BuildError(f"Unable to locate ISO file in Nix build output: {build_link}")

    prefix = f"abora-{edition}-"
    suffix = f"-{version_tag}.iso"
    for old in iso_dir.iterdir():
        if old.name.startswith(prefix) and old.name.endswith(suffix) and len(old.name) >= len(prefix) + len(suffix):
            old.unlink()
    target = iso_dir / f"abora-{edition}-{build_date}-x86_64-{version_tag}.iso"
    shutil.copyfile(iso_source, target)
    print(f"ISO output: {target}", flush=True)


def main() -> int:
    repo = repo_root(__file__)
    out_dir = Path(env("ABORA_OUT_DIR") or repo / "out")
    iso_dir = Path(env("ABORA_ISO_DIR") or out_dir / "iso")
    nix_out_dir = Path(env("ABORA_NIX_OUT_DIR") or out_dir / "nix")
    build_date = datetime.now().strftime("%Y.%m.%d")
    edition = env("ABORA_EDITION") or "cosmic"

    if not shutil.which("nix"):
        print("nix command not found. Install Nix with flakes support first.", file=sys.stderr)
        return 1

    version_tag = abora_version_tag(repo, env("ABORA_VERSION_ID"))
    iso_dir.mkdir(parents=True, exist_ok=True)
    nix_out_dir.mkdir(parents=True, exist_ok=True)
    os.environ["NIX_CONFIG"] = env("NIX_CONFIG") or "experimental-features = nix-command flakes"

    if edition == "all":
        targets = EDITIONS
    elif edition in EDITIONS:
        targets = (edition,)
    else:
        print(f"Unsupported ABORA_EDITION: {edition}", file=sys.stderr)
        print(f"Supported editions: {' '.join(EDITIONS)} all", file=sys.stderr)
        return 1

    try:
        for name in targets:
            build_one(repo, name, iso_dir, nix_out_dir, build_date, version_tag)
    except BuildError as exc:
        print(exc, file=sys.stderr)
        return 1

    # COSMIC is the single-ISO default `make iso` builds; also drop a copy under
    # the old pre-multi-edition filename (no "-cosmic-" segment) so tooling or
    # docs still expecting that name (from before editions existed) keep working.
    if edition == "cosmic":
        latest = iso_dir / f"abora-cosmic-{build_date}-x86_64-{version_tag}.iso"
        legacy = iso_dir / f"abora-{build_date}-x86_64-{version_tag}.iso"
        if latest.is_file():
            shutil.copyfile(latest, legacy)
            print(f"Legacy ISO output: {legacy}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
