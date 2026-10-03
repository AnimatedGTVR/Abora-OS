#!/usr/bin/env bash
# Behaviour tests for abora config (scripts/config/abora-config.sh).
#
# Run by scripts/check-scripts.py, one suite per Bash tool. These tests
# exercise Bash code directly (running it in sandboxes, or sourcing
# functions out of it), so they stay Bash until abora-config.sh itself
# is ported, then move to its new language with it.
set -euo pipefail
# shellcheck source=../../release/bash-testlib.sh
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../release" && pwd)/bash-testlib.sh"

config_help_out="$(ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" scripts/abora-config.sh --help 2>&1)"

apps_help_out="$(ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" scripts/abora-apps.sh --help 2>&1)"

if printf '%s' "$config_help_out" | grep -q 'abora config set timezone' \
  && printf '%s' "$config_help_out" | grep -q 'gaming.big-picture' \
  && printf '%s' "$apps_help_out" | grep -q 'abora apps catalog' \
  && printf '%s' "$apps_help_out" | grep -q 'abora apps bundle <name>' \
  && ! printf '%s' "$apps_help_out" | grep -q 'abora-apps catalog' \
  && grep -q "run 'abora apps add <id>'" scripts/abora-apps.sh \
  && grep -q 'sudo abora apps bundle gaming' scripts/abora.sh \
  && ! grep -q 'sudo abora apps add gaming' scripts/abora.sh \
  && grep -q "Run 'abora apps catalog'" scripts/abora-apps.sh \
  && ! grep -q "abora-apps add" scripts/abora-apps.sh; then
  pass "runtime: config and apps help use public commands"
else
  fail "runtime: config and apps help use public commands"
fi

# abora-config.sh backs the `abora config` command CLAUDE.md documents as
# read/writing abora-local.nix without requiring Nix knowledge, including
# that `user` and `disk` are intentionally read-only through this CLI — none
# of that was previously exercised at runtime, only checked for existence.
tmp_config="$(mktemp -d)"

tmp_config_module="$tmp_config/abora-local.nix"

cat > "$tmp_config_module" <<'EOF'
{ config, ... }:
{
  abora.hostname = "abora";
  abora.locale = "en_US.UTF-8";
  abora.timezone = "UTC";
  abora.keyboard.console = "us";
  abora.keyboard.xkb = "us";
  abora.desktop = "cosmic";
  abora.wallpaper = "titlis-alps.jpg";
  abora.gpu = "none";
  abora.stateVersion = "26.05";
  abora.user.name = "abora";
  abora.user.hashedPassword = "";
  abora.disk = null;

  networking.networkmanager.enable = true;
  users.users.root.hashedPassword = "!";
}
EOF

config_show_out="$(
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh show 2>&1
)"

if printf '%s' "$config_show_out" | grep -q "abora" \
  && printf '%s' "$config_show_out" | grep -q "titlis-alps.jpg"; then
  pass "runtime: abora config show reads abora-local.nix"
else
  fail "runtime: abora config show reads abora-local.nix"
fi

if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set hostname new-hostname >/dev/null 2>&1 \
  && grep -q 'abora.hostname = "new-hostname";' "$tmp_config_module"; then
  pass "runtime: abora config set writes a new value"
else
  fail "runtime: abora config set writes a new value"
fi

if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set gaming yes >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.steam off >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.big-picture off >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.controllers off >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.mangohud off >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.gamemode off >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.vulkan false >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.launchers false >/dev/null 2>&1 \
  && grep -q 'abora.gaming.enable = true;' "$tmp_config_module" \
  && grep -q 'abora.gaming.steam = false;' "$tmp_config_module" \
  && grep -q 'abora.gaming.bigPictureShortcut = false;' "$tmp_config_module" \
  && grep -q 'abora.gaming.controllerSupport = false;' "$tmp_config_module" \
  && grep -q 'abora.gaming.mangohud = false;' "$tmp_config_module" \
  && grep -q 'abora.gaming.gamemode = false;' "$tmp_config_module" \
  && grep -q 'abora.gaming.vulkanTools = false;' "$tmp_config_module" \
  && grep -q 'abora.gaming.launchers = false;' "$tmp_config_module"; then
  pass "runtime: abora config set writes gaming booleans"
else
  fail "runtime: abora config set writes gaming booleans"
