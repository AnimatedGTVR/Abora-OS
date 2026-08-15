{ lib
, stdenvNoCC
, makeWrapper
, bashInteractive
, coreutils
, diffutils
, findutils
, gawk
, git
, gnugrep
, gnused
, jq
, moducpp-anix
, nix
, procps
, util-linux
, rustPlatform
}:
let
  tinypmDir = ../../vendor/tinypm;
  # See nix/profiles/live.nix for the same derivation and the rationale:
  # TinyPM is a real Rust crate now (tinypm + grab binaries), not a
  # per-user bash install -- it just needs to be on PATH.
  tinypmPackage = rustPlatform.buildRustPackage {
    pname = "tinypm";
    version = "0.8.1-alpha";
    src = tinypmDir;
    cargoLock.lockFile = tinypmDir + "/Cargo.lock";
    doCheck = false;
  };
in
# The flake-native equivalent of package-anix.sh's standalone tarball: same
# share/anix/ layout and same ANIX_* env vars anix.sh reads for its
# docs/languages/tinypm/wallpaper paths, but wired via makeWrapper (--set/
# --prefix PATH) instead of a generated shell wrapper script, so a plain
# `nix profile install github:.../Abora-OS#anix` (or importing
# abora.nixosModules.anix) gets a working `anix` command with no separate
# install.sh step.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "anix";
  version = "1.0.5-demo";

  src = ../../.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/anix/docs/wiki" "$out/share/anix/assets" "$out/share/anix/languages"

    install -Dm0755 "$src/scripts/anix.sh" "$out/share/anix/anix.sh"
    install -Dm0644 "$src/scripts/abora-ui.sh" "$out/share/anix/abora-ui.sh"
    install -Dm0644 "$src/nix/modules/anix.nix" "$out/share/anix/anix-module.nix"

    install -Dm0644 "$src/docs/wiki/ANIX-V1.md" "$out/share/anix/docs/wiki/ANIX-V1.md"
    install -Dm0644 "$src/docs/wiki/TinyPM.md" "$out/share/anix/docs/wiki/TinyPM.md"
    install -Dm0644 "$src/docs/wiki/Abora-Tools.md" "$out/share/anix/docs/wiki/Abora-Tools.md"
    install -Dm0644 "$src/docs/wiki/Recovery.md" "$out/share/anix/docs/wiki/Recovery.md"
    install -Dm0644 "$src/docs/wiki/ANIX-V2-Languages.md" "$out/share/anix/docs/wiki/ANIX-V2-Languages.md"
    install -Dm0644 "$src/docs/wiki/Abora-Gaming.md" "$out/share/anix/docs/wiki/Abora-Gaming.md"

    if [ -d "$src/assets/anix-languages" ]; then
      cp -a "$src/assets/anix-languages/." "$out/share/anix/languages/"
    fi

    if [ -d "$src/assets/wallpapers/collection" ]; then
      mkdir -p "$out/share/anix/wallpapers"
      cp -a "$src/assets/wallpapers/collection/." "$out/share/anix/wallpapers/"
    fi

    if [ -f "$src/assets/Effects/v3StartingAbora.mp3" ]; then
      mkdir -p "$out/share/anix/effects"
      install -Dm0644 "$src/assets/Effects/v3StartingAbora.mp3" \
        "$out/share/anix/effects/v3StartingAbora.mp3"
    fi

    makeWrapper "${bashInteractive}/bin/bash" "$out/bin/anix" \
      --add-flags "$out/share/anix/anix.sh" \
      --prefix PATH : "${lib.makeBinPath [
        bashInteractive
        coreutils
        diffutils
        findutils
        gawk
        git
        gnugrep
        gnused
        jq
        moducpp-anix
        nix
        procps
        util-linux
        tinypmPackage
      ]}" \
      --set ANIX_UI_LIB "$out/share/anix/abora-ui.sh" \
      --set ANIX_DOCS_DIR "$out/share/anix/docs/wiki" \
      --set ANIX_SYSTEM_LANGUAGE_DIR "$out/share/anix/languages" \
      --set ANIX_WALLPAPER_DIR "$out/share/anix/wallpapers" \
      --set ANIX_SOUND_FILE "$out/share/anix/effects/v3StartingAbora.mp3"

    cat > "$out/share/anix/README.md" <<'EOF'
    ANIX standalone package

    CLI:
      anix

    Standalone module path:
      $out/share/anix/anix-module.nix

    Flake users can also consume this repository directly:
      inputs.abora.url = "github:AnimatedGTVR/Abora-OS";
      imports = [ abora.nixosModules.anix ];
      environment.systemPackages = [ abora.packages.''${pkgs.system}.anix ];
    EOF

    runHook postInstall
  '';

  meta = with lib; {
    description = "Friendly NixOS profile and rebuild helper";
    homepage = "https://github.com/AnimatedGTVR/Abora-OS";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "anix";
  };
})
