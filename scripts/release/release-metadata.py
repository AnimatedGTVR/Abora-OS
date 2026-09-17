#!/usr/bin/env python3
"""Generate release checksums, manifest and notes into out/release/.

Reads ISOs from out/iso/ and TinyPM/ANIX packages from out/packages/, writes
SHA256SUMS-<tag>.txt, RELEASE_MANIFEST-<tag>.txt and RELEASE_NOTES-<tag>.md,
then prints the version tag.

Environment overrides (empty counts as unset):
  ABORA_RELEASE_NAME   release title (default "Abora OS v4 Everest")
  ABORA_OUT_DIR        output root (default <repo>/out)
  ABORA_ISO_DIR        default $ABORA_OUT_DIR/iso
  ABORA_PACKAGE_DIR    default $ABORA_OUT_DIR/packages
  ABORA_RELEASE_DIR    default $ABORA_OUT_DIR/release
  ABORA_RELEASE_STAMP  ISO date stamp to publish (default: today, UTC). Without
                       it, the newest stamp among local ISOs for this version
                       is used when none match today.
"""

from __future__ import annotations

import hashlib
import math
import re
import sys
from datetime import datetime, timezone
from fractions import Fraction
from pathlib import Path

from abora_release import as_tag, env, repo_root, sanitize

DEFAULT_RELEASE_NAME = "Abora OS v4 Everest"
IEC_UNITS = ("K", "M", "G", "T", "P", "E", "Z", "Y")


def version_tag(repo: Path) -> str:
    # Unlike the packagers, a release needs a real VERSION file: a missing one is an error.
    raw = (repo / "VERSION").read_text(encoding="utf-8").replace("\n", "")
    return as_tag(sanitize(raw) or "dev")


def iec_size(size: int) -> str:
    """Matches `numfmt --to=iec-i --suffix=B`: round away from zero, one decimal below 10."""
    if size < 1024:
        return f"{size}B"

    def round_up(value: Fraction) -> Fraction:
        return Fraction(math.ceil(value * 10), 10) if value < 10 else Fraction(math.ceil(value))

    value = Fraction(size)  # exact: floats drift above 2**53 bytes
    power = 0
    while value >= 1024 and power < len(IEC_UNITS):
        value /= 1024
        power += 1
    rounded = round_up(value)
    if rounded >= 1024 and power < len(IEC_UNITS):
        rounded = round_up(rounded / 1024)
        power += 1
    number = f"{rounded.numerator // rounded.denominator}.{(rounded * 10).numerator % 10}" if rounded < 10 else str(int(rounded))
    return f"{number}{IEC_UNITS[power - 1]}iB"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def visible_files(directory: Path) -> list[Path]:
    """Like a shell `*` glob: non-hidden entries, sorted; missing directory means none."""
    try:
        entries = sorted(directory.iterdir())
    except (FileNotFoundError, NotADirectoryError):
        return []
    return [p for p in entries if not p.name.startswith(".")]


def iso_files(iso_dir: Path, stamp: str, tag: str) -> list[Path]:
    """Files named *<stamp>*-x86_64-<tag>.iso."""
    suffix = f"-x86_64-{tag}.iso"
    return [p for p in visible_files(iso_dir) if p.name.endswith(suffix) and stamp in p.name[: -len(suffix)]]


def newest_iso_stamp(iso_dir: Path, tag: str) -> str | None:
    pattern = re.compile(rf".*-([0-9]{{4}}\.[0-9]{{2}}\.[0-9]{{2}})-x86_64-{re.escape(tag)}\.iso$")
    stamps = [m.group(1) for p in visible_files(iso_dir) if (m := pattern.match(p.name))]
    return max(stamps) if stamps else None  # fixed-width dates: string order is date order


def package_files(package_dir: Path, tag: str) -> list[Path]:
    found = []
    for name in ("tinypm", "anix"):
        pattern = re.compile(rf"{name}-.*-abora-{re.escape(tag)}\.tar\.gz")
        found += [p for p in visible_files(package_dir) if pattern.fullmatch(p.name)]
    return found


def main() -> int:
    repo = repo_root(__file__)
    tag = version_tag(repo)
    release_name = env("ABORA_RELEASE_NAME") or DEFAULT_RELEASE_NAME
    out_dir = Path(env("ABORA_OUT_DIR") or repo / "out")
    iso_dir = Path(env("ABORA_ISO_DIR") or out_dir / "iso")
    package_dir = Path(env("ABORA_PACKAGE_DIR") or out_dir / "packages")
    release_dir = Path(env("ABORA_RELEASE_DIR") or out_dir / "release")

    now = datetime.now(timezone.utc)
    generated_at = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    release_date = now.strftime("%Y-%m-%d")
    explicit_stamp = env("ABORA_RELEASE_STAMP")
    stamp = explicit_stamp or now.strftime("%Y.%m.%d")

    release_dir.mkdir(parents=True, exist_ok=True)

    isos = iso_files(iso_dir, stamp, tag)
    if not isos and not explicit_stamp:
        newest = newest_iso_stamp(iso_dir, tag)
        if newest:
            stamp = newest
            isos = iso_files(iso_dir, stamp, tag)
    if not isos:
        print(f"No ISO files found for {stamp} {tag} in: {iso_dir}", file=sys.stderr)
        return 1

    assets = isos + package_files(package_dir, tag)
    checksums = {asset: sha256(asset) for asset in assets}

    checksum_file = f"SHA256SUMS-{tag}.txt"
    manifest_file = f"RELEASE_MANIFEST-{tag}.txt"
    notes_file = f"RELEASE_NOTES-{tag}.md"

    checksum_text = "".join(f"{checksums[a]}  {a.name}\n" for a in assets)
    (release_dir / checksum_file).write_text(checksum_text, encoding="utf-8")

    manifest = [f"{release_name} ({tag}) release manifest", f"Generated: {generated_at}", "", "Assets"]
    for asset in assets:
        size = asset.stat().st_size
        manifest += [f"- {asset.name}", f"  size: {iec_size(size)} ({size} bytes)", f"  sha256: {checksums[asset]}"]
    manifest += ["", "Supporting files", f"- {checksum_file}"]
    (release_dir / manifest_file).write_text("\n".join(manifest) + "\n", encoding="utf-8")

    notes = [f"# {release_name}\n\n", f"_Version tag: {tag}_\n\n", f"_Release date: {release_date} UTC_\n\n", "## Downloads\n\n"]
    notes += [f"- `{asset.name}`\n" for asset in assets]
    notes += [f"- `{checksum_file}`\n", f"- `{manifest_file}`\n\n"]
    notes_source = repo / "RELEASE_NOTES.md"
    if notes_source.is_file():
        # Everything after the source's own title line, which the header above replaces.
        _, newline, body = notes_source.read_text(encoding="utf-8").partition("\n")
        notes += [body if newline else "", "\n"]
    notes += ["## Checksums\n\n```text\n", checksum_text, "```\n"]
    (release_dir / notes_file).write_text("".join(notes), encoding="utf-8")

    print(tag)
    return 0


if __name__ == "__main__":
    sys.exit(main())
