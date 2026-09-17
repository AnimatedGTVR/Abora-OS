#!/usr/bin/env bash
# Behaviour tests for Abora Gaming (scripts/apps/abora-gaming.sh).
#
# Run by scripts/check-scripts.py, one suite per Bash tool. These tests
# exercise Bash code directly (running it in sandboxes, or sourcing
# functions out of it), so they stay Bash until abora-gaming.sh itself
# is ported, then move to its new language with it.
set -euo pipefail
# shellcheck source=../../release/bash-testlib.sh
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../release" && pwd)/bash-testlib.sh"

tmp_gaming_config="$(mktemp -d)"

tmp_gaming_module="$tmp_gaming_config/abora-local.nix"

cat > "$tmp_gaming_module" <<'EOF'
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
  abora.gaming.enable = false;
  abora.gaming.steam = false;
  abora.gaming.bigPictureShortcut = false;
  abora.gaming.bigPictureAutostart = false;
  abora.gaming.gamescopeSession = false;
  abora.gaming.controllerSupport = false;
  abora.gaming.mangohud = false;
  abora.gaming.gamemode = false;
  abora.gaming.vulkanTools = false;
  abora.gaming.launchers = false;
  abora.user.name = "abora";
  abora.user.hashedPassword = "";
  abora.disk = null;
}
EOF

mkdir -p "$tmp_gaming_config/abora"

cat > "$tmp_gaming_config/abora/gaming.pending" <<'EOF'
enable=yes
steam=yes
bigPictureShortcut=yes
bigPictureAutostart=no
gamescopeSession=yes
controllerSupport=yes
mangohud=yes
gamemode=yes
vulkanTools=yes
launchers=yes
EOF

if PATH="/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-gaming.sh apply-queued >/dev/null 2>&1 \
  && grep -q 'abora.gaming.enable = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.steam = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.gamescopeSession = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.launchers = true;' "$tmp_gaming_module" \
  && [[ ! -e "$tmp_gaming_config/abora/gaming.pending" ]]; then
  pass "runtime: abora gaming applies installer-queued gaming settings"
else
  fail "runtime: abora gaming applies installer-queued gaming settings"
fi

if PATH="/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-gaming.sh enable >/dev/null 2>&1 \
  && grep -q 'abora.gaming.enable = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.steam = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.bigPictureShortcut = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.controllerSupport = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.mangohud = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.gamemode = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.vulkanTools = true;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.launchers = true;' "$tmp_gaming_module" \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh gamescope on >/dev/null 2>&1 \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh autostart off >/dev/null 2>&1 \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh autostart on >/dev/null 2>&1 \
  && grep -q 'abora.gaming.bigPictureAutostart = true;' "$tmp_gaming_module" \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh controllers off >/dev/null 2>&1 \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh mangohud off >/dev/null 2>&1 \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh gamemode off >/dev/null 2>&1 \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh vulkan off >/dev/null 2>&1 \
	  && PATH="/usr/bin:/bin" \
	    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
	    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
	    bash scripts/abora-gaming.sh launchers off >/dev/null 2>&1 \
	  && PATH="/usr/bin:/bin" \
	    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
	    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
	    bash scripts/abora-gaming.sh disable >/dev/null 2>&1 \
	  && grep -q 'abora.gaming.enable = false;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.steam = false;' "$tmp_gaming_module" \
	  && PATH="/usr/bin:/bin" \
	    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
	    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
	    bash scripts/abora-gaming.sh enable >/dev/null 2>&1 \
	  && grep -q 'abora.gaming.enable = true;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.steam = true;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.bigPictureShortcut = true;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.gamescopeSession = false;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.bigPictureAutostart = false;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.controllerSupport = true;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.mangohud = true;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.gamemode = true;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.vulkanTools = true;' "$tmp_gaming_module" \
	  && grep -q 'abora.gaming.launchers = true;' "$tmp_gaming_module"; then
  pass "runtime: abora gaming toggles write config"
else
  fail "runtime: abora gaming toggles write config"
fi

if PATH="/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-gaming.sh bigpicture off >/dev/null 2>&1 \
  && grep -q 'abora.gaming.bigPictureShortcut = false;' "$tmp_gaming_module" \
  && bash scripts/abora-gaming.sh help 2>&1 | grep -q 'abora gaming big-picture' \
  && bash scripts/abora-gaming.sh help 2>&1 | grep -q 'abora gaming steam on|off'; then
  pass "runtime: abora gaming exposes friendly Big Picture commands"
