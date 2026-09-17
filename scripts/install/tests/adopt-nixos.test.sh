#!/usr/bin/env bash
# Behaviour tests for adopting an existing NixOS install (scripts/install/abora-adopt-nixos.sh).
#
# Run by scripts/check-scripts.py, one suite per Bash tool. These tests
# exercise Bash code directly (running it in sandboxes, or sourcing
# functions out of it), so they stay Bash until abora-adopt-nixos.sh itself
# is ported, then move to its new language with it.
set -euo pipefail
# shellcheck source=../../release/bash-testlib.sh
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../release" && pwd)/bash-testlib.sh"

adopt_help_out="$(scripts/abora-adopt-nixos.sh --help 2>&1)"

if printf '%s' "$adopt_help_out" | grep -q 'abora adopt-nixos' \
  && printf '%s' "$adopt_help_out" | grep -q 'without erasing /home' \
  && ./abora --help | grep -q 'abora adopt-nixos' \
  && grep -q 'abora.user.name = null;' scripts/abora-adopt-nixos.sh \
  && grep -q 'desktop="none"' scripts/abora-adopt-nixos.sh \
  && grep -q 'abora-backups' scripts/abora-adopt-nixos.sh \
  && grep -q 'sudo nixos-rebuild test' scripts/abora-adopt-nixos.sh \
  && grep -q 'aboraAdoptNixos = pkgs.writeShellScriptBin "abora-adopt-nixos"' nix/profiles/live.nix \
  && grep -q 'aboraAdoptNixos = pkgs.writeShellScriptBin "abora-adopt-nixos"' nix/modules/installed-base.nix \
  && grep -q '"abora/adopt-nixos.sh"' nix/profiles/live.nix \
  && grep -q '"abora/adopt-nixos.sh"' nix/modules/installed-base.nix; then
  pass "runtime: existing NixOS adoption path is non-destructive by default"
else
  fail "runtime: existing NixOS adoption path is non-destructive by default"
fi

# Regression test: abora-adopt-nixos.sh's copy list used to cover barely
# half of what nix/modules/installed-base.nix unconditionally requires
# (its own header comment: "the installer copies every required file via
# cp_required before the first nixos-rebuild, so the ./x paths are always
# present" -- true for the real installer's write_branding_assets(), but
# abora-adopt-nixos.sh has its own separate, hand-maintained copy list
# that had drifted, missing ~15 required files/dirs including
# adopt-nixos.sh itself, plus a destination-name bug (wallpaper-themes
# instead of the themes name installed-base.nix actually looks for) and a
# missing-parent-directory bug in copy_if_exists() (vendor/modularity and
# tools/moducpp-anix both failed to copy: "cp: cannot create directory").
# `sudo abora adopt-nixos --apply` followed by its own documented next
# step (`sudo nixos-rebuild test`) could not have completed a real
# adoption before this fix, regardless of the configuration.nix fixes
# made separately. This runs the real copy logic (not a copy of it)
# against this real repo checkout into a sandboxed directory, and checks
# every required destination path installed-base.nix's own source
# actually demands.
if command -v python3 >/dev/null 2>&1; then
  _required_dests="$(python3 -c "
import re
text = open('nix/modules/installed-base.nix').read()
let_block = text.split('\nin\n')[0]
lines = let_block.splitlines()
required = []
i = 0
while i < len(lines):
    m = re.match(r'\s*(\w+)\s*=\s*(.*)', lines[i])
    if m:
        name, rhs = m.groups()
        chunk = rhs
        j = i
        while ';' not in chunk and j < len(lines) - 1:
            j += 1
            chunk += ' ' + lines[j]
        if 'pathExists' not in chunk:
            paths = re.findall(r'\./([A-Za-z0-9_./-]+)', chunk)
            required += paths
    i += 1
