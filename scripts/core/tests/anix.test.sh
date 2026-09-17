#!/usr/bin/env bash
# Behaviour tests for ANIX (scripts/core/anix.sh).
#
# Run by scripts/check-scripts.py, one suite per Bash tool. These tests
# exercise Bash code directly (running it in sandboxes, or sourcing
# functions out of it), so they stay Bash until anix.sh itself
# is ported, then move to its new language with it.
set -euo pipefail
# shellcheck source=../../release/bash-testlib.sh
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../release" && pwd)/bash-testlib.sh"

# ── anix.sh end-to-end behavior tests ──────────────────────────────────────────
# Each block below runs the real scripts/anix.sh against a throwaway
# ANIX_SYSTEM_CONFIG directory (ANIX_NO_SUDO/ANIX_ASSUME_YES bypass root and
# prompts — see anix.sh's confirm()/run_as_root()), then asserts on the
# actual file/git state it produced, not just its printed output.
tmp_anix="$tmp_ok/anix.nix"

printf '%s\n' \
  '{ ... }:' \
  '{' \
  '  anix.enable = true;' \
  '  anix.hostname = "testbox";' \
  '  anix.timezone = "UTC";' \
  '  anix.keyboard.console = "us";' \
  '  anix.keyboard.xkb = "us";' \
  '  anix.desktop = "gnome";' \
  '  anix.wallpaper = "titlis-alps.jpg";' \
  '}' > "$tmp_anix"

anix_output="$(
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  ANIX_CONFIG_FILE="$tmp_anix" \
  ANIX_SYSTEM_CONFIG="$tmp_ok" \
  scripts/anix.sh show 2>&1
)"

if printf '%s' "$anix_output" | grep -q "testbox" \
  && printf '%s' "$anix_output" | grep -q "titlis-alps.jpg"; then
  pass "runtime: anix fallback UI show"
else
  fail "runtime: anix fallback UI show"
fi

tmp_anix_config_dir="$tmp_ok/anix-config"

mkdir -p "$tmp_anix_config_dir"

if ANIX_NO_SUDO=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_config_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh config set snapshots.push true >/dev/null \
  && grep -q "snapshots.push=true" "$tmp_anix_config_dir/.anix/config"; then
  pass "runtime: anix tool config set"
else
  fail "runtime: anix tool config set"
fi

tmp_anix_quickstart_dir="$tmp_ok/anix-quickstart"

if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_quickstart_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh quickstart >/dev/null \
  && [[ -f "$tmp_anix_quickstart_dir/anix.nix" ]] \
  && git -C "$tmp_anix_quickstart_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  pass "runtime: anix quickstart"
else
  fail "runtime: anix quickstart"
fi

anix_docs_output="$(
  ANIX_NO_SUDO=1 \
    ANIX_SYSTEM_CONFIG="$tmp_anix_quickstart_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh docs 2>&1
)"

if printf '%s' "$anix_docs_output" | grep -q "ANIX-V1"; then
  pass "runtime: anix docs"
else
  fail "runtime: anix docs"
fi

tmp_anix_save_dir="$tmp_ok/anix-save"

mkdir -p "$tmp_anix_save_dir"

printf '%s\n' '{ ... }: { networking.hostName = "testbox"; }' > "$tmp_anix_save_dir/configuration.nix"

if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_save_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh save "anix: test snapshot" >/dev/null \
  && git -C "$tmp_anix_save_dir" log --oneline -1 | grep -q "anix: test snapshot"; then
  pass "runtime: anix local snapshot"
else
  fail "runtime: anix local snapshot"
fi

tmp_anix_switch_dir="$tmp_ok/anix-switch"

tmp_anix_bin="$tmp_ok/anix-bin"

tmp_anix_log="$tmp_ok/anix-rebuild.log"

mkdir -p "$tmp_anix_switch_dir" "$tmp_anix_bin"

printf '%s\n' \
  '{' \
  '  outputs = { nixpkgs, ... }: {' \
  '    nixosConfigurations = {' \
  '      gaming = nixpkgs.lib.nixosSystem { system = "x86_64-linux"; modules = [ ]; };' \
  '    };' \
  '  };' \
  '}' > "$tmp_anix_switch_dir/flake.nix"

git -C "$tmp_anix_switch_dir" -c init.defaultBranch=main init >/dev/null

git -C "$tmp_anix_switch_dir" -c user.name=ANIX -c user.email=anix@localhost add -A

git -C "$tmp_anix_switch_dir" -c user.name=ANIX -c user.email=anix@localhost commit -m "initial" >/dev/null

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >> "$ANIX_REBUILD_LOG"' > "$tmp_anix_bin/nixos-rebuild"

chmod +x "$tmp_anix_bin/nixos-rebuild"

if PATH="$tmp_anix_bin:$PATH" \
  ANIX_REBUILD_LOG="$tmp_anix_log" \
  ANIX_NO_SUDO=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_switch_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh switch nix gaming --now >/dev/null \
  && grep -q "switch --flake ${tmp_anix_switch_dir}#gaming" "$tmp_anix_log"; then
  pass "runtime: anix switch maps flake profile"
else
  fail "runtime: anix switch maps flake profile"
fi

# `anix switch nix` (family only, no profile) must fall through to the
# "Usage: anix switch nix <profile> [--now]" message rather than misreading
# the leftover "nix" positional as an unrecognized --flag.
anix_switch_family_only_output="$(
  PATH="$tmp_anix_bin:$PATH" \
    ANIX_NO_SUDO=1 \
    ANIX_SYSTEM_CONFIG="$tmp_anix_switch_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh switch nix 2>&1 || true
)"