else
  fail "runtime: abora gaming exposes friendly Big Picture commands"
fi

tmp_gaming_parent_config="$(mktemp -d)"

tmp_gaming_parent_module="$tmp_gaming_parent_config/abora-local.nix"

cp "$tmp_gaming_module" "$tmp_gaming_parent_module"

if PATH="/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_parent_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-gaming.sh big-picture on >/dev/null 2>&1 \
  && grep -q 'abora.gaming.enable = true;' "$tmp_gaming_parent_module" \
  && grep -q 'abora.gaming.steam = true;' "$tmp_gaming_parent_module" \
  && grep -q 'abora.gaming.bigPictureShortcut = true;' "$tmp_gaming_parent_module" \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_parent_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh autostart on >/dev/null 2>&1 \
  && grep -q 'abora.gaming.bigPictureAutostart = true;' "$tmp_gaming_parent_module" \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_parent_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh gamescope on >/dev/null 2>&1 \
  && grep -q 'abora.gaming.gamescopeSession = true;' "$tmp_gaming_parent_module" \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_parent_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh steam off >/dev/null 2>&1 \
  && grep -q 'abora.gaming.steam = false;' "$tmp_gaming_parent_module" \
  && grep -q 'abora.gaming.bigPictureShortcut = false;' "$tmp_gaming_parent_module" \
  && grep -q 'abora.gaming.bigPictureAutostart = false;' "$tmp_gaming_parent_module" \
  && grep -q 'abora.gaming.gamescopeSession = false;' "$tmp_gaming_parent_module" \
  && grep -q 'abora.gaming.controllerSupport = false;' "$tmp_gaming_parent_module" \
  && PATH="/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_parent_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    bash scripts/abora-gaming.sh steam on >/dev/null 2>&1 \
  && grep -q 'abora.gaming.steam = true;' "$tmp_gaming_parent_module" \
  && grep -q 'abora.gaming.controllerSupport = true;' "$tmp_gaming_parent_module"; then
  pass "runtime: abora gaming launcher commands enable required parent options"
else
  fail "runtime: abora gaming launcher commands enable required parent options"
fi

tmp_gaming_status_path="$(mktemp -d)"

touch "$tmp_gaming_status_path/gamemoderun" "$tmp_gaming_status_path/heroic-games-launcher"

chmod +x "$tmp_gaming_status_path/gamemoderun" "$tmp_gaming_status_path/heroic-games-launcher"

cat > "$tmp_gaming_status_path/df" <<'EOF'
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf '/dev/test 10000000 3000000 7000000 30%% /nix/store\n'
EOF

chmod +x "$tmp_gaming_status_path/df"

tmp_gaming_status_out="$tmp_ok/gaming-status.out"

if PATH="$tmp_gaming_status_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-gaming.sh status >"$tmp_gaming_status_out" 2>&1 \
  && grep -q 'GameMode: installed' "$tmp_gaming_status_out" \
  && grep -q 'Heroic: installed' "$tmp_gaming_status_out" \
  && ! grep -q 'GameMode: missing' "$tmp_gaming_status_out" \
  && grep -q 'print_status_any "GameMode" gamemoderun gamemoded' scripts/abora-gaming.sh; then
  pass "runtime: abora gaming status accepts common command aliases"
else
  fail "runtime: abora gaming status accepts common command aliases"
fi

tmp_gaming_doctor_out="$tmp_ok/gaming-doctor.out"

if PATH="$tmp_gaming_status_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-gaming.sh doctor >"$tmp_gaming_doctor_out" 2>&1 \
  && grep -q 'Gaming layer:' "$tmp_gaming_doctor_out" \
  && grep -q 'Big Picture autostart:' "$tmp_gaming_doctor_out" \
  && grep -q 'Controller support:' "$tmp_gaming_doctor_out" \
  && grep -q 'MangoHud option:' "$tmp_gaming_doctor_out" \
  && grep -q 'GameMode option:' "$tmp_gaming_doctor_out" \
  && grep -q 'Vulkan tools option:' "$tmp_gaming_doctor_out" \
  && grep -q 'Launcher bundle:' "$tmp_gaming_doctor_out" \
  && grep -q 'Low free space near' "$tmp_gaming_doctor_out" \
  && grep -q 'nix-collect-garbage -d' "$tmp_gaming_doctor_out" \
  && grep -Eq 'abora gaming (install steam|big-picture)' "$tmp_gaming_doctor_out"; then
  pass "runtime: abora gaming doctor reports all gaming config toggles"
