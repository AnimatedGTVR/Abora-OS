{ stdenv
, lib
, autoPatchelfHook
, makeWrapper
, xorg
, ffmpeg_7
, vulkan-loader
, mono
, libsndfile
, opusfile
, libGL
}:

stdenv.mkDerivation rec {
  pname = "modularity";
  version = "1.0.0";

  src = ../../vendor/modularity;

  nativeBuildInputs = [ autoPatchelfHook makeWrapper ];

  buildInputs = [
    xorg.libSM
    xorg.libICE
    xorg.libX11
    xorg.libXext
    xorg.libXrandr
    xorg.libXi
    xorg.libXinerama
    xorg.libXcursor
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

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib $out/share/modularity

    install -m 755 bin/Modularity $out/bin/.modularity-unwrapped
    cp lib/*.so $out/lib/

    if [ -d share/modularity/Resources ]; then
      cp -r share/modularity/Resources $out/share/modularity/
    fi

    makeWrapper $out/bin/.modularity-unwrapped $out/bin/modularity \
      --chdir "$out/share/modularity"

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
