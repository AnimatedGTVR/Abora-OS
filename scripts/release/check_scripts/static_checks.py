"""Static repository content checks.

Each check is a chain of conditions that must all hold, evaluated in order and
stopping at the first that does not (like `&&`). `grep(...)` runs the real grep
with exactly these arguments from the repo root, so patterns keep their POSIX
BRE/ERE meaning. Generated from the former scripts/check-scripts.sh.
"""

from __future__ import annotations

import re

from .core import Check, grep, no_match, not_, test


def _adopt_layout() -> list[str]:
    """Every "source:installed-name" pair abora-adopt-nixos.sh copies."""
    from pathlib import Path
    script = Path(__file__).resolve().parents[3] / "scripts/install/abora-adopt-nixos.sh"
    text = script.read_text(encoding="utf-8")
    pairs = re.findall(r'^copy_if_exists "\$repo_dir/([^"]+)" "\$abora_dir/([^"]+)"$', text, re.M)
    pairs += re.findall(r'^  "([^":]+):([^"]+)"(?: \\|; do)$', text, re.M)
    return [f"{src}:{dest}" for src, dest in pairs]

CHECKS: tuple[Check, ...] = (
    Check(
        'runtime: desktop session setup has a systemd fallback for non-XDG-autostart sessions',
        grep('-q', 'systemd.user.services.abora-session-setup', 'nix/modules/installed-base.nix'),
        grep('-q', 'systemd.user.services.abora-session-setup', 'nix/profiles/live.nix'),
        grep('-q', 'graphical-session.target', 'nix/modules/installed-base.nix'),
        grep('-q', 'graphical-session.target', 'nix/profiles/live.nix'),
        grep('-q', 'ABORA_SESSION_SETUP_WAIT', 'scripts/abora-session-setup.sh'),
    ),
    Check(
        'static: live and installed systems ship wallpaper/theme helper tools',
        grep('-q', 'feh', 'nix/modules/installed-base.nix'),
        grep('-q', 'swaybg', 'nix/modules/installed-base.nix'),
        grep('-q', 'libsForQt5.qt5ct', 'nix/modules/installed-base.nix'),
        grep('-q', 'qt6Packages.qt6ct', 'nix/modules/installed-base.nix'),
        grep('-q', 'feh', 'nix/profiles/live.nix'),
        grep('-q', 'swaybg', 'nix/profiles/live.nix'),
        grep('-q', 'libsForQt5.qt5ct', 'nix/profiles/live.nix'),
        grep('-q', 'qt6Packages.qt6ct', 'nix/profiles/live.nix'),
    ),
    Check(
        'developer doctor documents nixpkgs and daemon/store failures',
        grep('-q', 'ABORA_NIXPKGS_PATH', 'scripts/dev-doctor.py'),
        grep('-q', 'Nix daemon/store', 'scripts/dev-doctor.py'),
        grep('-q', 'ABORA_NIXPKGS_PATH', 'docs/wiki/Building-Abora.md'),
        grep('-q', 'make doctor', 'docs/release-checklist.md'),
        fail_name='developer doctor must document nixpkgs and daemon/store failures',
    ),
    # The target system must be built through the generated flake, but from a
    # stable /tmp copy, then handed to nixos-install with --system. Building
    # directly from /mnt/etc/nixos lets nixos-install/nix lock-file writes
    # mutate the path source while Nix is hashing it, causing NAR hash
    # mismatches in real installs.
    Check(
        'runtime: installer builds the flake before nixos-install instead of hashing mutable /mnt',
        grep('-q', 'nix --extra-experimental-features "nix-command flakes" build', 'scripts/abora-installer.sh'),
        grep('-q', 'nix --extra-experimental-features "nix-command flakes"', 'scripts/abora-installer.sh'),
        grep('-q', 'eval', 'scripts/abora-installer.sh'),
        grep('-q', '--', '--print-build-logs', 'scripts/abora-installer.sh'),
        grep('-q', '--', '--option max-silent-time "${ABORA_INSTALL_NIX_MAX_SILENT_TIME:-900}"', 'scripts/abora-installer.sh'),
        grep('-q', 'ABORA_INSTALL_IDLE_TIMEOUT=900', 'scripts/abora-installer.sh'),
        grep('-q', '#nixosConfigurations.abora.config.system.build.toplevel', 'scripts/abora-installer.sh'),
        grep('-q', 'nixos-install --root /mnt --no-channel-copy --no-root-passwd --system "$system"', 'scripts/abora-installer.sh'),
        grep('-q', 'nixos_install_with_healing "$system_path"', 'scripts/abora-installer.sh'),
        not_(grep('-q', 'nixos-install --root /mnt --no-root-passwd .*--flake "/mnt/etc/nixos#abora"', 'scripts/abora-installer.sh')),
        not_(grep('-q', 'NIX_PATH=nixpkgs=\\${nixpkgs}:nixos-config=/mnt/etc/nixos/configuration.nix', 'scripts/abora-installer.sh')),
    ),
    Check(
        'runtime: installer bounds destructive disk commands and device settling',
        grep('-q', '^disk_engine()', 'scripts/abora-installer.sh'),
        grep('-q', 'disk_engine erase "$disk"', 'scripts/abora-installer.sh'),
        grep('-Fq', 'Command::new("timeout")', 'tools/abora-installer/src/system.rs'),
        grep('-Fq', '"--kill-after=5s"', 'tools/abora-installer/src/system.rs'),
        grep('-Fq', '"udevadm", "settle", "--timeout=15"', 'tools/abora-installer/src/disk.rs'),
        grep('-Fq', 'host.run(30, argv)?', 'tools/abora-installer/src/disk.rs'),
        grep('-Fq', '&["wipefs", "-af", disk]', 'tools/abora-installer/src/disk.rs'),
        grep('-Fq', 'host.run(120, &["mkfs.ext4", "-F", "-L", ROOT_LABEL', 'tools/abora-installer/src/disk.rs'),
    ),
    Check(
        'runtime: installer validates reused ESPs and registers the selected EFI partition',
        grep('-q', '^pub fn check_esp(', 'tools/abora-installer/src/disk.rs'),
        grep('-q', 'MIN_ESP_BYTES: u64 = 536_870_912', 'tools/abora-installer/src/disk.rs'),
        grep('-Fq', 'check_esp(host, esp)?;', 'tools/abora-installer/src/disk.rs'),
        grep('-Fq', 'disk_engine existing "$disk" --root "$target_partition" --esp "$target_esp"', 'scripts/abora-installer.sh'),
        grep('-q', 'lsblk -dnro PARTN "$efi_part"', 'scripts/abora-installer.sh'),
        grep('-q', '--', '--part "$efi_part_num"', 'scripts/abora-installer.sh'),
        not_(grep('-q', '--', '--part 2', 'scripts/abora-installer.sh')),
    ),
    Check(
        'runtime: installer preflight checks release lock and offline package assets',
        grep('-q', 'target-flake.lock', 'nix/profiles/live.nix'),
        grep('-q', '/etc/abora/target-flake.lock', 'scripts/abora-installer.sh'),
        grep('-q', '/etc/abora/plan-tool/Cargo.lock', 'scripts/abora-installer.sh'),
    ),
    Check(
        'runtime: Rust installer front controller is packaged and wired into the live ISO',
        test('-f', 'tools/abora-installer/Cargo.toml'),
        grep('-q', 'mod cli;', 'tools/abora-installer/src/main.rs'),
        grep('-q', 'mod install;', 'tools/abora-installer/src/main.rs'),
        grep('-q', 'mod runner;', 'tools/abora-installer/src/main.rs'),
        grep('-q', 'mod disk;', 'tools/abora-installer/src/main.rs'),
        grep('-q', 'ABORA_INSTALLER_BIN', 'tools/abora-installer/src/runner.rs'),
        grep('-q', 'abora-installer = final.callPackage ./nix/pkgs/abora-installer.nix', 'flake.nix'),
        grep('-q', 'pkgs.abora-installer}/bin/abora-installer --legacy-script /etc/abora/installer.sh', 'nix/profiles/live.nix'),
    ),
    Check(
        'runtime: installer can install a user flake, checked before any disk is touched',
        grep('-q', 'mod flake;', 'tools/abora-installer/src/main.rs'),
        grep('-Fq', 'pub fn judge(', 'tools/abora-installer/src/flake.rs'),
        grep('-Fq', 'extendModules', 'tools/abora-installer/src/flake.rs'),
        grep('-q', '^release_config_source()', 'scripts/abora-installer.sh'),
        grep('-Fq', 'flake_engine judge --uefi', 'scripts/abora-installer.sh'),
        grep('-Fq', 'install_from_flake', 'scripts/abora-installer.sh'),
        grep('-q', 'Installing your own NixOS flake', 'docs/wiki/Installation.md'),
    ),
    Check(
        'static: installs carry no duplicate terminal/browser, and minimal installs stay lean',
        grep('-Fq', 'needsFallbackTerminal = graphical && !(nativeTerminals ? ${desktop});', 'nix/modules/installed-base.nix'),
        grep('-Fq', 'lib.optional (needsFallbackTerminal && !minimal) kdePackages.konsole', 'nix/modules/installed-base.nix'),
        grep('-Fq', 'cp ${wallpaperDir}/${minimalWallpaper} ', 'nix/modules/installed-base.nix'),
        grep('-Fq', 'printf \'%s\\n\' none icewm lxqt xfce lumina niri sway fluxbox openbox', 'scripts/abora-installer.sh'),
        grep('-Fq', 'system=${system.pkgs.stdenv.hostPlatform.system}', 'scripts/abora-installer.sh'),
        not_(grep('-Eq', '^    (firefox|starship|xterm|kdePackages.konsole)$', 'nix/modules/installed-base.nix')),
        grep('-Fq', 'flatpak install --system --noninteractive --or-update flathub ${zenFlatpak}', 'nix/modules/installed-base.nix'),
        grep('-Fq', 'services.flatpak.enable = lib.mkDefault (!minimal);', 'nix/modules/installed-base.nix'),
        grep('-Fq', 'type = lib.types.enum [ "zen" "firefox" "none" ];', 'nix/modules/abora-options.nix'),
        grep('-Fq', 'abora.minimal = {minimal};', 'tools/abora-installer/src/nixcfg.rs'),
    ),
    Check(
        'static: nixosModules.default lays out every file abora adopt-nixos copies',
        grep('-Fq', 'default = import ./nix/modules/abora-flake.nix { inherit self nixpkgs; };', 'flake.nix'),
        grep('-Fq', 'abora.nixosModules.default', 'scripts/abora-adopt-nixos.sh'),
        *(grep('-Fq', f'"{pair}"', 'nix/modules/abora-flake.nix') for pair in _adopt_layout()),
        fail_name='nix/modules/abora-flake.nix must list every file abora-adopt-nixos.sh copies',
    ),
    Check(
        'runtime: grab is packaged and travels with installs and updates',
        grep('-q', 'abora-grab = final.callPackage ./nix/pkgs/abora-grab.nix', 'flake.nix'),
        grep('-q', '"abora/grab".source = ../../tools/abora-grab;', 'nix/profiles/live.nix'),
        grep('-q', 'lib.optional (pkgs ? abora-grab) pkgs.abora-grab', 'nix/modules/installed-base.nix'),
        grep('-q', 'cp -a /etc/abora/grab/. ', 'scripts/abora-installer.sh'),
        grep('-q', 'copy_upstream_dir "$upstream_dir/tools/abora-grab" "$abora_dir/grab"', 'scripts/abora-update.sh'),
        test('-f', 'tools/abora-grab/Cargo.lock'),
        grep('-q', '^## grab', 'docs/wiki/Packages.md'),
    ),
    Check(
        'runtime: the NixOS release (stable or unstable) is chosen in the installer, kept by the updater and switched by anix',
        grep('-Eq', '^nixos-[0-9]{2}\\.[0-9]{2}$', 'NIXOS_STABLE'),
        grep('-q', '"abora/nixos-stable".source = ../../NIXOS_STABLE;', 'nix/profiles/live.nix'),
        grep('-q', '^release_nixos()', 'scripts/abora-installer.sh'),
        grep('-q', 'abora/nixos-release', 'scripts/abora-installer.sh'),
        grep('-q', 'nixos-release', 'scripts/abora-update.sh'),
        grep('-q', '^do_nixos()', 'scripts/anix.sh'),
        grep('-q', '^### Choosing the NixOS release', 'docs/wiki/Installation.md'),
    ),
    Check(
        'runtime: abora.gpu accepts legacy/batch auto values as a no-op',
        grep('-Fq', 'type = lib.types.enum [ "auto" "nouveau" "nvidia" "nvidia-open" "amdgpu" "intel" "none" ];', 'nix/modules/abora-options.nix'),
        grep('-Fq', 'accepts "auto" as a compatibility-safe no-op', 'nix/modules/abora-options.nix'),
    ),
    Check(
        'runtime: release manifest includes dotfiles importer',
        grep('-q', '^scripts/abora-dotfiles-import.sh$', 'scripts/release/release-required-paths.txt'),
    ),
    Check(
        'runtime: abora command routes update, channel, rollback, network, logs, bug-report, dotfiles, gaming, and pre-alpha',
        grep('-q', '^[[:space:]]*rollback)', 'scripts/abora.sh'),
        grep('-q', 'exec abora-update rollback', 'scripts/abora.sh'),
        grep('-q', '^[[:space:]]*channel)', 'scripts/abora.sh'),
        grep('-q', 'handle_channel_command "$@"', 'scripts/abora-update.sh'),
        grep('-q', '^[[:space:]]*dotfiles)', 'scripts/abora.sh'),
        grep('-q', 'exec abora-dotfiles-import', 'scripts/abora.sh'),
        grep('-q', '^[[:space:]]*network)', 'scripts/abora.sh'),
        grep('-q', 'exec abora-recovery network "$@"', 'scripts/abora.sh'),
        grep('-q', 'resolve_helper abora-recovery.sh', 'scripts/abora.sh'),
        grep('-q', 'exec "$helper" network "$@"', 'scripts/abora.sh'),
        grep('-q', '^[[:space:]]*logs|log)', 'scripts/abora.sh'),
        grep('-q', 'show_logs "$@"', 'scripts/abora.sh'),
        grep('-q', 'ABORA_LOG_LINES', 'scripts/abora.sh'),
        grep('-q', '^[[:space:]]*bug-report|bug)', 'scripts/abora.sh'),
        grep('-q', 'show_bug_report_template', 'scripts/abora.sh'),
        grep('-q', 'create_github_issue "$@"', 'scripts/abora.sh'),
        grep('-q', 'gh issue create --repo "$repo"', 'scripts/abora.sh'),
        grep('-q', '^[[:space:]]*build)', 'scripts/abora.sh'),
        grep('-q', 'command -v abora-build', 'scripts/abora.sh'),
        grep('-q', 'resolve_helper abora-build.sh', 'scripts/abora.sh'),
        grep('-q', '^[[:space:]]*adopt-nixos|adopt)', 'scripts/abora.sh'),
        grep('-q', 'resolve_helper abora-adopt-nixos.sh', 'scripts/abora.sh'),
        grep('-q', '^[[:space:]]*gaming)', 'scripts/abora.sh'),
        grep('-q', 'exec abora-gaming', 'scripts/abora.sh'),
        grep('-q', 'resolve_helper abora-gaming.sh', 'scripts/abora.sh'),
        grep('-q', 'exec abora-update channel "$@"', 'scripts/abora.sh'),
        not_(grep('-q', 'ABORA_UPDATE_COMMAND=nixos abora-update channel', 'scripts/abora.sh')),
        grep('-q', 'abora channel set <stable|edge>', 'scripts/abora-update.sh'),
    ),
    Check(
        'runtime: updater can fall back between edge and main branches',
        grep('-q', 'ref_fallback_candidates()', 'scripts/abora-update.sh'),
        grep('-q', 'edge)', 'scripts/abora-update.sh'),
        grep('-q', 'main)', 'scripts/abora-update.sh'),
        grep('-q', "Selected ref '${selected_ref}' was unavailable; using branch fallback '${cloned_ref}'", 'scripts/abora-update.sh'),
        grep('-q', 'sudo ABORA_REPO_REF=<branch> abora update', 'scripts/abora-update.sh'),
    ),
    Check(
        # Greeters show the account description, so a hardcoded "Abora User" made installed systems look like they
        # still used a live-media account (#33).
        'runtime: installed account display name defaults to the chosen username',
        not_(grep('-q', 'description *= *"Abora User"', 'nix/modules/abora-options.nix')),
        grep('-q', 'cfg.user.fullName != null then cfg.user.fullName else cfg.user.name', 'nix/modules/abora-options.nix'),
        fail_name='runtime: installed account display name must default to the chosen username, not "Abora User"',
    ),
    Check(
        # xdg.desktopEntries only exists in home-manager; in a NixOS module it fails evaluation, which a host without
        # nix never notices before the ISO build.
        'runtime: NixOS modules do not use the home-manager xdg.desktopEntries option',
        lambda ctx: not any(
            re.search(r'^[^#]*xdg\.desktopEntries\s*=', f.read_text(errors="replace"), re.M)
            for f in (ctx.repo / "nix").rglob("*.nix")
        ),
        fail_name='runtime: NixOS modules must use pkgs.makeDesktopItem, not xdg.desktopEntries',
    ),
    Check(
        # A tag can be moved upstream, which changes the download while the pinned hash stays: the "source download
        # didn't match the hash Abora pins" install failure. A commit cannot move.
        'runtime: every download in nix/ is pinned to a commit, not a tag or branch',
        lambda ctx: all(
            re.search(r'rev\s*=\s*"[0-9a-f]{40}"', block) and not re.search(r'\b(tag|ref|branch)\s*=', block)
            for f in (ctx.repo / "nix").rglob("*.nix")
            for block in re.findall(r'fetch(?:FromGitHub|FromGitLab|git)\s*\{(.*?)\n\s*\};', f.read_text(errors="replace"), re.S)
        ),
        fail_name='runtime: a download in nix/ is pinned to a tag or branch; pin it to a 40-character commit',
    ),
    Check(
        'runtime: MAKO and ModuCPP are gone (removed in 4.2): no manifests, examples, or tool wiring',
        not_(test('-e', 'assets/anix-languages/moducpp.json')),
        not_(test('-e', 'assets/anix-languages/mako.json')),
        no_match('examples/anix-v2/*.moducpp'),
        no_match('examples/anix-v2/*.mko'),
        not_(grep('-rqi', 'moducpp-anix', 'nix', 'flake.nix', 'scripts/install', 'scripts/support/abora-update.sh')),
    ),
    Check(
        'runtime: release docs describe ANIX and gaming flow',
        grep('-q', 'sudo abora update', 'docs/wiki/FAQ.md'),
        grep('-q', 'abora build --from-source', 'docs/wiki/Building-Abora.md'),
        grep('-q', 'nix build .#nixosConfigurations.abora.config.system.build.toplevel', 'docs/wiki/Building-Abora.md'),
        grep('-q', 'ANIX standalone tarball', 'docs/wiki/Building-Abora.md'),
        grep('-q', 'ANIX standalone package', 'RELEASE_NOTES.md'),
        grep('-q', 'Abora Gaming', 'RELEASE_NOTES.md'),
        grep('-q', 'abora hardware-test', 'RELEASE_NOTES.md'),
        grep('-q', 'abora gaming status', 'docs/wiki/Abora-Gaming.md'),
        grep('-q', 'abora gaming install steam', 'docs/wiki/Abora-Gaming.md'),
        grep('-q', 'abora gaming doctor', 'scripts/abora.sh'),
        grep('-q', 'abora gaming repair-cache', 'scripts/abora.sh'),
        grep('-Eq', '(abora|anix) gaming doctor', 'nix/modules/installed-base.nix'),
        grep('-Eq', '(abora|anix) gaming repair-cache', 'nix/modules/installed-base.nix'),
        grep('-q', 'abora gaming steam on', 'RELEASE_NOTES.md'),
        grep('-q', 'abora gaming install wine winetricks', 'RELEASE_NOTES.md'),
        grep('-q', 'Wine and Winetricks', 'RELEASE_NOTES.md'),
        grep('-q', 'Steam, Wine, launchers', 'docs/wiki/Abora-Tools.md'),
        grep('-q', 'abora gaming install steam', 'docs/wiki/Abora-Gaming.md'),
        grep('-q', 'abora gaming controllers on', 'docs/wiki/Abora-Gaming.md'),
        grep('-q', 'abora gaming mangohud on', 'docs/wiki/Abora-Gaming.md'),
        grep('-q', 'abora gaming gamemode on', 'docs/wiki/Abora-Gaming.md'),
        grep('-q', 'abora gaming launchers on', 'docs/wiki/Abora-Gaming.md'),
        grep('-q', 'abora.gaming.controllerSupport = true', 'docs/release-checklist.md'),
        grep('-q', 'anix enable gaming.launchers', 'RELEASE_NOTES.md'),
        grep('-q', 'current alpha release line', 'docs/wiki/FAQ.md'),
        grep('-q', 'current alpha release line', 'docs/wiki/Home.md'),
        grep('-q', 'ANIX v2 Languages](ANIX-V2-Languages.md)', 'docs/wiki/_Sidebar.md'),
        grep('-q', 'sudo abora rollback', 'docs/wiki/Updating-Abora.md'),
        grep('-q', 'Abora OS v4.1 Horizon', 'DISCORD_CHANGELOG.md'),
        grep('-q', 'abora support-report', 'DISCORD_CHANGELOG.md'),
        grep('-q', 'abora hardware-test --with-report', 'DISCORD_CHANGELOG.md'),
        not_(grep('-q', 'abora-support-report', 'DISCORD_CHANGELOG.md')),
        grep('-q', 'abora support-report', 'docs/install-checklist.md'),
        grep('-q', 'sudo abora update', 'docs/wiki/Abora-Tools.md'),
        grep('-Eq', 'sudo (abora|anix) update', 'nix/modules/installed-base.nix'),
    ),
    Check(
        'runtime: installer first screen exposes terminal, debug, and source-build tools',
        grep('-q', 'open_live_terminal()', 'scripts/abora-installer.sh'),
        grep('-q', 'debug_tools_menu()', 'scripts/abora-installer.sh'),
        grep('-q', 'source_build_menu()', 'scripts/abora-installer.sh'),
        grep('-q', 'Open terminal|Drop to the live environment shell', 'scripts/abora-installer.sh'),
        grep('-q', 'Debug installer|View logs, run hardware tests, or collect a report', 'scripts/abora-installer.sh'),
        grep('-q', 'Build from source|Advanced commands for compiling Abora yourself', 'scripts/abora-installer.sh'),
        grep('-q', 'abora hardware-test --with-report', 'scripts/abora-installer.sh'),
        grep('-q', 'abora build --from-source', 'scripts/abora-installer.sh'),
        grep('-q', 'nixosConfigurations.abora.config.system.build.toplevel', 'scripts/abora-installer.sh'),
        grep('-q', 'the universal installer ISO', 'scripts/abora-installer.sh'),
        grep('-q', 'check_install_environment live', 'scripts/abora-installer.sh'),
        grep('-q', 'check_install_environment final', 'scripts/abora-installer.sh'),
        grep('-q', 'Selected install values will be checked after disk and user setup', 'scripts/abora-installer.sh'),
        grep('-q', 'Disk tools', 'scripts/abora-installer.sh'),
        grep('-q', 'Use lsblk, dmesg, or nvme/sata tools', 'scripts/abora-installer.sh'),
        grep('-q', 'network_tools_menu()', 'scripts/abora-installer.sh'),
        grep('-q', 'quick_wifi_connect()', 'scripts/abora-installer.sh'),
        grep('-q', 'open_nmtui_or_explain()', 'scripts/abora-installer.sh'),
        grep('-q', 'log_network_snapshot()', 'scripts/abora-installer.sh'),
        grep('-q', 'network snapshot start', 'scripts/abora-installer.sh'),
        grep('-q', 'visible Wi-Fi networks', 'scripts/abora-installer.sh'),
        grep('-q', 'cache.nixos.org reachable', 'scripts/abora-installer.sh'),
        grep('-q', 'Network tools|Status, nmtui, quick Wi-Fi, and rescan', 'scripts/abora-installer.sh'),
        grep('-q', 'failed_install_menu()', 'scripts/abora-installer.sh'),
        grep('-q', 'Try installer again|Return to the first screen', 'scripts/abora-installer.sh'),
        grep('-q', 'Network tools|Fix Wi-Fi, DNS, or cache reachability', 'scripts/abora-installer.sh'),
        grep('-q', 'Debug tools|View logs, hardware test, support report', 'scripts/abora-installer.sh'),
        grep('-q', 'Open terminal|Drop to the live shell', 'scripts/abora-installer.sh'),
        grep('-q', 'Interactive picker failed; using numbered fallback menu', 'scripts/abora-installer.sh'),
        grep('-q', 'Interactive picker returned an unknown choice; using numbered fallback menu', 'scripts/abora-installer.sh'),
        grep('-q', 'tui_size_warning()', 'scripts/abora-installer.sh'),
        grep('-q', 'Open terminal', 'docs/install-checklist.md'),
        grep('-q', 'Debug installer', 'docs/wiki/Installation.md'),
        grep('-q', 'Build from source', 'docs/install-checklist.md'),
    ),
    Check(
        'runtime: installer copies ANIX language adapters',
        grep('-q', '/etc/abora/anix-languages', 'scripts/abora-installer.sh'),
        grep('-q', 'etc/nixos/abora/anix-languages', 'scripts/abora-installer.sh'),
        grep('-q', '"abora/anix-languages".source = anixLanguagesDir', 'nix/modules/installed-base.nix'),
    ),
    # Regression test: a real fresh install once failed with "path
    # '/mnt/etc/nixos/abora/pkgs/abora-update-resolver-deps.json' does not exist":
    # a package's lock file is read relative to wherever its .nix file ends up,
    # so it has to travel with the tool at every hop (live ISO -> installed
    # target -> later abora update syncs). The plan tool's Cargo.lock lives in
    # its source directory, which every hop copies whole.
    Check(
        'runtime: installer and updater ship the plan tool with its Cargo.lock',
        grep('-Fq', 'cargoLock.lockFile = toolSrc + "/Cargo.lock";', 'nix/pkgs/abora-plan-tool.nix'),
        test('-f', 'tools/abora-plan-tool/Cargo.lock'),
        grep('-q', '"abora/plan-tool".source = ../../tools/abora-plan-tool', 'nix/profiles/live.nix'),
        grep('-q', 'cp -a /etc/abora/plan-tool/. ', 'scripts/abora-installer.sh'),
        grep('-q', 'copy_upstream_dir "$upstream_dir/tools/abora-plan-tool"', 'scripts/abora-update.sh'),
        grep('-Fq', 'tools/abora-plan-tool/Cargo.lock', 'scripts/abora-update.sh'),
    ),
    # 4.0/4.1 updaters refuse a release without the old resolver's files, and a
    # rolled-back older installed-base.nix may still call its .nix: the
    # placeholder forwards to abora-update (same CLI) instead of failing.
    Check(
        'runtime: the removed C# tools leave only legacy placeholders behind',
        grep('-Fq', 'exec abora-update "$@"', 'nix/pkgs/abora-update-resolver.nix'),
        not_(grep('-q', 'buildDotnetModule', 'nix/pkgs/abora-update-resolver.nix', 'nix/pkgs/abora-plan-tool.nix')),
        not_(grep('-q', 'abora-update-resolver', 'flake.nix', 'nix/profiles/live.nix', 'nix/modules/installed-base.nix')),
        not_(test('-e', 'tools/abora-plan-tool/AboraPlanTool.csproj')),
        not_(test('-e', 'nix/pkgs/abora-plan-tool-deps.json')),
    ),
    Check(
        'runtime: the startup sound is gone (removed in 4.2): no ringtone command, no login sound, no sound files',
        not_(grep('-rqiE', 'ringtone|launch_sound|ANIX_SOUND_FILE|v3StartingAbora', 'scripts/core', 'scripts/config', 'nix', 'scripts/install', 'scripts/support/abora-update.sh')),
        not_(test('-e', 'assets/Effects/v3StartingAbora.mp3')),
        test('-e', 'assets/Effects/LaunchingAbora.mp3'),
    ),
    Check(
        'runtime: installed systems expose dotfiles import and source build helper',
        grep('-q', 'dotfilesImportScript[[:space:]]*= ./dotfiles-import.sh;', 'nix/modules/installed-base.nix'),
        grep('-q', 'aboraDotfilesImport = pkgs.writeShellScriptBin "abora-dotfiles-import"', 'nix/modules/installed-base.nix'),
        grep('-q', 'aboraDotfilesImport', 'nix/modules/installed-base.nix'),
        grep('-q', 'buildScript[[:space:]]*= ./build.sh;', 'nix/modules/installed-base.nix'),
        grep('-q', 'adoptNixosScript[[:space:]]*= ./adopt-nixos.sh;', 'nix/modules/installed-base.nix'),
        grep('-q', '"abora/dotfiles-import.sh"', 'nix/modules/installed-base.nix'),
        grep('-q', '"abora/build.sh"', 'nix/modules/installed-base.nix'),
        grep('-q', '"abora/adopt-nixos.sh"', 'nix/modules/installed-base.nix'),
        grep('-q', '/etc/abora/build.sh', 'scripts/abora-installer.sh'),
        grep('-q', '/etc/abora/adopt-nixos.sh', 'scripts/abora-installer.sh'),
        grep('-q', '/etc/abora/check-full.sh', 'scripts/abora-installer.sh'),
        grep('-q', '/etc/abora/dotfiles-import.sh', 'scripts/abora-installer.sh'),
        grep('-q', '/etc/abora/abora-options.nix', 'scripts/abora-installer.sh'),
        grep('-q', '/etc/abora/desktops', 'scripts/abora-installer.sh'),
        grep('-q', '/etc/abora/wallpapers', 'scripts/abora-installer.sh'),
        grep('-q', '/etc/abora/themes', 'scripts/abora-installer.sh'),
        grep('-q', 'cp -a /etc/abora/wallpapers/.', 'scripts/abora-installer.sh'),
        grep('-q', 'cp -a /etc/abora/themes/.', 'scripts/abora-installer.sh'),
        grep('-q', '../../assets/wallpapers/collection', 'nix/modules/abora-options.nix'),
        grep('-q', '../../assets/wallpapers/collection', 'nix/modules/installed-base.nix'),
        grep('-q', '../../assets/wallpaper-themes', 'nix/modules/installed-base.nix'),
        grep('-q', 'build.sh adopt-nixos.sh', 'scripts/abora-installer.sh'),
        grep('-q', 'dotfiles-import.sh', 'scripts/abora-installer.sh'),
    ),
    Check(
        'runtime: installer ships current local docs',
        grep('-q', '/etc/abora/docs/wiki/ANIX-V2-Languages.md', 'scripts/abora-installer.sh'),
        grep('-q', '/etc/abora/docs/wiki/Abora-Gaming.md', 'scripts/abora-installer.sh'),
        grep('-q', '/etc/abora/docs/wiki/Updating-Abora.md', 'scripts/abora-installer.sh'),
        grep('-q', 'for doc in ANIX-V1 ANIX-V2-Languages Packages Abora-Tools Abora-Gaming Recovery Updating-Abora', 'scripts/abora-installer.sh'),
    ),
    Check(
        'runtime: diagnostics include dotfiles import log',
        grep('-q', 'dotfiles-import.log', 'scripts/support/abora-support-report.py'),
        grep('-q', 'Dotfiles import log', 'scripts/support/abora-check-full.py'),
        grep('-q', '~/.local/state/abora/dotfiles-import.log', 'docs/wiki/Abora-Tools.md'),
    ),
    Check(
        'runtime: check-full and docs describe redacted diagnostics',
        grep('-qF', 'self.write(redact(output))', 'scripts/support/abora-check-full.py'),
        grep('-qF', 'redact(command_output(argv))', 'scripts/support/abora-support-report.py'),
        grep('-q', 'Abora network diagnostics', 'scripts/support/abora-support-report.py'),
        grep('-qF', '["abora-recovery", "network"]', 'scripts/support/abora-support-report.py'),
        grep('-q', 'abora support-report \\[--output-dir DIR\\]', 'scripts/support/abora-support-report.py'),
        grep('-q', 'Abora support archive created', 'scripts/support/abora-support-report.py'),
        grep('-q', 'nmcli networking connectivity check', 'scripts/support/abora-check-full.py'),
        grep('-q', 'nmcli radio', 'scripts/support/abora-check-full.py'),
        grep('-q', 'cache.nixos.org', 'scripts/support/abora-check-full.py'),
        grep('-qF', 'redact(text).splitlines(keepends=True)[:260]', 'scripts/support/abora-check-full.py'),
        grep('-q', 'Support archives redact obvious password', 'docs/wiki/Abora-Tools.md'),
        grep('-q', 'bug report template', 'docs/wiki/Abora-Tools.md'),
        grep('-q', 'Abora Bug Report Template', 'docs/bug-report-template.md'),
        grep('-q', 'abora logs --lines 200', 'docs/bug-report-template.md'),
        grep('-q', 'abora bug-report --github --web', 'docs/bug-report-template.md'),
        grep('-q', 'abora bug-report --github --web --with-support-report', 'docs/wiki/Abora-Tools.md'),
        grep('-q', 'abora support-report --output-dir ~/Desktop', 'docs/bug-report-template.md'),
        grep('-q', 'abora support-report --output-dir ~/Desktop', 'docs/wiki/Abora-Tools.md'),
        grep('-q', 'review the archive before posting', 'docs/wiki/Recovery.md'),
        grep('-q', 'abora recovery network', 'docs/wiki/Recovery.md'),
        grep('-q', 'abora network', 'docs/wiki/Recovery.md'),
        grep('-q', 'Failed checks do not stop the report', 'docs/wiki/Recovery.md'),
        grep('-q', 'review', 'docs/hardware-testing.md'),
        grep('-q', 'abora hardware-test --with-report', 'docs/hardware-testing.md'),
        grep('-q', 'abora hardware-test', 'docs/wiki/FAQ.md'),
        grep('-q', 'Quick Wi-Fi connect', 'docs/wiki/FAQ.md'),
        grep('-q', 'abora network', 'docs/wiki/FAQ.md'),
        grep('-q', 'abora recovery network', 'docs/wiki/FAQ.md'),
    ),
    Check(
        'runtime: installer persists Abora Gaming Steam and Vulkan options',
        grep('-q', 'gaming_steam=', 'scripts/abora-installer.sh'),
        grep('-q', 'gaming_vulkan=', 'scripts/abora-installer.sh'),
        grep('-q', 'Vulkan tools', 'scripts/abora-installer.sh'),
        grep('-q', 'install_gaming_during_setup="${ABORA_INSTALL_GAMING_DURING_SETUP:-no}"', 'scripts/abora-installer.sh'),
        grep('-q', '^write_pending_gaming_plan()', 'scripts/abora-installer.sh'),
        grep('-q', 'deferred Abora Gaming package activation until first boot', 'scripts/abora-installer.sh'),
        grep('-q', 'install_gaming_enabled="no"', 'scripts/abora-installer.sh'),
        grep('-q', 'abora.gaming.steam = {g_steam};', 'tools/abora-installer/src/nixcfg.rs'),
        grep('-q', 'abora.gaming.vulkanTools = {g_vk};', 'tools/abora-installer/src/nixcfg.rs'),
        grep('-q', 'set_nix_bool_assignment "$abora_local" "abora.gaming.steam"', 'scripts/abora-installer.sh'),
        grep('-q', 'set_nix_bool_assignment "$abora_local" "abora.gaming.vulkanTools"', 'scripts/abora-installer.sh'),
    ),
    Check(
        'runtime: installer reconfig uses current Abora option names',
        grep('-q', '^read_nix_string_assignment()', 'scripts/abora-installer.sh'),
        grep('-q', '^set_nix_string_assignment()', 'scripts/abora-installer.sh'),
        grep('-q', 'read_nix_string_assignment "$f" "abora.hostname"', 'scripts/abora-installer.sh'),
        grep('-q', 'read_nix_string_assignment "$f" "networking.hostName"', 'scripts/abora-installer.sh'),
        grep('-q', 'read_nix_string_assignment "$f" "abora.locale"', 'scripts/abora-installer.sh'),
        grep('-q', 'read_nix_string_assignment "$f" "abora.timezone"', 'scripts/abora-installer.sh'),
        grep('-q', 'read_nix_string_assignment "$f" "abora.keyboard.console"', 'scripts/abora-installer.sh'),
        grep('-q', 'read_nix_string_assignment "$f" "abora.keyboard.xkb"', 'scripts/abora-installer.sh'),
        grep('-q', 'read_nix_string_assignment "$f" "abora.desktop"', 'scripts/abora-installer.sh'),
        grep('-q', 'read_nix_string_assignment "$f" "abora.wallpaper"', 'scripts/abora-installer.sh'),
        grep('-q', 'read_nix_string_assignment "$f" "abora.gpu"', 'scripts/abora-installer.sh'),
        grep('-q', 'set_nix_string_assignment "$abora_local" "abora.hostname"', 'scripts/abora-installer.sh'),
        grep('-q', 'set_nix_string_assignment "$abora_local" "abora.locale"', 'scripts/abora-installer.sh'),
        grep('-q', 'set_nix_string_assignment "$abora_local" "abora.timezone"', 'scripts/abora-installer.sh'),
        grep('-q', 'set_nix_string_assignment "$abora_local" "abora.keyboard.console"', 'scripts/abora-installer.sh'),
        grep('-q', 'set_nix_string_assignment "$abora_local" "abora.keyboard.xkb"', 'scripts/abora-installer.sh'),
        grep('-q', 'set_nix_string_assignment "$abora_local" "abora.desktop"', 'scripts/abora-installer.sh'),
        grep('-q', 'set_nix_string_assignment "$abora_local" "abora.wallpaper"', 'scripts/abora-installer.sh'),
        grep('-q', 'set_nix_string_assignment "$abora_local" "abora.gpu"', 'scripts/abora-installer.sh'),
        grep('-q', 'set_nix_string_assignment "${cfgdir}/anix.nix" "anix.hostname"', 'scripts/abora-installer.sh'),
        grep('-q', 'set_nix_string_assignment "${cfgdir}/anix.nix" "anix.wallpaper"', 'scripts/abora-installer.sh'),
    ),
    Check(
        'runtime: Nix ANIX package bundles v2 language support and gaming docs',
        grep('-q', 'dontBuild = true;', 'nix/pkgs/anix.nix'),
        grep('-q', 'jq', 'nix/pkgs/anix.nix'),
        grep('-q', 'ANIX_SYSTEM_LANGUAGE_DIR', 'nix/pkgs/anix.nix'),
        grep('-q', 'assets/anix-languages', 'nix/pkgs/anix.nix'),
        grep('-q', 'Abora-Gaming.md', 'nix/pkgs/anix.nix'),
    ),
    Check(
        'runtime: abora config GUI exposes gaming toggles',
        grep('-q', "Adw.SwitchRow(title='Abora Gaming')", 'scripts/abora-config-gui.py'),
        grep('-q', "read_bool_setting('gaming.enable'", 'scripts/abora-config-gui.py'),
        grep('-q', "read_bool_setting('gaming.steam'", 'scripts/abora-config-gui.py'),
        grep('-q', "'gaming.steam'", 'scripts/abora-config-gui.py'),
        grep('-q', "'gaming.big-picture'", 'scripts/abora-config-gui.py'),
        grep('-q', "'gaming.gamescope'", 'scripts/abora-config-gui.py'),
        grep('-q', "'gaming.controllers'", 'scripts/abora-config-gui.py'),
        grep('-q', "'gaming.mangohud'", 'scripts/abora-config-gui.py'),
        grep('-q', "'gaming.gamemode'", 'scripts/abora-config-gui.py'),
        grep('-q', "'gaming.vulkan'", 'scripts/abora-config-gui.py'),
        grep('-q', "'gaming.launchers'", 'scripts/abora-config-gui.py'),
        grep('-q', "'gaming.autostart'", 'scripts/abora-config-gui.py'),
    ),
    Check(
        'runtime: abora welcome exposes gaming status and action',
        grep('-qF', 'read_bool_setting("gaming.enable")', 'scripts/support/abora-welcome.py'),
        grep('-qF', 'kv("Gaming"', 'scripts/support/abora-welcome.py'),
        grep('-qF', '["abora", "gaming", "status"]', 'scripts/support/abora-welcome.py'),
        grep('-q', "read_local_bool('gaming.enable'", 'scripts/abora-welcome-gui.py'),
        grep('-q', "title='Gaming'", 'scripts/abora-welcome-gui.py'),
        grep('-q', "\\['abora', 'gaming', 'status'\\]", 'scripts/abora-welcome-gui.py'),
        grep('-q', "\\['abora', 'doctor'\\]", 'scripts/abora-welcome-gui.py'),
        grep('-q', "\\['abora', 'apps'\\]", 'scripts/abora-welcome-gui.py'),
        grep('-q', "\\['abora', 'desktop', 'list'\\]", 'scripts/abora-welcome-gui.py'),
        grep('-q', "\\['abora', 'recovery'\\]", 'scripts/abora-welcome-gui.py'),
    ),
    # Abora Gaming Welcome is a deliberately separate app from Abora Welcome
    # (see abora-gaming-welcome-gui.py's own module docstring for why) --
    # the normal welcome only hands off to it via a button, it doesn't embed
    # gaming-specific platform/sign-in UI itself.
    Check(
        'runtime: Abora Gaming Welcome is a separate app with a hand-off from Abora Welcome',
        grep('-q', 'class GamingWelcomeWindow', 'scripts/abora-gaming-welcome-gui.py'),
        grep('-q', 'def read_gaming_catalog', 'scripts/abora-gaming-welcome-gui.py'),
        grep('-q', "category != 'Gaming'", 'scripts/abora-gaming-welcome-gui.py'),
        grep('-q', "'bottles', 'wine', 'winetricks', 'gamemode'", 'scripts/abora-gaming-welcome-gui.py'),
        grep('-q', 'def _steam_installed', 'scripts/abora-gaming-welcome-gui.py'),
        grep('-q', "'Open Steam'", 'scripts/abora-gaming-welcome-gui.py'),
        grep('-q', "'Install Steam'", 'scripts/abora-gaming-welcome-gui.py'),
        grep('-q', "command_path('abora'), 'gaming', 'install', app_id", 'scripts/abora-gaming-welcome-gui.py'),
        grep('-q', 'gaming enable && exec', 'scripts/abora-gaming-welcome-gui.py'),
        grep('-q', 'command_path("abora-update")', 'scripts/abora-gaming-welcome-gui.py'),
        grep('-q', 'lib.optional (gamingWelcomeGuiScript != null) aboraGamingWelcomeGui', 'nix/modules/installed-base.nix'),
        grep('-q', 'lib.optional config.abora.gaming.enable aboraGamingWelcomeDesktopPkg', 'nix/modules/installed-base.nix'),
        grep('-q', 'GAMING_WELCOME_COMMAND', 'scripts/abora-welcome-gui.py'),
        grep('-q', "'abora-gaming-welcome-gui'", 'scripts/abora-welcome-gui.py'),
        grep('-q', "python3', fallback", 'scripts/abora-welcome-gui.py'),
        grep('-q', '_open_gaming_welcome', 'scripts/abora-welcome-gui.py'),
        grep('-q', 'welcome)', 'scripts/abora-gaming.sh'),
        grep('-q', 'launch_welcome', 'scripts/abora-gaming.sh'),
        grep('-q', 'abora-gaming-welcome-gui', 'scripts/abora-gaming.sh'),
    ),
    Check(
        'runtime: installed GUI wrappers match live renderer/backend fallbacks',
        grep('-q', 'export GSK_RENDERER=', 'nix/modules/installed-base.nix'),
        grep('-q', 'export GDK_BACKEND=', 'nix/modules/installed-base.nix'),
        grep('-q', 'export GSK_RENDERER=', 'nix/profiles/live.nix'),
        grep('-q', 'export GDK_BACKEND=', 'nix/profiles/live.nix'),
    ),
    Check(
        'runtime: live and installed systems both ship Gaming Welcome wrapper',
        grep('-q', 'writeShellScriptBin "abora-gaming-welcome-gui"', 'nix/modules/installed-base.nix'),
        grep('-q', 'writeShellScriptBin "abora-gaming-welcome-gui"', 'nix/profiles/live.nix'),
        grep('-q', 'export ABORA_APPS_SCRIPT=', 'nix/modules/installed-base.nix'),
        grep('-q', 'export ABORA_APPS_SCRIPT=', 'nix/profiles/live.nix'),
        grep('-q', 'export ABORA_APP_CATALOG=', 'nix/modules/installed-base.nix'),
        grep('-q', 'export ABORA_APP_CATALOG=', 'nix/profiles/live.nix'),
        grep('-q', 'exec .*gaming-welcome-gui.py', 'nix/modules/installed-base.nix'),
        grep('-q', 'exec .*gaming-welcome-gui.py', 'nix/profiles/live.nix'),
        grep('-q', 'abora/gaming-welcome-gui.py".source', 'nix/modules/installed-base.nix'),
        grep('-q', 'abora/gaming-welcome-gui.py".source', 'nix/profiles/live.nix'),
        grep('-q', 'aboraGaming', 'nix/profiles/live.nix'),
        grep('-q', 'aboraGamingWelcomeGui', 'nix/modules/installed-base.nix'),
    ),
    Check(
        'runtime: Abora Gaming Big Picture launcher has Steam flag fallback',
        grep('-q', 'writeShellScriptBin "abora-steam-big-picture"', 'nix/modules/abora-options.nix'),
        grep('-q', 'steam steam://open/bigpicture', 'nix/modules/abora-options.nix'),
        grep('-q', 'steam -gamepadui', 'nix/modules/abora-options.nix'),
        grep('-q', 'exec steam -bigpicture', 'nix/modules/abora-options.nix'),
        grep('-q', 'Steam Gamepad UI failed; trying legacy Big Picture mode', 'nix/modules/abora-options.nix'),
        grep('-q', 'Exec=abora-steam-big-picture', 'nix/modules/abora-options.nix'),
        grep('-q', 'writeShellScriptBin "abora-steam-gamescope-session"', 'nix/modules/abora-options.nix'),
        grep('-q', 'gamescope -e -f -- abora-steam-big-picture --session', 'nix/modules/abora-options.nix'),
        grep('-q', 'Exec=abora-steam-gamescope-session', 'nix/modules/abora-options.nix'),
        grep('-q', 'abora-steam-gamescope-session', 'docs/wiki/Abora-Gaming.md'),
        grep('-q', 'cfg.gaming.steam && cfg.gaming.bigPictureShortcut', 'nix/modules/abora-options.nix'),
        grep('-q', 'cfg.gaming.steam && cfg.gaming.gamescopeSession', 'nix/modules/abora-options.nix'),
        grep('-q', 'cfg.gaming.steam && cfg.gaming.bigPictureAutostart', 'nix/modules/abora-options.nix'),
        not_(grep('-q', '^[[:space:]]\\+\\[Desktop Entry\\]', 'nix/modules/abora-options.nix')),
        grep('-q', 'programs.steam.enable = lib.mkDefault true', 'nix/modules/abora-options.nix'),
        grep('-q', 'gaming.steam', 'scripts/abora-config.sh'),
        grep('-q', 'gaming.controllers', 'scripts/abora-config.sh'),
        grep('-q', 'gaming.launchers', 'scripts/abora-gaming.sh'),
        grep('-q', 'session|gamescope-session', 'scripts/abora-gaming.sh'),
        grep('-q', 'pkgIf cfg.gaming.vulkanTools "vulkan-tools"', 'nix/modules/abora-options.nix'),
        grep('-q', 'pkgIf cfg.gaming.launchers "winetricks"', 'nix/modules/abora-options.nix'),
        grep('-q', 'wineIf cfg.gaming.launchers', 'nix/modules/abora-options.nix'),
        grep('-q', 'Run: abora gaming install steam', 'nix/modules/abora-options.nix'),
        grep('-q', 'steam steam://open/bigpicture', 'scripts/abora-gaming.sh'),
        grep('-q', 'steam -gamepadui', 'scripts/abora-gaming.sh'),
        grep('-q', 'Steam Gamepad UI failed; trying legacy Big Picture mode', 'scripts/abora-gaming.sh'),
        grep('-q', 'gamescope -e -f --', 'scripts/abora-gaming.sh'),
        grep('-q', 'Run: abora gaming install steam', 'scripts/abora-gaming.sh'),
    ),
    # Same fixed-file guarantee for the installer's own first-time creation
    # path (abora-installer.sh, not the config-migration path above).
    Check(
        'runtime: installer keeps password hashes out of /etc/nixos (and so out of the Nix store)',
        grep('-Fq', 'abora.user.hashedPasswordFile = \"{secrets}/user.hash\";', 'tools/abora-installer/src/nixcfg.rs'),
        grep('-Fq', 'install -d -m 0700 "${root}${secrets_dir}"', 'scripts/abora-installer.sh'),
        not_(grep('-Fq', 'abora.user.hashedPassword = "${user_password_hash}";', 'scripts/abora-installer.sh')),
        grep('-Fq', 'hashedPasswordFile = lib.mkIf (cfg.user.hashedPasswordFile != null)', 'nix/modules/abora-options.nix'),
    ),
    # Static check for the self-elevation guard itself (abora-config.sh, right
    # after local_module is defined): a non-owning, non-root user reading a
    # now-0600 abora-local.nix needs this to `exec sudo "$0" "$@"` rather than
    # every scattered read call site (read_option, desktop/GPU detection, the
    # legacy migration, ...) failing or silently reading nothing. Not
    # exercised dynamically below -- doing that safely would mean either a
    # real interactive sudo prompt (hangs this suite) or mocking sudo, neither
    # worth it for one guard clause; this at least catches the guard being
    # deleted or its condition broken.
    Check(
        "runtime: abora-config.sh self-elevates via sudo when abora-local.nix isn't readable",
        grep('-q', 'ABORA_NO_SUDO:-0.*!= "1".*&&.*-f "\\$local_module".*&&.*! -r "\\$local_module"', 'scripts/abora-config.sh'),
        grep('-q', 'exec sudo "\\$0" "\\$@"', 'scripts/abora-config.sh'),
    ),
    # Static guard for a real fix that isn't cheap to verify behaviorally in
    # this suite (it needs a full NixOS module eval realizing abora-options.nix's
    # package references, which takes minutes -- verified manually instead, see
    # the commit that introduced this line): anix.nix's "anix.gaming.* is set
    # but anix.gaming.enable isn't true" warning used to fire even when
    # abora.gaming.enable was already true from another source (the common real
    # sequence: installer sets it in abora-local.nix, then `anix enable
    # gaming.vulkan` only touches anix.gaming.vulkanTools) -- a false-positive
    # warning on every single rebuild of an entirely normal, working config.
    # This just guards against the fix's condition being silently deleted.
    Check(
        'runtime: anix.nix gaming warning checks abora.gaming.enable, not just anix.gaming.enable',
        grep('-q', 'config.abora.gaming.enable != true', 'nix/modules/anix.nix'),
        grep('-q', 'abora.gaming.steam = lib.mkForce cfg.gaming.steam;', 'nix/modules/anix.nix'),
        grep('-q', 'abora.gaming.controllerSupport = lib.mkForce cfg.gaming.controllerSupport;', 'nix/modules/anix.nix'),
        grep('-q', 'abora.gaming.mangohud = lib.mkForce cfg.gaming.mangohud;', 'nix/modules/anix.nix'),
        grep('-q', 'abora.gaming.gamemode = lib.mkForce cfg.gaming.gamemode;', 'nix/modules/anix.nix'),
        grep('-q', 'abora.gaming.launchers = lib.mkForce cfg.gaming.launchers;', 'nix/modules/anix.nix'),
        grep('-q', 'gaming.steam|steam', 'scripts/anix.sh'),
        grep('-q', 'gaming.controllers|gaming.controller|gaming.controllerSupport', 'scripts/anix.sh'),
        grep('-q', 'gaming.launchers|launchers', 'scripts/anix.sh'),
        grep('-q', 'anix.gaming.steam = true;', 'scripts/anix.sh'),
        grep('-q', 'anix.gaming.launchers = true;', 'scripts/anix.sh'),
        grep('-q', 'write_anix_gaming_dependencies', 'scripts/anix.sh'),
        grep('-q', 'gaming.bigPictureAutostart', 'scripts/anix.sh'),
    ),
    # Regression test: scripts/abora-setup.desktop is installed identically on
    # both the live ISO and every installed system (nix/modules/installed-base.nix),
    # but commit 15dc9ec89453f5e376cc8c97d3bb06485c072d4f changed its Name/Comment
    # to installed-inappropriate wording ("Install Abora OS" / "Install Abora OS
    # from the live desktop"). abora-setup-launcher.sh correctly detects live vs.
    # installed and only runs an installer on the live ISO (--reconfig otherwise),
    # but the static .desktop label doesn't know that, so users who already
    # installed saw a launcher that claimed to reinstall/install the OS. Reported
    # via Discord: "after i installed abora os and booted up theres a gui app
    # that just says install abora os". Checks the label is context-neutral.
    Check(
        'runtime: abora-setup.desktop label is context-neutral (not install-only wording)',
        grep('-qx', 'Name=Start Abora', 'scripts/abora-setup.desktop'),
        grep('-qx', 'Comment=Install or reconfigure Abora OS', 'scripts/abora-setup.desktop'),
        not_(grep('-q', 'Name=Install Abora OS', 'scripts/abora-setup.desktop')),
        not_(grep('-q', 'from the live desktop', 'scripts/abora-setup.desktop')),
    ),
    Check(
        'runtime: updater re-execs with synced UI and builds before switching',
        grep('-q', 'local synced_ui="\\$config_dir/abora/ui.sh"', 'scripts/abora-update.sh'),
        grep('-q', 'ABORA_UI_LIB="\\${synced_ui}"', 'scripts/abora-update.sh'),
        grep('-q', 'resolve_resolver_bin()', 'scripts/abora-update.sh'),
        grep('-q', 'resolver_bin="$(resolve_resolver_bin)"', 'scripts/abora-update.sh'),
        grep('-q', 'abora-update-build.log', 'scripts/abora-update.sh'),
        grep('-q', 'Checking the new Abora system', 'scripts/abora-update.sh'),
        grep('-q', '--', '--no-link', 'scripts/abora-update.sh'),
        grep('-q', '--', '--show-trace', 'scripts/abora-update.sh'),
        grep('-q', 'Switching to the new Abora system', 'scripts/abora-update.sh'),
        grep('-q', 'Continuing with the synced updater', 'scripts/abora-update.sh'),
        grep('-q', 'ABORA_UPDATE_REEXECED:-0.*!= 1.*config_dir/abora/anix.sh', 'scripts/abora-update.sh'),
        grep('-q', 'ABORA_UPDATE_REEXECED:-0.*== 1', 'scripts/abora-update.sh'),
    ),
    Check(
        'runtime: updater bounds the build and switch steps with a timeout',
        grep('-q', 'build_timeout="\\${ABORA_BUILD_TIMEOUT:-3600}"', 'scripts/abora-update.sh'),
        grep('-q', 'switch_timeout="\\${ABORA_SWITCH_TIMEOUT:-1800}"', 'scripts/abora-update.sh'),
        grep('-q', 'timeout "\\$build_timeout"', 'scripts/abora-update.sh'),
        grep('-q', 'timeout "\\$switch_timeout"', 'scripts/abora-update.sh'),
        grep('-q', '^explain_step_failure()', 'scripts/abora-update.sh'),
        grep('-q', 'status" -eq 124', 'scripts/abora-update.sh'),
        grep('-q', 'was still running after', 'scripts/abora-update.sh'),
    ),
    # The build/switch exit status has to be captured via `cmd || status=$?` on
    # its own line, not `cmd; status=$?` on the next -- this file has `set -e`
    # at the top, so a failing standalone command exits the whole script right
    # there and the status-capture line (and the timeout-aware explanation)
    # would simply never run. Guards against silently reintroducing that.
    Check(
        'runtime: updater captures build/switch exit status without tripping set -e',
        grep('-q', 'toplevel" || build_status=\\$?', 'scripts/abora-update.sh'),
        grep('-q', 'flake_config_name}" || switch_status=\\$?', 'scripts/abora-update.sh'),
    ),
)
