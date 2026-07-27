{ stdenv
, lib
, fetchFromGitHub
, meson
, ninja
, pkg-config
, wayland-scanner
, libinput
, libxcb
, libxkbcommon
, pcre2
, cjson
, pixman
, wayland
, wayland-protocols
, wlroots_0_20
, scenefx-0_5
, libGL
, libX11
, libxcb-wm
, libdrm
, pango
, cairo
, xwayland
}:

# Packages the upstream MangoWM compositor (not an Abora fork -- pinned to a
# specific commit since it has no stable release tags yet). Abora's own
# MangoWM integration (session config, desktop entry, wallpaper/theme
# wiring) lives in nix/modules/desktops/mangowm.nix and abora-desktop-profiles.sh's
# mangowm case, not here.
stdenv.mkDerivation {
  pname = "mango";
  version = "0.15.4";

  src = fetchFromGitHub {
    owner = "mangowm";
    repo  = "mango";
    rev   = "8e71d6b0aec6db04c0e0f10fd1814a7d411c926f";
    hash  = "sha256-Bju+I6dW+m3RofwPx+ZYd84tZn1fBhOexIRl4TOrdy8=";
  };

  nativeBuildInputs = [ meson ninja pkg-config wayland-scanner ];

  buildInputs = [
    libinput libxcb libxkbcommon pcre2 cjson pixman
    wayland wayland-protocols wlroots_0_20 scenefx-0_5 libGL
    libX11 libxcb-wm libdrm pango cairo xwayland
  ];

  mesonFlags = [ (lib.mesonEnable "xwayland" true) ];

  # Tells NixOS's session-list machinery this package supplies a "mango"
  # login session, so display managers pick it up without a separate
  # services.xserver.displayManager.session entry.
  passthru.providedSessions = [ "mango" ];

  meta = with lib; {
    description = "Practical and powerful Wayland compositor (dwm but Wayland)";
    homepage    = "https://mangowm.github.io/";
    license     = licenses.gpl3Plus;
    platforms   = platforms.linux;
    maintainers = [];
  };
}
