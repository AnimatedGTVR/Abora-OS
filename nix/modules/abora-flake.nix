# nixosModules.default: Abora on an existing NixOS flake, the flake-input form of
# `abora adopt-nixos`. Existing users, homes and settings are kept (abora.user.name
# stays null unless set). See docs/wiki/Installation.md, "Existing NixOS Systems".
{ self, nixpkgs }:
{ ... }:
let
  # Abora's own pinned nixpkgs, not the module's arguments: `imports` can't depend on them.
  inherit (nixpkgs) lib;
  pkgs = nixpkgs.legacyPackages.x86_64-linux;

  # installed-base.nix reads its files from beside itself, under the names the
  # installer and abora-adopt-nixos.sh give them. This builds that directory from
  # the flake source. make check fails if it misses a file the adopt script copies.
  layout = [
    "VERSION:VERSION"
    "nix/modules/abora-options.nix:abora-options.nix"
    "nix/modules/installed-base.nix:installed-base.nix"
    "nix/modules/anix.nix:anix-module.nix"
    "nix/modules/community.nix:community.nix"
    "nix/modules/desktops:desktops"
    "nix/pkgs:pkgs"
    "tools/abora-plan-tool:plan-tool"
    "tools/abora-grab:grab"
    "tools/abora-update:abora-update"
    "assets/wallpapers/collection:wallpapers"
    "assets/wallpaper-themes:themes"
    "assets/bootloader:bootloader"
    "assets/plymouth:plymouth"
    "assets/Effects:effects"
    "assets/mango:mango"
    "assets/anix-languages:anix-languages"
    "docs:docs"
    "assets/abora-title.txt:title.txt"
    "assets/fastfetch-logo.txt:fastfetch-logo.txt"
    "assets/fastfetch-config.jsonc:fastfetch-config.jsonc"
    "assets/wallpapers/collection/titlis-alps.jpg:default-wallpaper.png"
    "scripts/abora-ui.sh:ui.sh"
    "scripts/abora.sh:abora.sh"
    "scripts/abora-build.sh:build.sh"
    "scripts/abora-config.sh:config.sh"
    "scripts/abora-desktop.sh:desktop.sh"
    "scripts/abora-dotfiles-import.sh:dotfiles-import.sh"
    "scripts/abora-doctor.sh:doctor.sh"
    "scripts/abora-recovery.sh:recovery.sh"
    "scripts/abora-welcome.sh:welcome.sh"
    "scripts/abora-app-catalog.sh:app-catalog.sh"
    "scripts/abora-apps.sh:apps.sh"
    "scripts/abora-support-report.sh:support-report.sh"
    "scripts/abora-hardware-test.sh:hardware-test.sh"
    "scripts/abora-gaming.sh:gaming.sh"
    "scripts/anix.sh:anix.sh"
    "scripts/abora-update.sh:update.sh"
    "scripts/abora-theme-sync.sh:theme-sync.sh"
    "scripts/abora-check-full.sh:check-full.sh"
    "scripts/abora-custom-packages.sh:custom-packages.sh"
    "scripts/abora-desktop-profiles.sh:desktop-profiles.sh"
    "scripts/abora-installer.sh:installer.sh"
    "scripts/abora-repair-flake-purity.sh:repair-flake-purity.sh"
    "scripts/abora-session-setup.sh:session-setup.sh"
    "scripts/abora-setup-launcher.sh:setup-launcher.sh"
    "scripts/abora-setup.desktop:setup.desktop"
    "scripts/abora-adopt-nixos.sh:adopt-nixos.sh"
    "scripts/abora-welcome-gui.py:welcome-gui.py"
    "scripts/support/abora-community.py:community.py"
    "scripts/support/abora_core.py:abora_core.py"
    "scripts/safety/abora-abt.py:abt.py"
    "scripts/abora-config-gui.py:config-gui.py"
    "scripts/abora-gaming-welcome-gui.py:gaming-welcome-gui.py"
  ];

  copy = entry:
    let
      parts = lib.splitString ":" entry;
      src = "${self}/${builtins.elemAt parts 0}";
      dest = builtins.elemAt parts 1;
    in ''
      if [ -e ${lib.escapeShellArg src} ]; then
        mkdir -p "$(dirname "$out/${dest}")"
        cp -RL ${lib.escapeShellArg src} "$out/${dest}"
      fi
    '';

  tree = pkgs.runCommandLocal "abora-system-files" { } ''
    mkdir -p "$out"
    ${lib.concatMapStrings copy layout}
    chmod -R u+w "$out"
  '';
in
{
  imports = [
    "${tree}/abora-options.nix"
    "${tree}/installed-base.nix"
    "${tree}/anix-module.nix"
  ];

  # As in `abora adopt-nixos`: Abora leaves the existing desktop alone unless asked.
  abora.desktop = lib.mkDefault "none";
}