if printf '%s' "$anix_switch_family_only_output" | grep -q "Usage: anix switch nix <profile>" \
  && ! printf '%s' "$anix_switch_family_only_output" | grep -q "Unknown switch option"; then
  pass "runtime: anix switch with family only shows usage"
else
  fail "runtime: anix switch with family only shows usage"
fi

# Simulates the "git needs root" case (a repo owned by a different UID —
# git calls this "dubious ownership" and refuses to operate as the invoking
# user): the fake `git` here fails for the calling user but succeeds via
# ANIX_ROOT_PATH's copy, exercising stage_config_for_flake()'s run_as_root
# fallback rather than just the happy path where a single git works for both.
tmp_anix_untracked_dir="$tmp_ok/anix-untracked-flake"

tmp_anix_untracked_bin="$tmp_ok/anix-untracked-bin"

tmp_anix_untracked_rootbin="$tmp_ok/anix-untracked-rootbin"

mkdir -p "$tmp_anix_untracked_dir" "$tmp_anix_untracked_bin" "$tmp_anix_untracked_rootbin"

git -C "$tmp_anix_untracked_dir" -c init.defaultBranch=main init >/dev/null

printf '%s\n' \
  '{' \
  '  outputs = { nixpkgs, ... }: {' \
  '    nixosConfigurations.abora = nixpkgs.lib.nixosSystem { system = "x86_64-linux"; modules = [ ]; };' \
  '  };' \
  '}' > "$tmp_anix_untracked_dir/flake.nix"

printf '%s\n' '{ ... }: { anix.hostname = "tracked"; }' > "$tmp_anix_untracked_dir/anix.nix"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [[ "${ANIX_FAKE_GIT_NEEDS_ROOT:-0}" == 1 ]]; then' \
  '  printf "dubious ownership\n" >&2' \
  '  exit 128' \
  'fi' \
  "exec $(command -v git) \"\$@\"" > "$tmp_anix_untracked_bin/git"

chmod +x "$tmp_anix_untracked_bin/git"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  "exec $(command -v git) \"\$@\"" > "$tmp_anix_untracked_rootbin/git"

chmod +x "$tmp_anix_untracked_rootbin/git"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'target=""' \
  'while [[ $# -gt 0 ]]; do' \
  '  case "$1" in --flake) shift; target="${1%%#*}" ;; esac' \
  '  shift || true' \
  'done' \
  'git -C "$target" ls-files --error-unmatch flake.nix >/dev/null' > "$tmp_anix_untracked_bin/nixos-rebuild"

chmod +x "$tmp_anix_untracked_bin/nixos-rebuild"

cp "$tmp_anix_untracked_bin/nixos-rebuild" "$tmp_anix_untracked_rootbin/nixos-rebuild"

if PATH="$tmp_anix_untracked_bin:$PATH" \
  ANIX_FAKE_GIT_NEEDS_ROOT=1 \
  ANIX_ROOT_PATH="$tmp_anix_untracked_rootbin:$PATH" \
  ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_untracked_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh apply >/dev/null 2>&1; then
  pass "runtime: anix stages untracked flake before apply"
else
  fail "runtime: anix stages untracked flake before apply"
fi

tmp_anix_pkgs_dir="$tmp_ok/anix-pkgs-header"

tmp_anix_pkgs_bin="$tmp_ok/anix-pkgs-bin"

mkdir -p "$tmp_anix_pkgs_dir" "$tmp_anix_pkgs_bin"

printf '%s\n' \
  '{' \
  '  outputs = { nixpkgs, ... }: {' \
  '    nixosConfigurations.abora = nixpkgs.lib.nixosSystem { system = "x86_64-linux"; modules = [ ]; };' \
  '  };' \
  '}' > "$tmp_anix_pkgs_dir/flake.nix"

printf '%s\n' \
  '{ ... }:' \
  '{' \
  '  anix.enable = true;' \
  '  anix.packages = with pkgs; [ git ];' \
  '}' > "$tmp_anix_pkgs_dir/anix.nix"

git -C "$tmp_anix_pkgs_dir" -c init.defaultBranch=main init >/dev/null

git -C "$tmp_anix_pkgs_dir" -c user.name=ANIX -c user.email=anix@localhost add -A

git -C "$tmp_anix_pkgs_dir" -c user.name=ANIX -c user.email=anix@localhost commit -m "initial" >/dev/null

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'target=""' \
  'while [[ $# -gt 0 ]]; do' \
  '  case "$1" in --flake) shift; target="${1%%#*}" ;; esac' \
  '  shift || true' \
  'done' \
  'grep -Eq "^[[:space:]]*\\{[[:space:]]*pkgs,[[:space:]]*\\.\\.\\.[[:space:]]*\\}:" "$target/anix.nix"' > "$tmp_anix_pkgs_bin/nixos-rebuild"

chmod +x "$tmp_anix_pkgs_bin/nixos-rebuild"

if PATH="$tmp_anix_pkgs_bin:$PATH" \
  ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_pkgs_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh apply >/dev/null 2>&1; then
  pass "runtime: anix repairs pkgs module argument before apply"
else
  fail "runtime: anix repairs pkgs module argument before apply"
fi

anix_profiles_output="$(
  PATH="$tmp_anix_bin:$PATH" \
    ANIX_NO_SUDO=1 \
    ANIX_SYSTEM_CONFIG="$tmp_anix_switch_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh profiles 2>&1
)"

if PATH="$tmp_anix_bin:$PATH" \
  ANIX_NO_SUDO=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_switch_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh status >/dev/null \
  && printf '%s' "$anix_profiles_output" | grep -q "gaming"; then
  pass "runtime: anix status and profiles"
