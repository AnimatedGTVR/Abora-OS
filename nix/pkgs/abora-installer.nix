{ lib
, rustPlatform
}:

rustPlatform.buildRustPackage {
  pname = "abora-installer";
  version = "4.0.1-alpha";

  src = ../../tools/abora-installer;
  cargoLock.lockFile = ../../tools/abora-installer/Cargo.lock;

  meta = with lib; {
    description = "Abora OS installer front controller";
    homepage = "https://github.com/AnimatedGTVR/Abora-OS";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "abora-installer";
  };
}