else
  fail "runtime: abora gaming doctor reports all gaming config toggles"
fi

tmp_gaming_cache_home="$(mktemp -d)"

mkdir -p "$tmp_gaming_cache_home/.cache/nix"

touch "$tmp_gaming_cache_home/.cache/nix/fetcher-cache-v4.sqlite" \
  "$tmp_gaming_cache_home/.cache/nix/fetcher-cache-v4.sqlite-wal"

tmp_gaming_cache_out="$tmp_ok/gaming-repair-cache.out"

if HOME="$tmp_gaming_cache_home" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-gaming.sh repair-cache >"$tmp_gaming_cache_out" 2>&1 \
  && grep -q 'Cleared local Nix fetch cache files' "$tmp_gaming_cache_out" \
  && [[ ! -e "$tmp_gaming_cache_home/.cache/nix/fetcher-cache-v4.sqlite" ]] \
  && [[ ! -e "$tmp_gaming_cache_home/.cache/nix/fetcher-cache-v4.sqlite-wal" ]]; then
  pass "runtime: abora gaming repair-cache clears stale Nix fetch cache files"
else
  fail "runtime: abora gaming repair-cache clears stale Nix fetch cache files"
fi

tmp_gaming_logs_path="$(mktemp -d)"

tmp_gaming_logs_out="$tmp_ok/gaming-logs.out"

cat > "$tmp_gaming_logs_path/abora" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*"
EOF

chmod +x "$tmp_gaming_logs_path/abora"

if PATH="$tmp_gaming_logs_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  bash scripts/abora-gaming.sh logs 77 >"$tmp_gaming_logs_out" 2>&1 \
  && grep -qx 'logs --lines 77' "$tmp_gaming_logs_out" \
  && grep -q 'abora gaming logs' scripts/abora-gaming.sh; then
  pass "runtime: abora gaming logs delegates to abora logs"
else
  fail "runtime: abora gaming logs delegates to abora logs"
fi

tmp_gaming_path="$(mktemp -d)"

cat > "$tmp_gaming_path/abora-apps" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "info" ]]; then
  case "${2:-}" in
    steam|lutris|heroic|bottles|wine|winetricks|gamemode|mangohud) exit 0 ;;
    *) exit 1 ;;
  esac
fi
printf '%s\n' "$*" > "$ABORA_GAMING_APPS_LOG"
EOF

chmod +x "$tmp_gaming_path/abora-apps"

tmp_gaming_apps_log="$tmp_ok/gaming-apps.log"

if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh install steam >/dev/null 2>&1 \
  && grep -q '^add steam$' "$tmp_gaming_apps_log" \
  && grep -q 'abora.gaming.steam = true;' "$tmp_gaming_module" \
  && PATH="$tmp_gaming_path:/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
    bash scripts/abora-gaming.sh uninstall steam >/dev/null 2>&1 \
  && grep -q '^remove steam$' "$tmp_gaming_apps_log" \
  && grep -q 'abora.gaming.steam = false;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.bigPictureShortcut = false;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.bigPictureAutostart = false;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.gamescopeSession = false;' "$tmp_gaming_module" \
  && grep -q 'abora.gaming.controllerSupport = false;' "$tmp_gaming_module"; then
  pass "runtime: abora gaming install/remove delegates to app manager"
else
  fail "runtime: abora gaming install/remove delegates to app manager"
fi

tmp_gaming_fail_path="$(mktemp -d)"

cat > "$tmp_gaming_fail_path/abora-apps" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "info" ]]; then
  [[ "${2:-}" == "steam" ]] && exit 0
  exit 1
fi
printf '%s\n' "$*" > "$ABORA_GAMING_APPS_LOG"
exit 1
EOF

chmod +x "$tmp_gaming_fail_path/abora-apps"

tmp_gaming_fail_config="$(mktemp -d)"

tmp_gaming_fail_module="$tmp_gaming_fail_config/abora-local.nix"

cat > "$tmp_gaming_fail_module" <<'EOF'
{ config, ... }:
{
  abora.gaming.enable = false;
  abora.gaming.steam = false;
  abora.gaming.bigPictureShortcut = false;
  abora.gaming.bigPictureAutostart = false;
  abora.gaming.gamescopeSession = false;
  abora.gaming.controllerSupport = false;
  abora.gaming.mangohud = false;
  abora.gaming.gamemode = false;
  abora.gaming.vulkanTools = false;
  abora.gaming.launchers = false;
}
EOF

