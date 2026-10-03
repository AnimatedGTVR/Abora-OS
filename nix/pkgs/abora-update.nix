{ lib
, stdenvNoCC
, makeBinaryWrapper
, vanta
  # Two possible locations depending on whether this is evaluated from the
  # repo's own flake.nix (../../tools/...) or from an installed system's copy
  # under /etc/nixos/abora (../abora-update) -- the same dual-path pattern
  # abora-update-resolver.nix uses.
, updateSrc ?
    if builtins.pathExists ../../tools/abora-update
    then ../../tools/abora-update
    else ../abora-update
}:
# The Vanta core of `abora update` (tools/abora-update): release channel
# resolution and the downgrade guard today, with more of scripts/abora-update.sh
# moving here over time. Same CLI as the C# abora-update-resolver it replaces.
stdenvNoCC.mkDerivation {
  pname = "abora-update";
  version = "0.1.0";

  src = updateSrc;

  nativeBuildInputs = [ makeBinaryWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/abora-update"
    cp -R . "$out/share/abora-update/"
    rm -f "$out/share/abora-update/tests.vanta"
    # A compiled launcher (no shell script): `abora-update <args>` runs
    # `vanta run <share>/main.vanta <args>`.
    makeBinaryWrapper ${vanta}/bin/vanta "$out/bin/abora-update" \
      --add-flags "run $out/share/abora-update/main.vanta"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${vanta}/bin/vanta run ${updateSrc}/tests.vanta
    test "$("$out/bin/abora-update" resolve-ref --channel unstable --current-version 4.0)" = "$(printf 'edge\tunstable channel tracks edge')"
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Vanta core of abora update: channel resolution and downgrade guard";
    homepage = "https://github.com/AboraOS-Project/Abora-Labs";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    mainProgram = "abora-update";
  };
}