fi

if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set gaming.big-picture true >/dev/null 2>&1 \
  && grep -q 'abora.gaming.enable = true;' "$tmp_config_module" \
  && grep -q 'abora.gaming.steam = true;' "$tmp_config_module" \
  && grep -q 'abora.gaming.bigPictureShortcut = true;' "$tmp_config_module" \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.autostart true >/dev/null 2>&1 \
  && grep -q 'abora.gaming.bigPictureAutostart = true;' "$tmp_config_module" \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set gaming.gamescope true >/dev/null 2>&1 \
  && grep -q 'abora.gaming.gamescopeSession = true;' "$tmp_config_module"; then
  pass "runtime: abora config gaming launcher keys enable required parent options"
else
  fail "runtime: abora config gaming launcher keys enable required parent options"
fi

if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set diagnostics true >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set vm-guests true >/dev/null 2>&1 \
  && ABORA_NO_SUDO=1 \
    ABORA_SYSTEM_CONFIG="$tmp_config" \
    scripts/abora-config.sh set mobile-broadband true >/dev/null 2>&1 \
  && grep -q 'abora.extras.diagnostics = true;' "$tmp_config_module" \
  && grep -q 'abora.extras.virtualizationGuests = true;' "$tmp_config_module" \
  && grep -q 'abora.extras.mobileBroadband = true;' "$tmp_config_module" \
  && grep -q 'lib.optionals config.abora.extras.diagnostics' nix/modules/installed-base.nix \
  && grep -q 'lib.optionals config.abora.extras.mobileBroadband' nix/modules/installed-base.nix \
  && grep -q 'config.abora.extras.virtualizationGuests' nix/modules/installed-base.nix \
  && grep -q 'abora.extras.diagnostics = false;' scripts/abora-installer.sh; then
  pass "runtime: lean extras are opt-in instead of always installed"
else
  fail "runtime: lean extras are opt-in instead of always installed"
fi

if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set gaming maybe >/dev/null 2>&1; then
  fail "runtime: abora config set rejects invalid gaming boolean"
else
  pass "runtime: abora config set rejects invalid gaming boolean"
fi

if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set hostname 'not a valid host!' >/dev/null 2>&1; then
  fail "runtime: abora config set rejects an invalid hostname"
elif grep -q 'abora.hostname = "not a valid host!"' "$tmp_config_module"; then
  fail "runtime: abora config set rejects an invalid hostname"
else
  pass "runtime: abora config set rejects an invalid hostname"
fi

# user/disk are deliberately absent from do_set's key case, falling through
# to "Unknown key" -- that's the actual read-only enforcement mechanism.
set +e

config_user_out="$(
  ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set user someone 2>&1
)"

config_user_status=$?

set -e

if [[ "$config_user_status" -eq 0 ]] || ! grep -q "Unknown key" <<<"$config_user_out"; then
  fail "runtime: abora config set rejects the read-only 'user' key"
elif grep -q 'abora.user.name = "someone"' "$tmp_config_module"; then
  fail "runtime: abora config set rejects the read-only 'user' key"
else
  pass "runtime: abora config set rejects the read-only 'user' key"
fi

if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set disk /dev/sda >/dev/null 2>&1; then
  fail "runtime: abora config set rejects the read-only 'disk' key"
else
  pass "runtime: abora config set rejects the read-only 'disk' key"
fi

# Belt-and-suspenders injection guard: a value carrying '"', '\', or '${'
# could otherwise break out of the Nix double-quoted string it's written
# into.
if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_config" \
  scripts/abora-config.sh set wallpaper '"; evil = true; "' >/dev/null 2>&1; then
  fail "runtime: abora config set rejects a Nix-breaking value"
elif grep -q "evil" "$tmp_config_module"; then
  fail "runtime: abora config set rejects a Nix-breaking value"
else
  pass "runtime: abora config set rejects a Nix-breaking value"
fi

# Legacy (pre-v2.5) abora-local.nix used raw NixOS options instead of the
# abora.* module — do_set migrates it in place on first write.
tmp_legacy_config="$(mktemp -d)"

tmp_legacy_module="$tmp_legacy_config/abora-local.nix"

