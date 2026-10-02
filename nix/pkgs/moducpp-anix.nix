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

  # builtins.path with a fixed name gives the source the SAME store path (and so the same derivation) wherever
  # it is evaluated from: the repo's own flake (which built the live ISO) or the copy the installer puts in
  # /etc/nixos. A plain path would be copied under its directory name, so the installed system would get a
  # different derivation and rebuild this Native AOT package from source (slow, and it runs out of memory in VMs).
  src = builtins.path { path = moducppAnixSrc; name = "moducpp-anix-src"; };

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
