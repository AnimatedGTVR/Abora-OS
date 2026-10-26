{ lib
, rustPlatform
  # From the repo's flake (../../tools/...) or an installed system's copy
  # under /etc/nixos/abora (../plan-tool).
, toolSrc ?
    if builtins.pathExists ../../tools/abora-plan-tool
    then ../../tools/abora-plan-tool
    else ../plan-tool
}:
# Shape validation for ANIX Plan JSON and the ANIX Native parser, used by
# anix.sh (validate-plan, diff-plan, apply-plan, run). Rust since 4.2; it
# replaced a C# Native AOT build with the same name and CLI.
rustPlatform.buildRustPackage {
  pname = "abora-plan-tool";
  version = "2.0.0";

  # A fixed name gives the source the same store path from the repo's flake and
  # from the installed copy, so installed systems reuse the ISO's build.
  src = builtins.path { path = toolSrc; name = "abora-plan-tool-src"; };
  cargoLock.lockFile = toolSrc + "/Cargo.lock";

  meta = with lib; {
    description = "Shape validation for ANIX Plan JSON, and ANIX Native to Plan JSON";
    homepage = "https://github.com/Abora-OS/Abora-OS";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "abora-plan-tool";
  };
}