cat > "$tmp_legacy_module" <<'EOF'
{ ... }:
{
  networking.hostName = "legacybox";
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";
  services.desktopManager.gnome.enable = true;
  users.users."quinn" = {
    hashedPassword = "!";
  };
  system.stateVersion = "26.05";
}
EOF

# Regression test: the username fixture here used to be "abora" -- the
# exact string migrate_legacy_config's (previously broken) username regex
# silently fell back to on a match failure, so a real extraction bug could
# never have been caught by this test no matter what the regex actually
# did. Using a distinct name ("quinn") and asserting on it directly closes
# that gap.
if ABORA_NO_SUDO=1 \
  ABORA_SYSTEM_CONFIG="$tmp_legacy_config" \
  scripts/abora-config.sh set hostname migrated-host >/dev/null 2>&1 \
	  && grep -q 'abora.hostname = "migrated-host";' "$tmp_legacy_module" \
	  && grep -q 'abora.desktop = "gnome";' "$tmp_legacy_module" \
	  && grep -q 'abora.user.name = "quinn";' "$tmp_legacy_module" \
	  && grep -q 'abora.gaming.controllerSupport = true;' "$tmp_legacy_module" \
	  && grep -q 'abora.gaming.mangohud = true;' "$tmp_legacy_module" \
	  && grep -q 'abora.gaming.gamemode = true;' "$tmp_legacy_module" \
	  && grep -q 'abora.gaming.launchers = true;' "$tmp_legacy_module" \
	  && compgen -G "${tmp_legacy_module}.legacy.*" >/dev/null; then
  pass "runtime: abora config migrates a legacy abora-local.nix on write"
else
  fail "runtime: abora config migrates a legacy abora-local.nix on write"
fi

# Security regression test: abora-local.nix carries a hashedPassword field
# (see the fixture above and abora-installer.sh's own generation of this
# file) -- it must never be world-readable, or any local user on the
# machine could read the hash straight out of /etc/nixos and run an
# offline attack against it, exactly what /etc/shadow's own restrictive
# permissions exist to prevent. The migration path above used to leave it
# 0644 (and its .legacy.* backup, via a plain `cp` that doesn't preserve
# source permissions on a new destination, at whatever the umask gives).
# Checks both the migrated file and its backup are 0600.
_migrated_mode="$(stat -c '%a' "$tmp_legacy_module" 2>/dev/null || echo unknown)"

_backup_path="$(compgen -G "${tmp_legacy_module}.legacy.*" | head -n1)"

_backup_mode="$(stat -c '%a' "$_backup_path" 2>/dev/null || echo unknown)"

if [[ "$_migrated_mode" == "600" && "$_backup_mode" == "600" ]]; then
  pass "runtime: migrated abora-local.nix and its legacy backup are 0600, not world-readable"
else
  fail "runtime: migrated abora-local.nix and its legacy backup are 0600, not world-readable"
  printf '              migrated=%s backup=%s\n' "$_migrated_mode" "$_backup_mode"
fi

# Security regression test: separately from whether elevation happens,
# abora-config.sh must never silently succeed with empty/wrong data when
# abora-local.nix can't be read at all (e.g. elevation is unavailable, or
# -- as simulated here via ABORA_NO_SUDO=1, the same switch every other
# test in this suite already relies on to avoid a real sudo prompt -- it's
# deliberately skipped). A genuinely unreadable file (chmod 000, unreadable
# even to its own owner) must make abora-config.sh fail closed.
tmp_unreadable_config="$(mktemp -d)"

tmp_unreadable_module="$tmp_unreadable_config/abora-local.nix"

printf '{ abora.hostname = "x"; }\n' > "$tmp_unreadable_module"

chmod 000 "$tmp_unreadable_module"

set +e

_unreadable_out="$(ABORA_NO_SUDO=1 ABORA_SYSTEM_CONFIG="$tmp_unreadable_config" \
  scripts/abora-config.sh show 2>&1)"

_unreadable_status=$?

set -e

chmod 600 "$tmp_unreadable_module"

rm -rf "$tmp_unreadable_config"

if [[ "$_unreadable_status" -ne 0 ]]; then
  pass "runtime: abora config fails closed (not silently) against an unreadable abora-local.nix"
else
  fail "runtime: abora config fails closed (not silently) against an unreadable abora-local.nix"
  printf '              output: %s\n' "$_unreadable_out"
fi

testlib_finish
