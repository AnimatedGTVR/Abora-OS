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
, wlroots_0_19
, scenefx
, libGL
, libX11
, libxcb-wm
, xwayland
}:

stdenv.mkDerivation {
  pname = "mango";
  version = "unstable-2026-06-12";

  src = fetchFromGitHub {
    owner = "mangowm";
    repo  = "mango";
    rev   = "792bfac475cab87bd470ed70bb9f540d72959263";
    hash  = "sha256-/sKbjzbftTgjvTmlPx5navYSPYcxyD4Pao0Ef1RJD54=";
  };

  nativeBuildInputs = [ meson ninja pkg-config wayland-scanner ];

  buildInputs = [
    libinput libxcb libxkbcommon pcre2 cjson pixman
    wayland wayland-protocols wlroots_0_19 scenefx libGL
    libX11 libxcb-wm xwayland
  ];

  mesonFlags = [ (lib.mesonEnable "xwayland" true) ];

  passthru.providedSessions = [ "mango" ];

  meta = with lib; {
    description = "Practical and powerful Wayland compositor (dwm but Wayland)";
    homepage    = "https://mangowm.github.io/";
    license     = licenses.gpl3Plus;
    platforms   = platforms.linux;
    maintainers = [];
  };
}
