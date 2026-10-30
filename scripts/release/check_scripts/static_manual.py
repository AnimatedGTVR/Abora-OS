"""Content checks that need more than a single grep chain (recursive searches, piped greps)."""

from __future__ import annotations

from .core import Check, Context, grep, not_

# Files that quote the patterns they search for, so a recursive search must skip them.
SELF_EXCLUDES = ("--exclude=static_manual.py",)


# Every Abora release codename so far. A shipped file naming any of them with a version other than this
# tree's own (VERSION + abora_release.RELEASE_CODENAME) is the drift that left 4.0 saying 4.1 and 4.1.1
# saying 4.1: the website, ISO, installer and docs disagreeing about which release this is.
CODENAMES = ("Denali", "Everest", "Horizon", "Solstice")
SHIPPED = ("scripts", "nix", ".github")


def branding(ctx: Context) -> None:
    from abora_release import RELEASE_CODENAME, release_short

    short = release_short(ctx.repo)  # "v4.2 Solstice"
    version = short.split()[0][1:]
    old_branding = ctx.grep_output(
        "-RIEn", *SELF_EXCLUDES,
        "2026[.]7[.]27|current stable release|Tracks `main` directly",
        "README.md", "RELEASE_NOTES.md", "docs", "scripts", "nix",
    )
    pattern = r"v[0-9]+[.][0-9]+([.][0-9]+)? (" + "|".join(CODENAMES) + r")\b"
    stale = [
        line for line in ctx.grep_output("-RIEno", *SELF_EXCLUDES, "--exclude-dir=tests", "--exclude-dir=check_scripts", pattern, *SHIPPED).splitlines()
        if not line.endswith(f":{short}")
    ]
    passed = not old_branding and not stale and Check(
        f"runtime: {short} branding is consistent",
        grep("-q", f"Abora OS {short}", "RELEASE_NOTES.md"),
        grep("-q", f"git tag v{version}", "docs/wiki/Release-Guide.md"),
        grep("-q", f"x86_64-v{version}.iso", "RELEASE_NOTES.md"),
        grep("-q", f"SHA256SUMS-v{version}.txt", "RELEASE_NOTES.md"),
        grep("-q", 'abora_release_stage="${ABORA_RELEASE_STAGE:-alpha}"', "scripts/abora-installer.sh"),
        grep("-q", 'abora_release_channel="${ABORA_RELEASE_CHANNEL:-unstable}"', "scripts/abora-installer.sh"),
        grep("-q", f"Abora OS {short}", "scripts/abora-installer.sh"),
        grep("-q", f"ABORA OS  —  {short}", "scripts/abora-boot.sh"),
        grep("-qF", 'os.environ.get("ABORA_DEFAULT_CHANNEL") or "unstable"', "scripts/support/abora-welcome.py"),
        grep("-q", "ABORA_DEFAULT_CHANNEL', 'unstable'", "scripts/abora-welcome-gui.py"),
        grep("-qF", 'os.environ.get("ABORA_DEFAULT_CHANNEL") or "unstable"', "scripts/support/abora-doctor.py"),
        grep("-q", f"{short} alpha default", "docs/wiki/Updating-Abora.md"),
        grep("-qF", f'os.environ.get("ABORA_RELEASE_NAME") or "Abora OS {short}"', "scripts/support/abora-support-report.py"),
        grep("-q", f"printf '{short}'", "scripts/abora-ui.sh"),
        grep("-q", f'RELEASE_SHORT = "{short}"', "scripts/check-desktops.py"),
        grep("-q", f'PRETTY_NAME = "Abora OS {short}"', "nix/profiles/live.nix"),
        grep("-q", f'PRETTY_NAME = "Abora OS {short}"', "nix/modules/installed-base.nix"),
        grep("-q", f'VERSION = "{short}"', "nix/profiles/live.nix"),
        grep("-q", f'VERSION_ID = "{version}"', "nix/modules/installed-base.nix"),
        grep("-q", f'VERSION_ID = "{version}"', "nix/profiles/live.nix"),
        grep("-q", f'VERSION_CODENAME = "{RELEASE_CODENAME.lower()}"', "nix/modules/installed-base.nix"),
        grep("-q", f'VERSION_CODENAME = "{RELEASE_CODENAME.lower()}"', "nix/profiles/live.nix"),
        grep("-q", f'DISTRIB_CODENAME = "{RELEASE_CODENAME.lower()}"', "nix/modules/installed-base.nix"),
        grep("-q", f'DISTRIB_CODENAME = "{RELEASE_CODENAME.lower()}"', "nix/profiles/live.nix"),
        grep("-q", f'title="Abora OS {short} (${{tag}})"', ".github/workflows/release-iso.yml"),
    ).conditions_hold(ctx)
    ctx.result(passed, f"runtime: {short} branding is consistent (VERSION + {RELEASE_CODENAME})")
    if not passed and old_branding:
        ctx.detail(old_branding)
    if stale:
        ctx.detail("names another release:\n" + "\n".join(stale))