else
  fail "runtime: anix status and profiles"
fi

if PATH="$tmp_anix_bin:$PATH" \
  ANIX_REBUILD_LOG="$tmp_anix_log" \
  ANIX_NO_SUDO=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_switch_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh test nix gaming >/dev/null \
  && grep -q "test --flake ${tmp_anix_switch_dir}#gaming" "$tmp_anix_log"; then
  pass "runtime: anix test activation"
else
  fail "runtime: anix test activation"
fi

if PATH="$tmp_anix_bin:$PATH" \
  ANIX_REBUILD_LOG="$tmp_anix_log" \
  ANIX_NO_SUDO=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_switch_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh boot nix gaming >/dev/null \
  && grep -q "boot --flake ${tmp_anix_switch_dir}#gaming" "$tmp_anix_log"; then
  pass "runtime: anix boot activation"
else
  fail "runtime: anix boot activation"
fi

if PATH="$tmp_anix_bin:$PATH" \
  ANIX_REBUILD_LOG="$tmp_anix_log" \
  ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_switch_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh rollback nix --now >/dev/null \
  && grep -q "switch --rollback" "$tmp_anix_log"; then
  pass "runtime: anix generation rollback"
else
  fail "runtime: anix generation rollback"
fi

if [[ -n "$plan_tool_bin" ]]; then
export ABORA_PLAN_TOOL_BIN="$plan_tool_bin"
tmp_anix_plan_dir="$tmp_ok/anix-plan"
mkdir -p "$tmp_anix_plan_dir"

anix_plan_json='{"planVersion":1,"language":"test","operations":[{"op":"set","key":"hostname","value":"planhost"},{"op":"enable","feature":"bluetooth"},{"op":"enable","feature":"gaming"},{"op":"enable","feature":"gaming.steam"},{"op":"enable","feature":"gaming.big-picture"},{"op":"enable","feature":"gaming.controllers"},{"op":"enable","feature":"gaming.mangohud"},{"op":"enable","feature":"gaming.gamemode"},{"op":"enable","feature":"gaming.vulkan"},{"op":"enable","feature":"gaming.launchers"},{"op":"package.add","name":"firefox"}]}'
printf '%s' "$anix_plan_json" > "$tmp_anix_plan_dir/plan.json"
if ANIX_SYSTEM_CONFIG="$tmp_anix_plan_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh validate-plan "$tmp_anix_plan_dir/plan.json" >/dev/null; then
  pass "runtime: anix validate-plan accepts a well-formed plan"
else
  fail "runtime: anix validate-plan accepts a well-formed plan"
fi

anix_bad_plan_json='{"planVersion":1,"language":"test","operations":[{"op":"set","key":"not-a-real-key","value":"x"}]}'

printf '%s' "$anix_bad_plan_json" > "$tmp_anix_plan_dir/bad-plan.json"

if ANIX_SYSTEM_CONFIG="$tmp_anix_plan_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh validate-plan "$tmp_anix_plan_dir/bad-plan.json" >/dev/null 2>&1; then
  fail "runtime: anix validate-plan rejects an unknown set key"
else
  pass "runtime: anix validate-plan rejects an unknown set key"
fi

tmp_anix_apply_plan_dir="$tmp_ok/anix-apply-plan"

mkdir -p "$tmp_anix_apply_plan_dir"

if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_apply_plan_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh apply-plan "$tmp_anix_plan_dir/plan.json" --yes >/dev/null 2>&1; then
  :
fi

if grep -Eq 'anix\.hostname[[:space:]]*=[[:space:]]*"planhost"' "$tmp_anix_apply_plan_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.services\.bluetooth[[:space:]]*=[[:space:]]*true' "$tmp_anix_apply_plan_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.enable[[:space:]]*=[[:space:]]*true' "$tmp_anix_apply_plan_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.steam[[:space:]]*=[[:space:]]*true' "$tmp_anix_apply_plan_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.bigPictureShortcut[[:space:]]*=[[:space:]]*true' "$tmp_anix_apply_plan_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.controllerSupport[[:space:]]*=[[:space:]]*true' "$tmp_anix_apply_plan_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.vulkanTools[[:space:]]*=[[:space:]]*true' "$tmp_anix_apply_plan_dir/anix.nix" 2>/dev/null; then
  pass "runtime: anix apply-plan writes every operation as one transaction"
else
  fail "runtime: anix apply-plan writes every operation as one transaction"
fi

tmp_anix_gaming_deps_dir="$tmp_ok/anix-gaming-deps"

mkdir -p "$tmp_anix_gaming_deps_dir"