print('\n'.join(sorted(set(required))))
")"

  tmp_adopt_copy="$(mktemp)"
  {
    sed -n '/^copy_if_exists() {/,/^}$/p' scripts/abora-adopt-nixos.sh
    sed -n '/^abora_dir="\$config_dir\/abora"$/,/^cat > "\$target_import"/p' scripts/abora-adopt-nixos.sh | sed '$d'
  } > "$tmp_adopt_copy"
  tmp_adopt_target="$(mktemp -d)"
  if bash -n "$tmp_adopt_copy" 2>/dev/null \
    && ( repo_dir="$repo_dir"; config_dir="$tmp_adopt_target"; source "$tmp_adopt_copy" ) >/dev/null 2>&1; then
    adopt_copy_ok=1
    while IFS= read -r required_path; do
      [[ -n "$required_path" ]] || continue
      if [[ ! -e "$tmp_adopt_target/abora/$required_path" ]]; then
        adopt_copy_ok=0
        printf '              missing after copy: abora/%s\n' "$required_path"
      fi
    done <<<"$_required_dests"
  else
    adopt_copy_ok=0
    printf '              copy logic itself failed to run\n'
  fi
  rm -f "$tmp_adopt_copy"
  rm -rf "$tmp_adopt_target"

  if [[ "$adopt_copy_ok" -eq 1 ]]; then
    pass "runtime: abora-adopt-nixos.sh copies every file installed-base.nix requires"
  else
    fail "runtime: abora-adopt-nixos.sh copies every file installed-base.nix requires"
  fi
fi

# Regression test: abora-adopt-nixos.sh's backup step used to crash on
# every run after the first against the same --config-dir. It backs up
# $config_dir into $config_dir/abora-backups/<timestamp>/ -- but from the
# second run onward, $config_dir already contains every prior backup, so
# `cp -a "$config_dir"/. "$backup_dir"/` tries to copy that whole tree
# (including the fresh, now-nested backup_dir itself) into itself. GNU cp
# detects this and refuses ("cp: cannot copy a directory ... into
# itself"), returning non-zero, which set -euo pipefail turns into the
# entire script aborting right there -- before any of the real adoption
# work (the file copies checked above) ever runs. Exercises the real
# backup logic for real, three runs in a row against the same directory,
# confirming it doesn't abort and doesn't grow backups inside backups.
tmp_backup_dir="$(mktemp -d)"

printf 'test config\n' > "$tmp_backup_dir/configuration.nix"

tmp_backup_snippet="$(mktemp)"

awk '/^timestamp="\$\(date \+%Y%m%d-%H%M%S\)"$/{p=1} p{print} p && /-exec cp -a/{exit}' \
  scripts/abora-adopt-nixos.sh > "$tmp_backup_snippet"

backup_all_ok=1

if [[ -s "$tmp_backup_snippet" ]] && bash -n "$tmp_backup_snippet" 2>/dev/null; then
  for run in 1 2 3; do
    if ! ( config_dir="$tmp_backup_dir"; set -euo pipefail; source "$tmp_backup_snippet" ) >/dev/null 2>&1; then
      backup_all_ok=0
    fi
    sleep 1.1
  done
  backup_count="$(find "$tmp_backup_dir/abora-backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
  [[ "$backup_count" -eq 3 ]] || backup_all_ok=0
  nested_count="$(find "$tmp_backup_dir/abora-backups" -mindepth 2 -maxdepth 2 -type d -name 'abora-backups' 2>/dev/null | wc -l)"
  [[ "$nested_count" -eq 0 ]] || backup_all_ok=0
else
  backup_all_ok=0
fi

rm -f "$tmp_backup_snippet"

rm -rf "$tmp_backup_dir"

if [[ "$backup_all_ok" -eq 1 ]]; then
  pass "runtime: abora-adopt-nixos.sh's backup step survives repeated runs against the same config-dir"
else
  fail "runtime: abora-adopt-nixos.sh's backup step survives repeated runs against the same config-dir"
fi

# Regression test for ensure_import_in_configuration(): both of its
# branches used to produce a real syntax/semantic break on the *standard*
# nixos-generate-config output shape (function header on its own line,
# "imports =" and its "[" on separate lines) -- inserting right after
# "imports =" landed the new path *before* the "[", which Nix parses as
# function application (`imports = ./abora-adopt.nix [ ... ];` calls the
# path as a function) rather than list concatenation; the "no imports at
# all" fallback replaced the *first* "{" in the file, which for the
# standard format is the function argument list's own brace, not the
# config body's, producing a hard parse error. Extracts the real function
# (it can't be sourced wholesale -- this script parses its own $@ at load
# time) and confirms the real `nix-instantiate` can both parse and
# evaluate the result for four real shapes: multi-line imports (the
# standard shape), single-line imports, a function-header body with no
# imports at all, and a bare attrset with no function header and no
# imports.
if command -v nix-instantiate >/dev/null 2>&1; then
  tmp_adopt_fn="$(mktemp)"
  awk '/^ensure_import_in_configuration\(\) \{/{p=1} p{print} p && /^}$/{exit}' \
    scripts/abora-adopt-nixos.sh > "$tmp_adopt_fn"
  tmp_adopt_dir="$(mktemp -d)"

  cat > "$tmp_adopt_dir/multiline.nix" <<'EOF'
{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  boot.loader.systemd-boot.enable = true;
}
EOF
  cat > "$tmp_adopt_dir/singleline.nix" <<'EOF'
{ config, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];
  boot.loader.systemd-boot.enable = true;
}
EOF
  cat > "$tmp_adopt_dir/noimports-header.nix" <<'EOF'
{ config, pkgs, ... }:

