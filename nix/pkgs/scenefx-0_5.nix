{ lib
, stdenv
, fetchFromGitHub
, meson
, ninja
, wlroots_0_20
, scdoc
, pkg-config
, wayland
, libdrm
, libxkbcommon
, pixman
, wayland-protocols
, libGL
, libgbm
, libxcb
, libxcb-wm
, lcms2
, validatePkgConfig
, testers
, wayland-scanner
}:

# wlroots-based rendering-effects library mango.nix needs at this exact
# version (matching its wlroots_0_20 pin); packaged here rather than pulled
# from nixpkgs because nixpkgs' own scenefx package can drift to a newer
# wlroots ABI that mango's pinned commit doesn't build against.
stdenv.mkDerivation (finalAttrs: {
  pname = "scenefx";
  version = "0.5";

  src = fetchFromGitHub {
    owner = "wlrfx";
    repo  = "scenefx";
    tag   = finalAttrs.version;
    hash  = "sha256-vUjLG6eubEhJJVa9LPygIcVmNoHwYbSUTJcWEcbxnU4=";
  };

  strictDeps = true;

  depsBuildBuild = [ pkg-config ];

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    scdoc
    validatePkgConfig
    wayland-scanner
  ];

  buildInputs = [
    libdrm
    libGL
    libxkbcommon
    libgbm
    libxcb
    libxcb-wm
    lcms2
    pixman
    wayland
    wayland-protocols
    wlroots_0_20
  ];

  passthru.tests.pkg-config = testers.testMetaPkgConfig finalAttrs.finalPackage;

  meta = {
    description = "Drop-in replacement for the wlroots scene API that allows wayland compositors to render surfaces with eye-candy effects";
    homepage    = "https://github.com/wlrfx/scenefx";
    license     = lib.licenses.mit;
    maintainers = [ ];
    mainProgram = "scenefx";
    pkgConfigModules = [ "scenefx" ];
    platforms   = lib.platforms.all;
  };
})