if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_gaming_deps_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh enable gaming.big-picture >/dev/null 2>&1 \
  && grep -Eq 'anix\.gaming\.enable[[:space:]]*=[[:space:]]*true' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.steam[[:space:]]*=[[:space:]]*true' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.bigPictureShortcut[[:space:]]*=[[:space:]]*true' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && ANIX_NO_SUDO=1 \
    ANIX_ASSUME_YES=1 \
    ANIX_SYSTEM_CONFIG="$tmp_anix_gaming_deps_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh enable gaming.autostart >/dev/null 2>&1 \
  && grep -Eq 'anix\.gaming\.bigPictureAutostart[[:space:]]*=[[:space:]]*true' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && ANIX_NO_SUDO=1 \
    ANIX_ASSUME_YES=1 \
    ANIX_SYSTEM_CONFIG="$tmp_anix_gaming_deps_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh enable gaming.gamescope >/dev/null 2>&1 \
  && grep -Eq 'anix\.gaming\.gamescopeSession[[:space:]]*=[[:space:]]*true' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && ANIX_NO_SUDO=1 \
    ANIX_ASSUME_YES=1 \
    ANIX_SYSTEM_CONFIG="$tmp_anix_gaming_deps_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh disable gaming.steam >/dev/null 2>&1 \
  && grep -Eq 'anix\.gaming\.steam[[:space:]]*=[[:space:]]*false' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.bigPictureShortcut[[:space:]]*=[[:space:]]*false' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.bigPictureAutostart[[:space:]]*=[[:space:]]*false' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.gamescopeSession[[:space:]]*=[[:space:]]*false' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.controllerSupport[[:space:]]*=[[:space:]]*false' "$tmp_anix_gaming_deps_dir/anix.nix" 2>/dev/null; then
  pass "runtime: anix gaming toggles enable and disable required parent options"
else
  fail "runtime: anix gaming toggles enable and disable required parent options"
fi

tmp_anix_native_dir="$tmp_ok/anix-native-plan"

mkdir -p "$tmp_anix_native_dir"

printf '%s\n' \
  'set hostname nativehost' \
  'enable bluetooth' \
  'package add git' > "$tmp_anix_native_dir/plan.anix"

if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_native_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh run "$tmp_anix_native_dir/plan.anix" --yes >/dev/null 2>&1; then
  :
fi

if grep -Eq 'anix\.hostname[[:space:]]*=[[:space:]]*"nativehost"' "$tmp_anix_native_dir/anix.nix" 2>/dev/null \
  && grep -q "git" "$tmp_anix_native_dir/anix.nix" 2>/dev/null; then
  pass "runtime: anix run applies a .anix Native file as one plan"
else
  fail "runtime: anix run applies a .anix Native file as one plan"
fi

# `anix run <file> --language` with no value after --language must print the
# usage message, not crash silently: the old `shift 2` failed under `set -e`
# when only one positional remained, exiting with no output at all.
anix_run_missing_lang_value_out="$(
  ANIX_NO_SUDO=1 \
    ANIX_ASSUME_YES=1 \
    ANIX_SYSTEM_CONFIG="$tmp_anix_native_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh run "$tmp_anix_native_dir/plan.anix" --language 2>&1 || true
)"

if printf '%s' "$anix_run_missing_lang_value_out" | grep -q "Usage: anix run <file>"; then
  pass "runtime: anix run with a valueless --language shows usage instead of crashing silently"
else
  fail "runtime: anix run with a valueless --language shows usage instead of crashing silently"
fi

tmp_anix_diff_plan_dir="$tmp_ok/anix-diff-plan"

mkdir -p "$tmp_anix_diff_plan_dir"

anix_diff_plan_output="$(
  ANIX_SYSTEM_CONFIG="$tmp_anix_diff_plan_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh diff-plan "$tmp_anix_plan_dir/plan.json" 2>&1
)"

if printf '%s' "$anix_diff_plan_output" | grep -q "ADD.*set hostname" \
  && printf '%s' "$anix_diff_plan_output" | grep -q "ADD.*enable bluetooth" \
  && printf '%s' "$anix_diff_plan_output" | grep -q "ADD.*enable gaming.steam" \
  && printf '%s' "$anix_diff_plan_output" | grep -q "ADD.*enable gaming.big-picture" \
  && printf '%s' "$anix_diff_plan_output" | grep -q "also ADD enable gaming.enable" \
  && printf '%s' "$anix_diff_plan_output" | grep -q "ADD.*enable gaming.controllers" \
  && printf '%s' "$anix_diff_plan_output" | grep -q "ADD.*enable gaming.launchers"; then
  pass "runtime: anix diff-plan labels new settings as ADD"
else
  fail "runtime: anix diff-plan labels new settings as ADD"
fi

# Regression check: enable/disable ops must compare against the real current
# boolean in anix.nix, not report ADD/REMOVE unconditionally regardless of
# state (a real bug caught by hand-testing — read_anix_bool_option originally
# used '|' as its sed delimiter while also using '|' for alternation in the
# pattern, which silently broke the read and made every feature look unset).
if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_diff_plan_dir" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh apply-plan "$tmp_anix_plan_dir/plan.json" --yes >/dev/null 2>&1; then
  :
fi

anix_diff_plan_same_output="$(
  ANIX_SYSTEM_CONFIG="$tmp_anix_diff_plan_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh diff-plan "$tmp_anix_plan_dir/plan.json" 2>&1
)"

if printf '%s' "$anix_diff_plan_same_output" | grep -q "SAME.*set hostname" \
  && printf '%s' "$anix_diff_plan_same_output" | grep -q "SAME.*enable bluetooth" \
  && printf '%s' "$anix_diff_plan_same_output" | grep -q "SAME.*enable gaming.big-picture"; then
  pass "runtime: anix diff-plan labels already-applied settings as SAME"
else
  fail "runtime: anix diff-plan labels already-applied settings as SAME"
fi

printf 'disable bluetooth\n' > "$tmp_anix_diff_plan_dir/disable.anix"

anix_diff_plan_change_output="$(
  ANIX_SYSTEM_CONFIG="$tmp_anix_diff_plan_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh diff-plan "$tmp_anix_diff_plan_dir/disable.anix" 2>&1
)"

if printf '%s' "$anix_diff_plan_change_output" | grep -q "CHANGE.*disable bluetooth"; then
  pass "runtime: anix diff-plan labels a real flip as CHANGE"
else
  fail "runtime: anix diff-plan labels a real flip as CHANGE"
