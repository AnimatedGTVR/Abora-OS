{ lib
, rustPlatform
  # From the repo's flake (../../tools/...) or an installed system's copy
  # under /etc/nixos/abora (../grab).
, toolSrc ?
    if builtins.pathExists ../../tools/abora-grab
    then ../../tools/abora-grab
    else ../grab
}:
# `grab <app>`: installs an app from whichever source has it (Nix or Lix,
# Flatpak, Snap). The successor of TinyPM's grab command.
rustPlatform.buildRustPackage {
  pname = "abora-grab";
  version = "1.0.0";

  # A fixed name gives the source the same store path from the repo's flake and
  # from the installed copy, so installed systems reuse the ISO's build.
  src = builtins.path { path = toolSrc; name = "abora-grab-src"; };
  cargoLock.lockFile = toolSrc + "/Cargo.lock";

  meta = with lib; {
    description = "Install an app from whichever source has it: Nix or Lix, Flatpak, Snap";
    homepage = "https://github.com/Abora-OS/Abora-OS";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "grab";
  };
}
