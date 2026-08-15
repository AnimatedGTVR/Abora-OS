{ lib
, buildDotnetModule
, dotnetCorePackages
  # Two possible locations depending on whether this is evaluated from the
  # repo's own flake.nix (../../tools/...) or from an installed system's
  # copy under /etc/nixos/abora (../update-resolver) -- same dual-path
  # pattern nix/modules/installed-base.nix uses for mango/modularity.
, resolverSrc ?
    if builtins.pathExists ../../tools/abora-update-resolver
    then ../../tools/abora-update-resolver
    else ../update-resolver
}:
# scripts/abora-update.sh's version-resolution logic (tag_base_version,
# version_lt, resolve_update_ref's channel state machine,
# guard_against_accidental_downgrade) was a real decision tree over version
# strings and channels, done with nested bash case/sort -V string
# manipulation. This packages a C# port of just that pure decision logic
# (tools/abora-update-resolver, real xunit-tested) as a Native AOT binary --
# no .NET runtime needed at deploy time, single small self-contained
# executable, same as running any other CLI tool. All I/O (git ls-remote,
# reading VERSION, printing colored UI text) stays in bash; this binary
# only ever receives plain strings and returns a plain result plus an exit
# code -- see tools/abora-update-resolver/Program.cs.
buildDotnetModule rec {
  pname = "abora-update-resolver";
  version = "1.0.0";

  src = resolverSrc;

  projectFile = "AboraUpdateResolver.csproj";
  # Generated via `nuget-to-json` (nuget-to-nix's replacement in current
  # nixpkgs) -- requires network access this sandbox doesn't have. Run once
  # on a machine with Nix + network, from this directory:
  #   nix run nixpkgs#nuget-to-json -- . > ../../nix/pkgs/abora-update-resolver-deps.json
  # Check `nix run nixpkgs#nuget-to-json -- --help` first if that doesn't
  # work as-is -- the exact invocation has shifted across nixpkgs revisions.
  nugetDeps = ./abora-update-resolver-deps.json;

  dotnet-sdk = dotnetCorePackages.sdk_10_0;
  dotnet-runtime = dotnetCorePackages.runtime_10_0;

  selfContainedBuild = true;
  useAppHost = true;

  dotnetInstallFlags = [ "-p:PublishAot=true" ];
  dotnetPublishFlags = [ "-p:PublishAot=true" ];

  executables = [ "abora-update-resolver" ];

  meta = with lib; {
    description = "Pure version/channel resolution logic for abora update, extracted from bash";
    homepage = "https://github.com/AnimatedGTVR/Abora-OS";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "abora-update-resolver";
  };
}