fi

tmp_anix_diff_deps_dir="$tmp_ok/anix-diff-deps"

mkdir -p "$tmp_anix_diff_deps_dir"

cat > "$tmp_anix_diff_deps_dir/anix.nix" <<'EOF'
{ pkgs, ... }:
{
  anix.gaming.enable = true;
  anix.gaming.steam = true;
  anix.gaming.bigPictureShortcut = true;
  anix.gaming.bigPictureAutostart = true;
  anix.gaming.gamescopeSession = true;
  anix.gaming.controllerSupport = true;
}
EOF

printf '%s\n' 'disable gaming.steam' > "$tmp_anix_diff_deps_dir/disable-steam.anix"

anix_diff_deps_output="$(
  ANIX_SYSTEM_CONFIG="$tmp_anix_diff_deps_dir" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh diff-plan "$tmp_anix_diff_deps_dir/disable-steam.anix" 2>&1
)"

if printf '%s' "$anix_diff_deps_output" | grep -q "CHANGE.*disable gaming.steam" \
  && printf '%s' "$anix_diff_deps_output" | grep -q "also CHANGE disable gaming.bigPictureShortcut" \
  && printf '%s' "$anix_diff_deps_output" | grep -q "also CHANGE disable gaming.bigPictureAutostart" \
  && printf '%s' "$anix_diff_deps_output" | grep -q "also CHANGE disable gaming.gamescopeSession" \
  && printf '%s' "$anix_diff_deps_output" | grep -q "also CHANGE disable gaming.controllerSupport"; then
  pass "runtime: anix diff-plan previews implied gaming dependency changes"
else
  fail "runtime: anix diff-plan previews implied gaming dependency changes"
fi

unset ABORA_PLAN_TOOL_BIN

else

  pass "runtime: anix plan-JSON tests skipped (dotnet unavailable)"

fi

tmp_anix_lang_dir="$tmp_ok/anix-language"

tmp_anix_lang_adapters="$tmp_ok/anix-language-adapters"

mkdir -p "$tmp_anix_lang_dir" "$tmp_anix_lang_adapters"

printf '%s\n' \
  '{' \
  '  "id": "stub",' \
  '  "name": "Stub",' \
  '  "extensions": [".stub"],' \
  '  "command": ["cat"],' \
  '  "planVersion": 1' \
  '}' > "$tmp_anix_lang_adapters/stub.json"

anix_language_list_output="$(
  ANIX_SYSTEM_CONFIG="$tmp_anix_lang_dir" \
    ANIX_SYSTEM_LANGUAGE_DIR="$tmp_anix_lang_adapters" \
    ANIX_USER_LANGUAGE_DIR="$tmp_empty/no-user-languages" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh language list 2>&1
)"

if printf '%s' "$anix_language_list_output" | grep -q "Stub"; then
  pass "runtime: anix language list shows an installed adapter manifest"
else
  fail "runtime: anix language list shows an installed adapter manifest"
fi

if ANIX_SYSTEM_CONFIG="$tmp_anix_lang_dir" \
  ANIX_SYSTEM_LANGUAGE_DIR="$tmp_anix_lang_adapters" \
  ANIX_USER_LANGUAGE_DIR="$tmp_empty/no-user-languages" \
  ANIX_NO_SUDO=1 \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh language use stub >/dev/null 2>&1 \
  && grep -q "language=stub" "$tmp_anix_lang_dir/.anix/config" 2>/dev/null; then
  pass "runtime: anix language use persists the default frontend"
else
  fail "runtime: anix language use persists the default frontend"
fi

tmp_installed_anix_lang="$tmp_ok/installed-anix-languages"

mkdir -p "$tmp_installed_anix_lang/etc/nixos/abora/anix-languages" \
         "$tmp_installed_anix_lang/etc/anix"

