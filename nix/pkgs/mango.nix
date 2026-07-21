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

stdenv.mkDerivation {
  pname = "mango";
  version = "0.15.4";

  src = fetchFromGitHub {
    owner = "mangowm";
    repo  = "mango";
    rev   = "71278aa7a44ff4174c0a8dbb2483a291e292846d";
    hash  = "sha256-vbL9hO4vdG5MYEDocW8ORFr/qhphEUvY0ZkmrJuhrIc=";
  };

  nativeBuildInputs = [ meson ninja pkg-config wayland-scanner ];

  buildInputs = [
    libinput libxcb libxkbcommon pcre2 cjson pixman
    wayland wayland-protocols wlroots_0_20 scenefx-0_5 libGL
    libX11 libxcb-wm libdrm pango cairo xwayland
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