cp "$tmp_gaming_fail_module" "$tmp_ok/gaming-failed-install.before"

if PATH="$tmp_gaming_fail_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_fail_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_ok/gaming-failed-apps.log" \
  bash scripts/abora-gaming.sh install steam >/tmp/abora-gaming-failed-install.out 2>&1; then
  fail "runtime: abora gaming restores toggles when app install fails"
elif cmp -s "$tmp_gaming_fail_module" "$tmp_ok/gaming-failed-install.before" \
  && grep -q 'Restored previous gaming settings because the app install failed' /tmp/abora-gaming-failed-install.out; then
  pass "runtime: abora gaming restores toggles when app install fails"
else
  fail "runtime: abora gaming restores toggles when app install fails"
  sed 's/^/              /' /tmp/abora-gaming-failed-install.out
fi

rm -rf "$tmp_gaming_fail_path" "$tmp_gaming_fail_config"

tmp_gaming_remove_fail_path="$(mktemp -d)"

cat > "$tmp_gaming_remove_fail_path/abora-apps" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "info" ]]; then
  [[ "${2:-}" == "steam" ]] && exit 0
  exit 1
fi
printf '%s\n' "$*" > "$ABORA_GAMING_APPS_LOG"
exit 1
EOF

chmod +x "$tmp_gaming_remove_fail_path/abora-apps"

tmp_gaming_remove_fail_config="$(mktemp -d)"

tmp_gaming_remove_fail_module="$tmp_gaming_remove_fail_config/abora-local.nix"

cat > "$tmp_gaming_remove_fail_module" <<'EOF'
{ config, ... }:
{
  abora.gaming.enable = true;
  abora.gaming.steam = true;
  abora.gaming.bigPictureShortcut = true;
  abora.gaming.bigPictureAutostart = true;
  abora.gaming.gamescopeSession = true;
  abora.gaming.controllerSupport = true;
  abora.gaming.mangohud = true;
  abora.gaming.gamemode = true;
  abora.gaming.vulkanTools = true;
  abora.gaming.launchers = true;
}
EOF

cp "$tmp_gaming_remove_fail_module" "$tmp_ok/gaming-failed-remove.before"

if PATH="$tmp_gaming_remove_fail_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_remove_fail_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_ok/gaming-failed-remove-apps.log" \
  bash scripts/abora-gaming.sh remove steam >/tmp/abora-gaming-failed-remove.out 2>&1; then
  fail "runtime: abora gaming restores toggles when app removal fails"
elif cmp -s "$tmp_gaming_remove_fail_module" "$tmp_ok/gaming-failed-remove.before" \
  && grep -q 'Restored previous gaming settings because the app removal failed' /tmp/abora-gaming-failed-remove.out; then
  pass "runtime: abora gaming restores toggles when app removal fails"
else
  fail "runtime: abora gaming restores toggles when app removal fails"
  sed 's/^/              /' /tmp/abora-gaming-failed-remove.out
fi

rm -rf "$tmp_gaming_remove_fail_path" "$tmp_gaming_remove_fail_config"

if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh install wine winetricks --dry-run >/dev/null 2>&1 \
  && grep -q '^add wine winetricks --dry-run$' "$tmp_gaming_apps_log"; then
  pass "runtime: abora gaming install accepts Wine tooling"
else
  fail "runtime: abora gaming install accepts Wine tooling"
fi

tmp_gaming_lean_config="$(mktemp -d)"

tmp_gaming_lean_module="$tmp_gaming_lean_config/abora-local.nix"

cat > "$tmp_gaming_lean_module" <<'EOF'
{ config, ... }:
{
  abora.gaming.enable = false;
  abora.gaming.steam = false;
  abora.gaming.bigPictureShortcut = false;
  abora.gaming.bigPictureAutostart = false;
  abora.gaming.gamescopeSession = false;
  abora.gaming.controllerSupport = false;
  abora.gaming.mangohud = false;
  abora.gaming.gamemode = false;
  abora.gaming.vulkanTools = false;
  abora.gaming.launchers = false;
}
EOF

if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_lean_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh install wine >/dev/null 2>&1 \
  && grep -q '^add wine$' "$tmp_gaming_apps_log" \
  && grep -q 'abora.gaming.enable = true;' "$tmp_gaming_lean_module" \
  && grep -q 'abora.gaming.launchers = true;' "$tmp_gaming_lean_module" \
  && grep -q 'abora.gaming.steam = false;' "$tmp_gaming_lean_module" \
  && grep -q 'abora.gaming.bigPictureShortcut = false;' "$tmp_gaming_lean_module" \
  && grep -q 'abora.gaming.mangohud = false;' "$tmp_gaming_lean_module" \
  && grep -q 'abora.gaming.gamemode = false;' "$tmp_gaming_lean_module"; then
  pass "runtime: abora gaming install enables only the needed feature family"
