{ lib, stdenv, meson, ninja, pkg-config, vala, wrapGAppsHook4, gtk4, libadwaita, json-glib, glib
, toolSrc ? if builtins.pathExists ../../tools/anix-control then ../../tools/anix-control else ../anix-control
}:
# Anix Control: software shop for NixOS and NixOS-based systems (nixpkgs via Nix or Lix, Flathub, Snap).
stdenv.mkDerivation {
  pname = "anix-control";
  version = "0.1.0";
  src = builtins.path { path = toolSrc; name = "anix-control-src"; };
  nativeBuildInputs = [ meson ninja pkg-config vala wrapGAppsHook4 ];
  buildInputs = [ gtk4 libadwaita json-glib glib ];
  meta = with lib; {
    description = "Edit your ANIX system config without the terminal";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    mainProgram = "anix-control";
  };
}
