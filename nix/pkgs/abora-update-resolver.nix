{ writeShellScriptBin, ... }:
# Removed in 4.2: abora-update (tools/abora-update) has the same CLI. This file stays because the
# updaters installed on 4.0/4.1 require it (scripts/release/legacy-required-paths.txt), and an older
# installed-base.nix restored by a rollback may still call it, so it forwards instead of failing.
writeShellScriptBin "abora-update-resolver" ''
  exec abora-update "$@"
''