{
  boot.loader.systemd-boot.enable = true;
}
EOF
  cat > "$tmp_adopt_dir/noimports-bare.nix" <<'EOF'
{
  boot.loader.systemd-boot.enable = true;
}
EOF
  printf '{ imports = [ ]; }\n' > "$tmp_adopt_dir/abora-adopt.nix"

  adopt_all_ok=1
  for shape in multiline singleline noimports-header noimports-bare; do
    cp "$tmp_adopt_dir/$shape.nix" "$tmp_adopt_dir/configuration.nix"
    if ! ( configuration_nix="$tmp_adopt_dir/configuration.nix"; source "$tmp_adopt_fn"; ensure_import_in_configuration ) \
      || ! nix-instantiate --parse "$tmp_adopt_dir/configuration.nix" >/dev/null 2>&1 \
      || ! nix-instantiate --eval -E \
           "let raw = import $tmp_adopt_dir/configuration.nix; cfg = if builtins.isFunction raw then raw { config = {}; pkgs = {}; lib = (import <nixpkgs> {}).lib; } else raw; in builtins.length cfg.imports" \
           >/dev/null 2>&1; then
      adopt_all_ok=0
      printf '              %s shape failed to parse/eval after ensure_import_in_configuration\n' "$shape"
    fi
    rm -f "$tmp_adopt_dir/configuration.nix"
  done
  rm -f "$tmp_adopt_fn"
  rm -rf "$tmp_adopt_dir"

  if [[ "$adopt_all_ok" -eq 1 ]]; then
    pass "runtime: ensure_import_in_configuration produces valid Nix for standard configuration.nix shapes"
  else
    fail "runtime: ensure_import_in_configuration produces valid Nix for standard configuration.nix shapes"
  fi
fi

# The interactive wizard (run with zero args) is a real, separate code path
# from the flag-based one above -- exercise it for real rather than just
# grepping source, same as the rest of this file's "runtime:" checks.
tmp_adopt_wizard="$(mktemp -d)"

printf '{ ... }:\n{\n}\n' > "$tmp_adopt_wizard/configuration.nix"

adopt_wizard_out="$(
  printf 'gnome\ny\nn\n' \
    | ABORA_ASSUME_NIXOS=1 ABORA_SYSTEM_CONFIG="$tmp_adopt_wizard" \
      scripts/abora-adopt-nixos.sh 2>&1
)"

rm -rf "$tmp_adopt_wizard"

if printf '%s' "$adopt_wizard_out" | grep -q 'Abora NixOS Adoption Wizard' \
  && printf '%s' "$adopt_wizard_out" | grep -q 'Desktop profile : gnome' \
  && printf '%s' "$adopt_wizard_out" | grep -q 'Gaming layer    : enabled' \
  && printf '%s' "$adopt_wizard_out" | grep -q 'No changes made' \
  && grep -q 'run_interactive_wizard' scripts/abora-adopt-nixos.sh \
  && grep -q 'abora.gaming.enable = \$(' scripts/abora-adopt-nixos.sh \
  && grep -q 'abora.gaming.steam = \$(' scripts/abora-adopt-nixos.sh \
  && grep -q 'abora.gaming.controllerSupport = \$(' scripts/abora-adopt-nixos.sh \
  && grep -q 'abora.gaming.mangohud = \$(' scripts/abora-adopt-nixos.sh \
  && grep -q 'abora.gaming.gamemode = \$(' scripts/abora-adopt-nixos.sh \
  && grep -q 'abora.gaming.launchers = \$(' scripts/abora-adopt-nixos.sh \
  && grep -q 'exec sudo "\$0" --apply' scripts/abora-adopt-nixos.sh \
  && grep -q 'exec "\$clone_dir/abora" adopt-nixos' scripts/abora-adopt-bootstrap.sh; then
  pass "runtime: adopt-nixos interactive wizard asks desktop/gaming and confirms before applying"
else
  fail "runtime: adopt-nixos interactive wizard asks desktop/gaming and confirms before applying"
fi

testlib_finish
