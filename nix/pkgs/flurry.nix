{ lib, stdenv, meson, ninja, pkg-config, vala, wrapGAppsHook4, gtk4, libadwaita, json-glib, glib
, toolSrc ? if builtins.pathExists ../../tools/flurry then ../../tools/flurry else ../flurry
}:
# Flurry: software shop for NixOS and NixOS-based systems (nixpkgs via Nix or Lix, Flathub, Snap).
stdenv.mkDerivation {
  pname = "flurry";
  version = "0.1.0";
  src = builtins.path { path = toolSrc; name = "flurry-src"; };
  nativeBuildInputs = [ meson ninja pkg-config vala wrapGAppsHook4 ];
  buildInputs = [ gtk4 libadwaita json-glib glib ];
  meta = with lib; {
    description = "Software shop for NixOS: nixpkgs (Nix or Lix), Flathub and Snap in one place";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    mainProgram = "flurry";
  };
}
