{ stdenvNoCC }:
# Packages abora-desktop-preview.sh as a standalone `nix run`-able binary,
# so a plain NixOS user doesn't need a checkout of this repo just to see
# what config/packages Abora uses for a given desktop profile (see
# docs/wiki/ANIX-Standalone.md, "Desktop Config Preview"). The script
# sources abora-desktop-profiles.sh by looking next to its own path
# (dirname "${BASH_SOURCE[0]}"), so both files are installed into the same
# $out/bin directory under their original names rather than renamed/
# wrapped -- that relative lookup keeps working unmodified once installed.
stdenvNoCC.mkDerivation {
  pname = "abora-desktop-preview";
  version = "1.0.0";

  src = ../../.;

  # patchShebangs (part of stdenv's default fixupPhase) repoints the
  # installed script's `#!/usr/bin/env bash` at a real /nix/store bash
  # automatically -- no makeWrapper needed for a plain shell script.
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm0755 "$src/scripts/abora-desktop-preview.sh" \
      "$out/bin/abora-desktop-preview"
    install -Dm0644 "$src/scripts/abora-desktop-profiles.sh" \
      "$out/bin/abora-desktop-profiles.sh"
    runHook postInstall
  '';

  meta = {
    description = "Preview Abora OS's NixOS config/packages for a desktop profile, standalone";
    mainProgram = "abora-desktop-preview";
  };
}
