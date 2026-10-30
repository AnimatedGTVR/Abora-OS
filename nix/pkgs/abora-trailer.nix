{ lib, rustPlatform }:
# The animated title sequence for Abora trailers (`nix run .#abora-trailer`).
# A recording tool for the project, not shipped on installed systems.
rustPlatform.buildRustPackage {
  pname = "abora-trailer";
  version = "1.0.0";
  src = ../../tools/abora-trailer;
  cargoLock.lockFile = ../../tools/abora-trailer/Cargo.lock;

  meta = with lib; {
    description = "Animated Abora OS title sequence for trailers, played in a terminal";
    homepage = "https://github.com/Abora-OS/Abora-OS";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "abora-trailer";
  };
}
