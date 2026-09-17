"""Content checks that need more than a single grep chain (recursive searches, piped greps)."""

from __future__ import annotations

from .core import Check, Context, grep, not_

# Files that quote the patterns they search for, so a recursive search must skip them.
SELF_EXCLUDES = ("--exclude=static_manual.py",)


def branding(ctx: Context) -> None:
    old_branding = ctx.grep_output(
        "-RIEn", *SELF_EXCLUDES,
        "2026[.]7[.]27|current stable release|Tracks `main` directly",
        "README.md", "RELEASE_NOTES.md", "docs", "scripts", "nix",
    )
    passed = not old_branding and Check(
        "runtime: v4 Everest branding is consistent",
        grep("-q", "Abora OS v4 Everest", "RELEASE_NOTES.md"),
        grep("-q", "git tag v4.0", "docs/wiki/Release-Guide.md"),
        grep("-q", "x86_64-v4.0.iso", "RELEASE_NOTES.md"),
        grep("-q", "SHA256SUMS-v4.0.txt", "RELEASE_NOTES.md"),
        grep("-q", 'abora_release_stage="${ABORA_RELEASE_STAGE:-alpha}"', "scripts/abora-installer.sh"),
        grep("-q", 'abora_release_channel="${ABORA_RELEASE_CHANNEL:-unstable}"', "scripts/abora-installer.sh"),
        grep("-q", "Abora OS v4 Everest", "scripts/abora-installer.sh"),
        grep("-q", "ABORA OS  —  v4 Everest", "scripts/abora-boot.sh"),
        grep("-q", "ABORA_DEFAULT_CHANNEL:-unstable", "scripts/abora-welcome.sh"),
        grep("-q", "ABORA_DEFAULT_CHANNEL', 'unstable'", "scripts/abora-welcome-gui.py"),
        grep("-q", "ABORA_DEFAULT_CHANNEL:-unstable", "scripts/abora-doctor.sh"),
        grep("-q", "v4 Everest alpha default", "docs/wiki/Updating-Abora.md"),
        grep("-q", 'release_name="${ABORA_RELEASE_NAME:-Abora OS v4 Everest}"', "scripts/abora-support-report.sh"),
        grep("-q", "printf 'v4 Everest'", "scripts/abora-ui.sh"),
        grep("-q", 'RELEASE_SHORT = "v4 Everest"', "scripts/check-desktops.py"),
        grep("-q", 'PRETTY_NAME = "Abora OS v4 Everest"', "nix/profiles/live.nix"),
        grep("-q", 'PRETTY_NAME = "Abora OS v4 Everest"', "nix/modules/installed-base.nix"),
        grep("-q", 'VERSION = "v4 Everest"', "nix/profiles/live.nix"),
        grep("-q", 'VERSION_ID = "4"', "nix/modules/installed-base.nix"),
    ).conditions_hold(ctx)
    ctx.result(passed, "runtime: v4 Everest branding is consistent")
    if not passed and old_branding:
        ctx.detail(old_branding)


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
        grep("-q", 'repo_git_url="${ABORA_REPO_GIT_URL:-https://github.com/AnimatedGTVR/Abora-OS.git}"', "scripts/abora-update.sh"),
        grep("-q", "https://github.com/AboraProject/Abora-OS.git", "scripts/abora-update.sh"),
        not_(grep(
            "-RIE", *SELF_EXCLUDES, "-q",
            "github(:|\\.com/)AnimatedGTVR/abora-os|AnimatedGTVR/abora-os|abora-os[.]git",
            "README.md", "RELEASE_NOTES.md", "DISCORD_CHANGELOG.md", "docs", "scripts", "nix", "packaging", "flake.nix", "Makefile",
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
        grep("-q", "vendor/modularity", "scripts/abora-update.sh"),
        grep("-q", 'cp -R "$upstream_dir/vendor/modularity" "$abora_dir/vendor/modularity"', "scripts/abora-update.sh"),
        grep("-q", "docs/wiki/ANIX-V2-Languages.md", "scripts/abora-update.sh"),
        grep("-q", "docs/wiki/Updating-Abora.md", "scripts/abora-update.sh"),
        grep("-q", "Check your internet connection, then run: sudo abora update", "scripts/abora-update.sh"),
        grep("-q", "sudo ABORA_REPO_REF=edge abora update", "docs/wiki/Updating-Abora.md"),
        grep("-q", 'copy_upstream_file "$upstream_dir/scripts/abora-gaming.sh" "$abora_dir/gaming.sh"', "scripts/abora-update.sh"),
        grep("-q", 'copy_upstream_file "$upstream_dir/scripts/abora-custom-packages.sh" "$abora_dir/custom-packages.sh"', "scripts/abora-update.sh"),
        grep("-q", 'copy_upstream_file "$upstream_dir/scripts/abora-dotfiles-import.sh" "$abora_dir/dotfiles-import.sh"', "scripts/abora-update.sh"),
        grep("-q", 'copy_upstream_file "$upstream_dir/assets/Abora-LOGO.png" "$abora_dir/Abora-LOGO.png"', "scripts/abora-update.sh"),
        grep("-q", 'copy_upstream_file "$upstream_dir/assets/Abora-Text.png" "$abora_dir/Abora-Text.png"', "scripts/abora-update.sh"),
        grep("-q", 'cp -R "$upstream_dir/docs" "$abora_dir/docs"', "scripts/abora-update.sh"),
    ).run(ctx)


def run(ctx: Context) -> None:
    branding(ctx)
    pure_eval(ctx)
    updater_sync(ctx)
