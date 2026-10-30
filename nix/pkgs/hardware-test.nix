{ stdenvNoCC, python3 }:
# Packages abora-hardware-test (hardware-readiness checks: Wi-Fi, BIOS/
# UEFI, disk, memory -- none of it Abora-specific) as a standalone binary.
# --with-report also needs abora-support-report.py, itself a generic Linux
# system-info collector with no Abora-specific state either, and both import
# abora_core.py (the shared UI and redaction). The main script looks for
# them beside itself, so they are installed next to it in $out/bin.
# patchShebangs points the scripts at the python3 in buildInputs.
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
    install -Dm0644 "$src/scripts/support/abora_core.py" \
      "$out/bin/abora_core.py"
    runHook postInstall
  '';

  meta = {
    description = "Check whether a machine looks ready for Abora OS hardware testing, standalone";
    mainProgram = "abora-hardware-test";
  };
}
