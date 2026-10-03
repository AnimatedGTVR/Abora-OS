{ lib
, rustPlatform
, fetchFromGitHub
}:
# The Vanta language interpreter (github.com/AnimatedGTVR/Vanta). Abora's
# app/service tools written in Vanta (tools/abora-update, ...) run on it.
# Pinned to a commit so every Abora build uses the same language semantics;
# bump rev, hash and cargoHash together.
rustPlatform.buildRustPackage {
  pname = "vanta";
  version = "0.1.0-unstable-2026-09-13";

  src = fetchFromGitHub {
    owner = "AnimatedGTVR";
    repo = "Vanta";
    rev = "e83cd0e96889db05eb815384c4b10b5ab3daa504";
    hash = "sha256-ccnrczGgiHRKAnGwpxA25sWay33p/pQpe+bDQvcRl3A=";
  };

  cargoHash = "sha256-NagYt62hrqHAGlrOnmrEEbs1B+vK1kV1sxLOrUFNavI=";

  meta = with lib; {
    description = "The Vanta programming language";
    homepage = "https://github.com/AnimatedGTVR/Vanta";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    mainProgram = "vanta";
  };
}