else
  fail "runtime: abora gaming install enables only the needed feature family"
fi

if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_lean_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh install mangohud gamemode >/dev/null 2>&1 \
  && grep -q 'abora.gaming.mangohud = true;' "$tmp_gaming_lean_module" \
  && grep -q 'abora.gaming.gamemode = true;' "$tmp_gaming_lean_module" \
  && PATH="$tmp_gaming_path:/usr/bin:/bin" \
    ABORA_SYSTEM_CONFIG="$tmp_gaming_lean_config" \
    ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
    ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
    bash scripts/abora-gaming.sh remove wine mangohud gamemode >/dev/null 2>&1 \
  && grep -q '^remove wine mangohud gamemode$' "$tmp_gaming_apps_log" \
  && grep -q 'abora.gaming.launchers = false;' "$tmp_gaming_lean_module" \
  && grep -q 'abora.gaming.mangohud = false;' "$tmp_gaming_lean_module" \
  && grep -q 'abora.gaming.gamemode = false;' "$tmp_gaming_lean_module"; then
  pass "runtime: abora gaming remove disables reinstalling feature families"
else
  fail "runtime: abora gaming remove disables reinstalling feature families"
fi

tmp_gaming_before_stale_remove="$tmp_ok/gaming-before-stale-remove.nix"

cp "$tmp_gaming_module" "$tmp_gaming_before_stale_remove"

if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh remove stale-removed-app >/dev/null 2>&1 \
  && grep -q '^remove stale-removed-app$' "$tmp_gaming_apps_log" \
  && cmp -s "$tmp_gaming_module" "$tmp_gaming_before_stale_remove"; then
  pass "runtime: abora gaming remove lets app manager clean stale ids"
else
  fail "runtime: abora gaming remove lets app manager clean stale ids"
fi

tmp_gaming_before_bad="$tmp_ok/gaming-before-bad.nix"

cp "$tmp_gaming_module" "$tmp_gaming_before_bad"

if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh install steem >/tmp/abora-gaming-bad-app.out 2>&1; then
  fail "runtime: abora gaming rejects unknown apps before writing config"
elif cmp -s "$tmp_gaming_module" "$tmp_gaming_before_bad"; then
  pass "runtime: abora gaming rejects unknown apps before writing config"
else
  fail "runtime: abora gaming rejects unknown apps before writing config"
fi

tmp_gaming_before_dry="$tmp_ok/gaming-before-dry.nix"

cp "$tmp_gaming_module" "$tmp_gaming_before_dry"

if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh install steam --dry-run >/dev/null 2>&1 \
  && cmp -s "$tmp_gaming_module" "$tmp_gaming_before_dry"; then
  pass "runtime: abora gaming install --dry-run is read-only"
else
  fail "runtime: abora gaming install --dry-run is read-only"
fi

tmp_gaming_before_flag="$tmp_ok/gaming-before-flag.nix"

cp "$tmp_gaming_module" "$tmp_gaming_before_flag"

if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh install steam --not-a-real-option >/tmp/abora-gaming-bad-flag.out 2>&1; then
  fail "runtime: abora gaming rejects unknown install flags before writing config"
elif cmp -s "$tmp_gaming_module" "$tmp_gaming_before_flag"; then
  pass "runtime: abora gaming rejects unknown install flags before writing config"
else
  fail "runtime: abora gaming rejects unknown install flags before writing config"
fi

tmp_gaming_before="$tmp_ok/gaming-before.nix"

cp "$tmp_gaming_module" "$tmp_gaming_before"

if PATH="$tmp_gaming_path:/usr/bin:/bin" \
  ABORA_SYSTEM_CONFIG="$tmp_gaming_config" \
  ABORA_UI_LIB="$repo_dir/scripts/abora-ui.sh" \
  ABORA_GAMING_APPS_LOG="$tmp_gaming_apps_log" \
  bash scripts/abora-gaming.sh install >/tmp/abora-gaming-noarg.out 2>&1; then
  fail "runtime: abora gaming install without an app is read-only"
elif cmp -s "$tmp_gaming_module" "$tmp_gaming_before"; then
  pass "runtime: abora gaming install without an app is read-only"
