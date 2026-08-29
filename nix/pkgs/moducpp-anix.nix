{ lib
, stdenvNoCC
, makeWrapper
, bashInteractive
, gcc
, moducppAnixSrc ? ../../tools/moducpp-anix
}:
stdenvNoCC.mkDerivation {
  pname = "moducpp-anix";
  version = "1.0.0";

  src = moducppAnixSrc;

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm0755 "$src" "$out/bin/.moducpp-anix-unwrapped"

    # The script embeds the ANIX plan header itself (see tools/moducpp-anix)
    # and only needs a C++ compiler on PATH at run time — it has no
    # dependency on a Modularity source checkout, unlike the tool it started
    # as before that was fixed. CXX defaults to "c++" inside the script;
    # wrapping just makes sure a real one is reliably present.
    makeWrapper "$out/bin/.moducpp-anix-unwrapped" "$out/bin/moducpp-anix" \
      --prefix PATH : "${lib.makeBinPath [ bashInteractive gcc ]}"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Compiles a ModuCPP ANIX script and runs it, emitting an ANIX Plan on stdout";
    homepage = "https://github.com/AnimatedGTVR/Abora-OS";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "moducpp-anix";
  };
}
