{ stdenvNoCC, python3 }:
# Packages abora-hardware-test (hardware-readiness checks: Wi-Fi, BIOS/
# UEFI, disk, memory -- none of it Abora-specific, see
# scripts/support/abora-hardware-test.py's own lack of any /etc/abora
# dependency) as a standalone binary. --with-report also needs
# abora-support-report.py, itself a generic Linux system-info collector with
# no Abora-specific state either. The main script looks for it beside
# itself, so it is installed next to it in $out/bin under its original name.
# patchShebangs points both at the python3 in buildInputs.
stdenvNoCC.mkDerivation {
  pname = "abora-hardware-test";
  version = "1.1.0";

  src = ../../.;

  buildInputs = [ python3 ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm0755 "$src/scripts/support/abora-hardware-test.py" \
      "$out/bin/abora-hardware-test"
    install -Dm0755 "$src/scripts/support/abora-support-report.py" \
      "$out/bin/abora-support-report.py"
    runHook postInstall
  '';

  meta = {
    description = "Check whether a machine looks ready for Abora OS hardware testing, standalone";
    mainProgram = "abora-hardware-test";
  };
}
