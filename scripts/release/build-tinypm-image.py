#!/usr/bin/env python3
"""Build a container image of TinyPM from packaging/tinypm/Dockerfile.

A third distribution channel alongside the Nix package (nix/pkgs/anix.nix has
its own TinyPM wiring) and the standalone tarball (package-tinypm.py), for
running TinyPM outside any NixOS/Abora system entirely.

Usage: build-tinypm-image.py [image-name]   (or IMAGE_NAME=...)
"""

from __future__ import annotations

import subprocess
import sys

from abora_release import env, first_quoted_value, read_version, repo_root, sanitize

TINYPM_VERSION_LINE = r"^version\s*="


def main() -> int:
    repo = repo_root(__file__)
    abora_version = sanitize(read_version(repo)) or "unknown"
    # The image uses bare versions ("0.8.1-alpha"), not "v"-prefixed tags.
    tinypm_version = sanitize(first_quoted_value(repo / "vendor/tinypm/Cargo.toml", TINYPM_VERSION_LINE) or "unknown") or "unknown"

    image_name = (sys.argv[1] if len(sys.argv) > 1 else None) or env("IMAGE_NAME") or f"abora-tinypm:{tinypm_version}-abora-{abora_version}"

    status = subprocess.run(
        [
            "docker", "build",
            "--file", "packaging/tinypm/Dockerfile",
            "--build-arg", f"TINYPM_VERSION={tinypm_version}",
            "--build-arg", f"ABORA_VERSION={abora_version}",
            "--build-arg", "IMAGE_SOURCE=https://github.com/AnimatedGTVR/Abora-OS",
            "--tag", image_name,
            "vendor/tinypm",
        ],
        cwd=repo,
    ).returncode
    if status != 0:
        return status

    print(f"Built TinyPM image: {image_name}")
    print(f"Try it with: docker run --rm {image_name} tinypm --version")
    return 0


if __name__ == "__main__":
    sys.exit(main())
