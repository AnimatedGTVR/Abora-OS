#!/usr/bin/env python3
"""Build vendor/tinypm/ and package tinypm + grab with their docs into a release tarball.

Writes out/packages/tinypm-<tinypm-tag>-abora-<abora-tag>.tar.gz and prints its path.

Environment overrides (empty counts as unset):
  ABORA_OUT_DIR      output root (default <repo>/out)
  ABORA_PACKAGE_DIR  default $ABORA_OUT_DIR/packages
  ABORA_VERSION_ID   Abora version instead of VERSION
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from abora_release import abora_version_tag, component_tag, env, repo_root
from tarball import Entry, write_tar_gz

BINARIES = ("tinypm", "grab")
DOCS = ("README.md", "LICENSE", "CHANGELOG.md")


def main() -> int:
    repo = repo_root(__file__)
    out_dir = Path(env("ABORA_OUT_DIR") or repo / "out")
    package_dir = Path(env("ABORA_PACKAGE_DIR") or out_dir / "packages")
    tinypm_dir = repo / "vendor/tinypm"

    if not tinypm_dir.is_dir():
        print(f"TinyPM source directory not found: {tinypm_dir}", file=sys.stderr)
        return 1

    version_tag = abora_version_tag(repo, env("ABORA_VERSION_ID"))
    tinypm_tag = component_tag(tinypm_dir / "Cargo.toml", r"^version\s*=")

    status = subprocess.run(["cargo", "build", "--release", "--locked"], cwd=tinypm_dir).returncode
    if status != 0:
        return status

    release_dir = tinypm_dir / "target/release"
    for binary in BINARIES:
        path = release_dir / binary
        if not (path.is_file() and os.access(path, os.X_OK)):
            print(f"TinyPM release build did not produce {path}", file=sys.stderr)
            return 1

    entries = [Entry("tinypm", None, 0o755)]
    entries += [Entry(f"tinypm/{binary}", release_dir / binary, 0o755) for binary in BINARIES]
    entries += [Entry(f"tinypm/{doc}", tinypm_dir / doc, 0o644) for doc in DOCS if (tinypm_dir / doc).is_file()]

    package_dir.mkdir(parents=True, exist_ok=True)
    package_path = package_dir / f"tinypm-{tinypm_tag}-abora-{version_tag}.tar.gz"
    package_path.unlink(missing_ok=True)
    write_tar_gz(package_path, entries)

    print(package_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