else
  fail "runtime: abora gaming install without an app is read-only"
fi

if python3 - <<'PY'
import re
from pathlib import Path
text = Path('nix/modules/abora-options.nix').read_text()

def desktop_text(var):
    m = re.search(rf'{var}\s*=\s*pkgs\.writeTextFile\s*\{{.*?text\s*=\s*\'\'\n(.*?)\n\s*\'\';\n\s*\}};', text, re.S)
    return m.group(1) if m else ''

launcher = desktop_text('steamBigPictureDesktop')
session = desktop_text('gamescopeSessionDesktop')
autostart = re.search(r'environment\.etc\."xdg/autostart/abora-steam-big-picture\.desktop"\.text\s*=\s*\'\'\n(.*?)\n\s*\'\';', text, re.S)
autostart_text = autostart.group(1) if autostart else ''

def has_lines(block, *lines):
    return all(line in block for line in lines)

ok = (
    has_lines(
        launcher,
        '[Desktop Entry]',
        'Type=Application',
        'Name=Steam Big Picture',
        'Exec=abora-steam-big-picture',
        'Icon=steam',
        'Categories=Game;',
        'Terminal=false',
    )
    and has_lines(
        session,
        '[Desktop Entry]',
        'Type=Application',
        'Name=Abora Gaming',
        'Exec=abora-steam-gamescope-session',
    )
    and has_lines(
        autostart_text,
        '[Desktop Entry]',
        'Type=Application',
        'Exec=abora-steam-big-picture',
        'X-GNOME-Autostart-enabled=true',
    )
)
raise SystemExit(0 if ok else 1)
PY
then
  pass "runtime: Abora Gaming desktop/session entries keep required fields"
else
  fail "runtime: Abora Gaming desktop/session entries keep required fields"
fi

tmp_steam_path="$(mktemp -d)"

tmp_steam_log="$tmp_ok/steam-big-picture.log"

cat > "$tmp_steam_path/steam" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$tmp_steam_log"
case "\$*" in
  steam://open/bigpicture|-gamepadui*) exit 0 ;;
  *) exit 1 ;;
esac
EOF

chmod +x "$tmp_steam_path/steam"

: > "$tmp_steam_log"

if PATH="$tmp_steam_path:/usr/bin:/bin" bash scripts/abora-gaming.sh big-picture >/dev/null 2>&1 \
  && grep -qx 'steam://open/bigpicture' "$tmp_steam_log" \
  && : > "$tmp_steam_log" \
  && PATH="$tmp_steam_path:/usr/bin:/bin" bash scripts/abora-gaming.sh big-picture --session >/dev/null 2>&1 \
  && grep -qx -- '-gamepadui' "$tmp_steam_log" \
  && [[ "$(wc -l < "$tmp_steam_log" | tr -d ' ')" == "1" ]] \
  && : > "$tmp_steam_log" \
  && PATH="$tmp_steam_path:/usr/bin:/bin" bash scripts/abora-gaming.sh session >/dev/null 2>&1 \
  && grep -qx -- '-gamepadui' "$tmp_steam_log" \
  && [[ "$(wc -l < "$tmp_steam_log" | tr -d ' ')" == "1" ]]; then
  pass "runtime: Abora Gaming Big Picture uses desktop URI and session-safe Steam mode"
else
  fail "runtime: Abora Gaming Big Picture uses desktop URI and session-safe Steam mode"
fi

tmp_steam_fallback_path="$(mktemp -d)"

tmp_steam_fallback_log="$tmp_ok/steam-big-picture-fallback.log"

cat > "$tmp_steam_fallback_path/steam" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$tmp_steam_fallback_log"
case "\$*" in
  -bigpicture*) exit 0 ;;
  *) exit 1 ;;
esac
EOF

chmod +x "$tmp_steam_fallback_path/steam"

: > "$tmp_steam_fallback_log"

if PATH="$tmp_steam_fallback_path:/usr/bin:/bin" bash scripts/abora-gaming.sh big-picture --session >/tmp/steam-big-picture-fallback.out 2>&1 \
  && grep -qx -- '-gamepadui' "$tmp_steam_fallback_log" \
  && grep -qx -- '-bigpicture' "$tmp_steam_fallback_log" \
  && grep -q 'trying legacy Big Picture mode' /tmp/steam-big-picture-fallback.out; then
  pass "runtime: Abora Gaming Big Picture explains legacy fallback"
else
  fail "runtime: Abora Gaming Big Picture explains legacy fallback"
fi

testlib_finish
