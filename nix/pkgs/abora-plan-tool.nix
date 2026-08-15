{ lib
, buildDotnetModule
, dotnetCorePackages
  # Two possible locations depending on whether this is evaluated from the
  # repo's own flake.nix (../../tools/...) or from an installed system's
  # copy under /etc/nixos/abora (../plan-tool) -- same dual-path pattern
  # nix/modules/installed-base.nix uses for mango/modularity/tinypm.
, toolSrc ?
    if builtins.pathExists ../../tools/abora-plan-tool
    then ../../tools/abora-plan-tool
    else ../plan-tool
}:
# anix.sh's validate_plan_json/apply_plan_json/do_diff_plan parsed and
# shape-validated ANIX Plan JSON through many small `jq` shell-outs (one
# subprocess per field per operation). This packages a C# port of just the
# JSON-shape validation (tools/abora-plan-tool, real xunit-tested) as a
# Native AOT binary -- no .NET runtime needed at deploy time. ANIX-specific
# business rules that must stay a single source of truth with other
# commands (feature_to_anix_key, do_set's per-key value validation) are
# deliberately NOT duplicated here -- see PlanParser.cs's doc comment.
buildDotnetModule rec {
  pname = "abora-plan-tool";
  version = "1.0.0";

  src = toolSrc;

  projectFile = "AboraPlanTool.csproj";
  # Generated via `nuget-to-json` (nuget-to-nix's replacement in current
  # nixpkgs) -- requires network access. Run once on a machine with Nix +
  # network, from this directory (same step as
  # nix/pkgs/abora-update-resolver.nix):
  #   nix run nixpkgs#nuget-to-json -- . > ../../nix/pkgs/abora-plan-tool-deps.json
  nugetDeps = ./abora-plan-tool-deps.json;

  dotnet-sdk = dotnetCorePackages.sdk_10_0;
  dotnet-runtime = dotnetCorePackages.runtime_10_0;

  selfContainedBuild = true;
  useAppHost = true;

  dotnetInstallFlags = [ "-p:PublishAot=true" ];
  dotnetPublishFlags = [ "-p:PublishAot=true" ];

  executables = [ "abora-plan-tool" ];

  meta = with lib; {
    description = "Structural validation for ANIX Plan JSON, extracted from bash";
    homepage = "https://github.com/AnimatedGTVR/Abora-OS";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "abora-plan-tool";
  };
}
