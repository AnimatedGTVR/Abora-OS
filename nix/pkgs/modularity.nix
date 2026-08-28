{ stdenv
, lib
, autoPatchelfHook
, makeWrapper
, libsm
, libice
, libx11
, libxext
, libxrandr
, libxi
, libxinerama
, libxcursor
, ffmpeg_7
, vulkan-loader
, mono
, libsndfile
, opusfile
, libGL
, modularitySrc ?
    if builtins.pathExists ../vendor/modularity
    then ../vendor/modularity
    else ../../vendor/modularity
}:

# Packages a pre-built proprietary binary (vendor/modularity/bin/Modularity,
# not source built from here) -- dontBuild/dontConfigure skip Nix's normal
# build phases entirely, autoPatchelfHook rewrites the binary's dynamic
# linker/rpath to point at these Nix store paths instead of whatever paths
# it shipped with, and makeWrapper's --chdir makes the real binary always
# run with share/modularity/ as its working directory (it expects to find
# its Resources folder there via a relative path), while still exposing a
# plain `modularity` command on PATH.
stdenv.mkDerivation rec {
  pname = "modularity";
  version = "7.0.0";

  src = modularitySrc;

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];

  buildInputs = [
    libsm
    libice
    libx11
    libxext
    libxrandr
    libxi
    libxinerama
    libxcursor
    ffmpeg_7
    vulkan-loader
    mono
    libsndfile
    opusfile
    libGL
    stdenv.cc.cc.lib
  ];

  dontBuild = true;
  dontConfigure = true;

  installPhase =
    if builtins.pathExists (src + "/bin/Modularity") then ''
    runHook preInstall

    mkdir -p $out/bin $out/lib $out/share/modularity

    install -m 755 bin/Modularity $out/bin/.modularity-unwrapped
    if compgen -G "lib/*.so" >/dev/null; then
      cp lib/*.so $out/lib/
    fi

    if [ -d share/modularity/Resources ]; then
      cp -r share/modularity/Resources $out/share/modularity/
    fi

    makeWrapper $out/bin/.modularity-unwrapped $out/bin/modularity \
      --chdir "$out/share/modularity"

    runHook postInstall
  '' else ''
    runHook preInstall

    mkdir -p $out/bin $out/share/modularity
    if [ -d share/modularity/Resources ]; then
      cp -r share/modularity/Resources $out/share/modularity/
    fi
    cat > $out/bin/modularity <<'EOF'
#!/usr/bin/env bash
cat >&2 <<'MSG'
Modularity V7 is not bundled in this checkout yet.

Download the Modularity V7 Linux zip from Tareno Labs, then run:
  make setup-modularity ZIP=/path/to/Modularity-7.0.0-Linux.zip

After rebuilding Abora, run:
  modularity
MSG
exit 1
EOF
    chmod 0755 $out/bin/modularity

    runHook postInstall
  '';

  meta = with lib; {
    description = "Modularity game engine editor by Tareno Labs";
    homepage = "https://pak.moduengine.xyz/Tareno-Labs-LLC/Modularity";
    platforms = [ "x86_64-linux" ];
    license = licenses.unfree;
    maintainers = [];
  };
}
