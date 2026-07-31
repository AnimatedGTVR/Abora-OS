{ stdenvNoCC }:
# Packages abora-hardware-test.sh (hardware-readiness checks: Wi-Fi, BIOS/
# UEFI, disk, memory -- none of it Abora-specific, see
# scripts/abora-hardware-test.sh's own lack of any /etc/abora dependency
# beyond its ui.sh fallback) as a standalone binary. --with-report also
# needs abora-support-report.sh, itself a generic Linux system-info
# collector with no Abora-specific state either. Same install-siblings-
# under-original-names approach as desktop-preview.nix: both companion
# scripts are resolved by the main script via
# dirname "${BASH_SOURCE[0]}", so keeping them next to it in $out/bin
# needs no changes to the scripts themselves.
stdenvNoCC.mkDerivation {
  pname = "abora-hardware-test";
  version = "1.0.0";

  src = ../../.;

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm0755 "$src/scripts/abora-hardware-test.sh" \
      "$out/bin/abora-hardware-test"
    install -Dm0755 "$src/scripts/abora-support-report.sh" \
      "$out/bin/abora-support-report.sh"
    install -Dm0644 "$src/scripts/abora-ui.sh" \
      "$out/bin/abora-ui.sh"
    runHook postInstall
  '';

  meta = {
    description = "Check whether a machine looks ready for Abora OS hardware testing, standalone";
    mainProgram = "abora-hardware-test";
  };
}