cp assets/anix-languages/*.json "$tmp_installed_anix_lang/etc/nixos/abora/anix-languages/"

ln -s "$tmp_installed_anix_lang/etc/nixos/abora/anix-languages" \
      "$tmp_installed_anix_lang/etc/anix/languages"

installed_anix_language_list_output="$(
  ANIX_SYSTEM_CONFIG="$tmp_installed_anix_lang/etc/nixos" \
    ANIX_SYSTEM_LANGUAGE_DIR="$tmp_installed_anix_lang/etc/anix/languages" \
    ANIX_USER_LANGUAGE_DIR="$tmp_empty/no-user-languages" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh language list 2>&1
)"

if printf '%s' "$installed_anix_language_list_output" | grep -q "MAKO" \
  && printf '%s' "$installed_anix_language_list_output" | grep -q "ModuCPP" \
  && grep -q 'builtins.pathExists ./anix-languages' nix/modules/installed-base.nix \
  && grep -q '"anix/languages".source = anixLanguagesDir' nix/modules/installed-base.nix; then
  pass "runtime: installed systems expose real ANIX language adapters"
else
  fail "runtime: installed systems expose real ANIX language adapters"
fi

# ── ANIX v2 end-to-end: real example files through real adapters ───────────
# Each example is run through the actual `anix run`, with the real adapter
# manifests in assets/anix-languages, against an isolated config dir. This
# exercises the whole path (adapter resolution -> real mko/moducpp-anix
# process -> plan validation -> transactional write), not just the plan
# engine in isolation like the tests above. Skips per-frontend when the
# frontend's own tool isn't installed, matching the existing `command -v
# nix` skip pattern, rather than failing the whole suite on a missing dev
# tool that isn't part of this repo.


anix_e2e_run() {
  local example="$1" config_dir="$2"
  ANIX_NO_SUDO=1 \
    ANIX_ASSUME_YES=1 \
    ANIX_SYSTEM_CONFIG="$config_dir" \
    ANIX_SYSTEM_LANGUAGE_DIR="$repo_dir/assets/anix-languages" \
    ANIX_USER_LANGUAGE_DIR="$tmp_empty/no-user-languages" \
    ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
    scripts/anix.sh run "$example" --yes >/dev/null 2>&1
}

if [[ -n "$plan_tool_bin" ]]; then
export ABORA_PLAN_TOOL_BIN="$plan_tool_bin"
tmp_anix_e2e_anix="$tmp_ok/anix-e2e-anix"
mkdir -p "$tmp_anix_e2e_anix"
anix_e2e_run "examples/anix-v2/simple.anix" "$tmp_anix_e2e_anix" || true
if grep -Eq 'anix\.hostname[[:space:]]*=[[:space:]]*"everest"' "$tmp_anix_e2e_anix/anix.nix" 2>/dev/null; then
  pass "runtime: e2e .anix simple example applies through anix run"
else
  fail "runtime: e2e .anix simple example applies through anix run"
fi

# do_set only bans '"', '\', and '${' for timezone/keyboard.xkb/gc.days/
# gc.dates -- a systemd OnCalendar-style gc.dates value like "Sun 03:00:00"
# is legal there and via a JSON Plan's "value" field, but
# NativePlanBuilder's `set` used to require exactly 3 whitespace-split
# tokens, silently truncating/rejecting any value containing a space.
tmp_anix_e2e_spaced_value="$tmp_ok/anix-e2e-spaced-value"

mkdir -p "$tmp_anix_e2e_spaced_value"

printf 'set gc.dates Sun 03:00:00\n' > "$tmp_anix_e2e_spaced_value/plan.anix"

anix_e2e_run "$tmp_anix_e2e_spaced_value/plan.anix" "$tmp_anix_e2e_spaced_value" || true

if grep -Eq 'anix\.garbageCollect\.dates[[:space:]]*=[[:space:]]*"Sun 03:00:00"' "$tmp_anix_e2e_spaced_value/anix.nix" 2>/dev/null; then
  pass "runtime: native .anix 'set' preserves a space-containing value"
else
  fail "runtime: native .anix 'set' preserves a space-containing value"
fi

tmp_anix_e2e_anix_ws="$tmp_ok/anix-e2e-anix-workstation"

mkdir -p "$tmp_anix_e2e_anix_ws"

anix_e2e_run "examples/anix-v2/workstation.anix" "$tmp_anix_e2e_anix_ws" || true

if grep -Eq 'anix\.hostname[[:space:]]*=[[:space:]]*"everest-workstation"' "$tmp_anix_e2e_anix_ws/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.services\.bluetooth[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_anix_ws/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.enable[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_anix_ws/anix.nix" 2>/dev/null \
  && grep -Eq 'anix\.gaming\.bigPictureShortcut[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_anix_ws/anix.nix" 2>/dev/null \
  && grep -q "firefox" "$tmp_anix_e2e_anix_ws/anix.nix" 2>/dev/null \
  && grep -q "git" "$tmp_anix_e2e_anix_ws/anix.nix" 2>/dev/null; then
  pass "runtime: e2e .anix workstation example applies through anix run"
else
  fail "runtime: e2e .anix workstation example applies through anix run"
fi

if command -v mko >/dev/null 2>&1; then
  tmp_anix_e2e_mko="$tmp_ok/anix-e2e-mko"
  mkdir -p "$tmp_anix_e2e_mko"
  anix_e2e_run "examples/anix-v2/simple.mko" "$tmp_anix_e2e_mko" || true
  if grep -Eq 'anix\.hostname[[:space:]]*=[[:space:]]*"everest"' "$tmp_anix_e2e_mko/anix.nix" 2>/dev/null; then
    pass "runtime: e2e .mko simple example applies through anix run"
  else
    fail "runtime: e2e .mko simple example applies through anix run"
  fi

  tmp_anix_e2e_mko_ws="$tmp_ok/anix-e2e-mko-workstation"
  mkdir -p "$tmp_anix_e2e_mko_ws"
  anix_e2e_run "examples/anix-v2/workstation.mko" "$tmp_anix_e2e_mko_ws" || true
  if grep -Eq 'anix\.hostname[[:space:]]*=[[:space:]]*"everest-workstation"' "$tmp_anix_e2e_mko_ws/anix.nix" 2>/dev/null \
    && grep -Eq 'anix\.services\.bluetooth[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_mko_ws/anix.nix" 2>/dev/null \
    && grep -Eq 'anix\.gaming\.enable[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_mko_ws/anix.nix" 2>/dev/null \
    && grep -Eq 'anix\.gaming\.bigPictureShortcut[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_mko_ws/anix.nix" 2>/dev/null \
    && grep -q "firefox" "$tmp_anix_e2e_mko_ws/anix.nix" 2>/dev/null \
    && grep -q "git" "$tmp_anix_e2e_mko_ws/anix.nix" 2>/dev/null; then
    pass "runtime: e2e .mko workstation example applies through anix run"
  else
    fail "runtime: e2e .mko workstation example applies through anix run"
  fi
else
  pass "mko unavailable (MAKO e2e tests skipped)"
fi

if command -v moducpp-anix >/dev/null 2>&1; then
  tmp_anix_e2e_moducpp="$tmp_ok/anix-e2e-moducpp"
  mkdir -p "$tmp_anix_e2e_moducpp"
  anix_e2e_run "examples/anix-v2/simple.moducpp" "$tmp_anix_e2e_moducpp" || true
  if grep -Eq 'anix\.hostname[[:space:]]*=[[:space:]]*"everest"' "$tmp_anix_e2e_moducpp/anix.nix" 2>/dev/null; then
    pass "runtime: e2e .moducpp simple example applies through anix run"
  else
    fail "runtime: e2e .moducpp simple example applies through anix run"
  fi

  tmp_anix_e2e_moducpp_ws="$tmp_ok/anix-e2e-moducpp-workstation"
  mkdir -p "$tmp_anix_e2e_moducpp_ws"
  anix_e2e_run "examples/anix-v2/workstation.moducpp" "$tmp_anix_e2e_moducpp_ws" || true
  if grep -Eq 'anix\.hostname[[:space:]]*=[[:space:]]*"everest-workstation"' "$tmp_anix_e2e_moducpp_ws/anix.nix" 2>/dev/null \
    && grep -Eq 'anix\.services\.bluetooth[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_moducpp_ws/anix.nix" 2>/dev/null \
    && grep -Eq 'anix\.gaming\.enable[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_moducpp_ws/anix.nix" 2>/dev/null \
    && grep -Eq 'anix\.gaming\.bigPictureShortcut[[:space:]]*=[[:space:]]*true' "$tmp_anix_e2e_moducpp_ws/anix.nix" 2>/dev/null \
    && grep -q "firefox" "$tmp_anix_e2e_moducpp_ws/anix.nix" 2>/dev/null \
    && grep -q "git" "$tmp_anix_e2e_moducpp_ws/anix.nix" 2>/dev/null; then
    pass "runtime: e2e .moducpp workstation example applies through anix run"
  else
    fail "runtime: e2e .moducpp workstation example applies through anix run"
  fi
else
  pass "moducpp-anix unavailable (ModuCPP e2e tests skipped)"
fi

unset ABORA_PLAN_TOOL_BIN

else

  pass "runtime: anix e2e run tests skipped (dotnet unavailable)"

fi

# ── ANIX v2 failure paths: invalid input must never mutate state ───────────


if [[ -n "$plan_tool_bin" ]]; then
export ABORA_PLAN_TOOL_BIN="$plan_tool_bin"
tmp_anix_fail_bad_plan="$tmp_ok/anix-fail-bad-plan"
mkdir -p "$tmp_anix_fail_bad_plan"
printf '%s' '{"planVersion":1,"language":"test","operations":[{"op":"set","key":"totally-not-a-key","value":"x"}]}' \
  > "$tmp_anix_fail_bad_plan/bad.json"
if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_fail_bad_plan" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh apply-plan "$tmp_anix_fail_bad_plan/bad.json" --yes >/dev/null 2>&1; then
  fail "runtime: apply-plan rejects an invalid plan without writing anix.nix"
elif [[ -f "$tmp_anix_fail_bad_plan/anix.nix" ]]; then
  fail "runtime: apply-plan rejects an invalid plan without writing anix.nix"
else
  pass "runtime: apply-plan rejects an invalid plan without writing anix.nix"
fi

tmp_anix_fail_malformed_json="$tmp_ok/anix-fail-malformed-json"

mkdir -p "$tmp_anix_fail_malformed_json"

printf '{ this is not json' > "$tmp_anix_fail_malformed_json/malformed.json"

if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_fail_malformed_json" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh apply-plan "$tmp_anix_fail_malformed_json/malformed.json" --yes >/dev/null 2>&1; then
  fail "runtime: apply-plan rejects malformed JSON without writing anix.nix"
elif [[ -f "$tmp_anix_fail_malformed_json/anix.nix" ]]; then
  fail "runtime: apply-plan rejects malformed JSON without writing anix.nix"
else
  pass "runtime: apply-plan rejects malformed JSON without writing anix.nix"
fi

tmp_anix_fail_unknown_adapter="$tmp_ok/anix-fail-unknown-adapter"

mkdir -p "$tmp_anix_fail_unknown_adapter"

printf 'not real source content\n' > "$tmp_anix_fail_unknown_adapter/script.nosuchlang"

if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_fail_unknown_adapter" \
  ANIX_SYSTEM_LANGUAGE_DIR="$tmp_empty/no-system-languages" \
  ANIX_USER_LANGUAGE_DIR="$tmp_empty/no-user-languages" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh run "$tmp_anix_fail_unknown_adapter/script.nosuchlang" --yes >/dev/null 2>&1; then
  fail "runtime: run rejects an unresolvable language without writing anix.nix"
elif [[ -f "$tmp_anix_fail_unknown_adapter/anix.nix" ]]; then
  fail "runtime: run rejects an unresolvable language without writing anix.nix"
else
  pass "runtime: run rejects an unresolvable language without writing anix.nix"
fi

tmp_anix_fail_adapter_error="$tmp_ok/anix-fail-adapter-error"

tmp_anix_fail_adapter_dir="$tmp_ok/anix-fail-adapter-manifests"

mkdir -p "$tmp_anix_fail_adapter_error" "$tmp_anix_fail_adapter_dir"

printf '%s\n' \
  '{' \
  '  "id": "always-fails",' \
  '  "name": "Always Fails",' \
  '  "extensions": [".fails"],' \
  '  "command": ["false"],' \
  '  "planVersion": 1' \
  '}' > "$tmp_anix_fail_adapter_dir/always-fails.json"

printf 'anything\n' > "$tmp_anix_fail_adapter_error/script.fails"

if ANIX_NO_SUDO=1 \
  ANIX_ASSUME_YES=1 \
  ANIX_SYSTEM_CONFIG="$tmp_anix_fail_adapter_error" \
  ANIX_SYSTEM_LANGUAGE_DIR="$tmp_anix_fail_adapter_dir" \
  ANIX_USER_LANGUAGE_DIR="$tmp_empty/no-user-languages" \
  ABORA_UI_LIB="$tmp_empty/missing-ui.sh" \
  scripts/anix.sh run "$tmp_anix_fail_adapter_error/script.fails" --yes >/dev/null 2>&1; then
  fail "runtime: run surfaces an adapter's own failure without writing anix.nix"
elif [[ -f "$tmp_anix_fail_adapter_error/anix.nix" ]]; then
  fail "runtime: run surfaces an adapter's own failure without writing anix.nix"
else
  pass "runtime: run surfaces an adapter's own failure without writing anix.nix"
fi

unset ABORA_PLAN_TOOL_BIN

else

  pass "runtime: anix plan failure-path tests skipped (dotnet unavailable)"

fi

# Regression test: anix.sh's "ANIX Control Center" terminal menus had the
# same bug, but worse -- do_set/do_toggle/do_switch/do_rollback/do_save/
# do_tool_config/do_tinypm/do_package/do_doctor/do_apply all call `exit`
# (not `return`) on failure, so even a subshell-less `|| true` at the call
# site couldn't have caught it; each call needed wrapping in its own `(
# ... )` subshell so the exit only ends that subshell. Reproduced directly:
# typing a hostname containing a space into "Settings > Hostname" killed
# the entire `anix --gui` session before it ever returned to the settings
# menu or the control center. Runs the real terminal UI end-to-end (no
# DISPLAY/zenity, so it falls back to do_gui_terminal) against a sandboxed
# ANIX_SYSTEM_CONFIG, entering Settings (2) -> Hostname (2) -> an invalid
# value, and checks the control center/settings banners rendered more than
# once and the whole process exited cleanly.
tmp_anix_menu_cfg="$(mktemp -d)"

printf '{ ... }: { imports = [ ./anix.nix ]; }\n' > "$tmp_anix_menu_cfg/configuration.nix"

set +e

_anix_menu_out="$(
  printf '2\n2\nbad hostname\nq\n0\nq\n' | \
    DISPLAY= WAYLAND_DISPLAY= \
    ANIX_SYSTEM_CONFIG="$tmp_anix_menu_cfg" ANIX_NO_SUDO=1 ANIX_ASSUME_YES=1 \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" bash scripts/anix.sh --gui 2>&1
)"

_anix_menu_status=$?

set -e

rm -rf "$tmp_anix_menu_cfg"

_anix_menu_renders="$(grep -c 'ANIX Control Center\|ANIX Settings' <<<"$_anix_menu_out")"

if [[ "$_anix_menu_status" -eq 0 && "$_anix_menu_renders" -ge 3 ]] \
  && grep -q '( do_toggle "\$wanted" "\$feature" ) || true' scripts/anix.sh \
  && grep -q '( do_switch nix "\$profile" ) || true' scripts/anix.sh \
  && grep -q '( do_rollback ) || true' scripts/anix.sh \
  && grep -q '( do_save "\${message:-anix: local config snapshot}" ) || true' scripts/anix.sh \
  && grep -q '( do_tool_config show ) || true' scripts/anix.sh \
  && grep -q '( do_tinypm install ) || true' scripts/anix.sh \
  && grep -q '( do_package add "\$pkg" ) || true' scripts/anix.sh \
  && grep -q '( do_doctor ) || true' scripts/anix.sh \
  && grep -q '( do_apply ) || true' scripts/anix.sh; then
  pass "runtime: ANIX terminal menus survive a failing action and return to the menu"
else
  fail "runtime: ANIX terminal menus survive a failing action and return to the menu"
  printf '              exit status: %s, menu renders: %s (need 0 and >=3)\n' \
    "$_anix_menu_status" "$_anix_menu_renders"
fi

# Regression test: anix.power.thermald defaulted to true in both the
# nixosOption (nix/modules/anix.nix) and the anix.nix template render_template()
# writes on `anix init`/`anix quickstart` -- but thermald is Intel's
# laptop-specific thermal daemon, and it exits nonzero on non-mobile
# hardware instead of no-op'ing. Since `nixos-rebuild switch` treats any
# failed unit as a hard activation error, every desktop-class Abora
# install had a perpetually-failing thermald.service, and every
# nixos-rebuild -- including `abora update`'s -- failed because of it.
# Reproduced on real desktop hardware: thermald logged "Non mobile ...
# THD engine" errors and the whole update aborted. Checks both defaults
# are false now: the nixosOption's static default, and a real render_template()
# run (not a copy of it).
if sed -n '/thermald = lib.mkOption {/,/description = "Enable thermald when available.";/p' nix/modules/anix.nix \
  | grep -q 'default = false;'; then
  pass "runtime: anix.power.thermald nixosOption defaults to false"
else
  fail "runtime: anix.power.thermald nixosOption defaults to false"
fi

tmp_thermald_render="$(mktemp -d)"

ANIX_SYSTEM_CONFIG="$tmp_thermald_render" ANIX_NO_SUDO=1 ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/anix.sh init >/dev/null 2>&1 || true

if grep -qx '  anix.power.thermald = false;' "$tmp_thermald_render/anix.nix" 2>/dev/null; then
  pass "runtime: anix init's generated anix.nix defaults power.thermald to false"
else
  fail "runtime: anix init's generated anix.nix defaults power.thermald to false"
fi

rm -rf "$tmp_thermald_render"

testlib_finish