def pure_eval(ctx: Context) -> None:
    # Committed Nix and installer templates must never hardcode /nix/store paths:
    # flakes may only access files that are part of the flake input or copied into
    # the installed /etc/nixos tree.
    matches = ctx.grep_output(
        "-RIEn", *SELF_EXCLUDES,
        "--exclude=abora-repair-flake-purity.sh", "--exclude=repair-flake-purity.test.sh",
        '(/nix/store/assets|source[[:space:]]*=[[:space:]]*"?/nix/store|builtins\\.storePath)',
        "flake.nix", "nix", "scripts",
    )
    if matches:
        ctx.fail("pure-eval: forbidden hardcoded /nix/store path or builtins.storePath found")
        ctx.detail(matches)
    else:
        ctx.ok("pure-eval: no hardcoded /nix/store paths in Nix/templates")

    mango = ctx.grep_output(
        "-RIEn",
        "(/nix/store/assets|(\\.\\./\\.\\./|\\.\\./\\.\\./\\.\\./)assets/mango/config\\.conf)",
        "nix/modules/abora-options.nix", "nix/modules/installed-base.nix",
    )
    if mango:
        ctx.fail("pure-eval: installed Mango modules contain repo-relative asset paths")
        ctx.detail(mango)
    else:
        ctx.ok("pure-eval: installed Mango modules use installed asset paths")


def updater_sync(ctx: Context) -> None:
    Check(
        "runtime: updater syncs Abora Gaming command",
        grep("-q", "release_has_gaming_layer", "scripts/abora-update.sh"),
        grep("-q", '! version_lt "$(tag_base_version "$selected_ref")" "4.0"', "scripts/abora-update.sh"),
        lambda c: c.grep(
            "-q", '! version_lt "$(tag_base_version "$selected_ref")" "4.0"',
            stdin=c.grep_output("-A5", "release_has_welcome_config_gui", "scripts/abora-update.sh"),
        ),
        grep("-q", 'repo_git_url="${ABORA_REPO_GIT_URL:-https://github.com/Abora-OS/Abora-OS.git}"', "scripts/abora-update.sh"),
        grep("-q", "https://github.com/AnimatedGTVR/Abora-OS.git", "scripts/abora-update.sh"),
        not_(grep("-rqE", "AboraProject|AboraOS-Project", "scripts/support", "scripts/install", "scripts/apps", "nix")),
        not_(grep(
            "-RIE", *SELF_EXCLUDES, "-q",
            "github(:|\\.com/)abora-os/abora-os|abora-os/abora-os|abora-os[.]git",
            "README.md", "RELEASE_NOTES.md", "DISCORD_CHANGELOG.md", "docs", "scripts", "nix", "flake.nix", "Makefile",
        )),
        grep("-q", "scripts/abora-build.sh", "scripts/abora-update.sh"),
        grep("-q", 'copy_upstream_file "$upstream_dir/scripts/abora-build.sh" "$abora_dir/build.sh"', "scripts/abora-update.sh"),
        grep("-q", "scripts/abora-adopt-nixos.sh", "scripts/abora-update.sh"),
        grep("-q", 'copy_upstream_file "$upstream_dir/scripts/abora-adopt-nixos.sh" "$abora_dir/adopt-nixos.sh"', "scripts/abora-update.sh"),
        grep("-q", "scripts/abora-gaming.sh", "scripts/abora-update.sh"),
        grep("-q", "scripts/abora-custom-packages.sh", "scripts/abora-update.sh"),
        grep("-q", "scripts/abora-dotfiles-import.sh", "scripts/abora-update.sh"),
        grep("-q", "assets/Abora-LOGO.png", "scripts/abora-update.sh"),
        grep("-q", "assets/Abora-Text.png", "scripts/abora-update.sh"),
        grep("-q", 'cp /etc/abora/Abora-LOGO.png "${root}/etc/nixos/abora/Abora-LOGO.png"', "scripts/abora-installer.sh"),
        grep("-q", 'cp /etc/abora/Abora-Text.png "${root}/etc/nixos/abora/Abora-Text.png"', "scripts/abora-installer.sh"),
        grep("-q", '"abora/Abora-LOGO.png".source = ../../assets/Abora-LOGO.png', "nix/profiles/live.nix"),
        grep("-q", '"abora/Abora-Text.png".source = ../../assets/Abora-Text.png', "nix/profiles/live.nix"),
        grep("-q", "docs/wiki/ANIX-V2-Languages.md", "scripts/abora-update.sh"),
        grep("-q", "docs/wiki/Updating-Abora.md", "scripts/abora-update.sh"),
        grep("-q", "Check your internet connection, then run: sudo abora update", "scripts/abora-update.sh"),
        grep("-q", "sudo ABORA_REPO_REF=edge abora update", "docs/wiki/Updating-Abora.md"),
        grep("-q", 'copy_upstream_file "$upstream_dir/scripts/abora-gaming.sh" "$abora_dir/gaming.sh"', "scripts/abora-update.sh"),
        grep("-q", 'copy_upstream_file "$upstream_dir/scripts/abora-custom-packages.sh" "$abora_dir/custom-packages.sh"', "scripts/abora-update.sh"),
        grep("-q", 'copy_upstream_file "$upstream_dir/scripts/abora-dotfiles-import.sh" "$abora_dir/dotfiles-import.sh"', "scripts/abora-update.sh"),
        grep("-q", 'copy_upstream_file "$upstream_dir/assets/Abora-LOGO.png" "$abora_dir/Abora-LOGO.png"', "scripts/abora-update.sh"),
        grep("-q", 'copy_upstream_file "$upstream_dir/assets/Abora-Text.png" "$abora_dir/Abora-Text.png"', "scripts/abora-update.sh"),
        grep("-q", 'copy_upstream_dir "$upstream_dir/docs" "$abora_dir/docs"', "scripts/abora-update.sh"),
    ).run(ctx)


def run(ctx: Context) -> None:
    branding(ctx)
    pure_eval(ctx)
    updater_sync(ctx)
