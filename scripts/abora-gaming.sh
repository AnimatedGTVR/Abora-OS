#!/usr/bin/env bash
set -euo pipefail

ui_lib="${ABORA_UI_LIB:-/etc/abora/ui.sh}"
if [[ -r "$ui_lib" ]]; then
  # shellcheck source=/dev/null
  source "$ui_lib"
fi
c_cyan="${c_cyan:-$'\033[1;36m'}"; c_blue="${c_blue:-$'\033[1;34m'}"
c_green="${c_green:-$'\033[1;32m'}"; c_yellow="${c_yellow:-$'\033[1;33m'}"
c_red="${c_red:-$'\033[1;31m'}"; c_reset="${c_reset:-$'\033[0m'}"
declare -F info >/dev/null 2>&1 || info() { printf '%s\n' "$*"; }
declare -F ok >/dev/null 2>&1 || ok() { printf '%s✓%s %s\n' "$c_green" "$c_reset" "$*"; }
declare -F warn >/dev/null 2>&1 || warn() { printf '%s!%s %s\n' "$c_yellow" "$c_reset" "$*"; }
declare -F err >/dev/null 2>&1 || err() { printf '%sx%s %s\n' "$c_red" "$c_reset" "$*" >&2; }

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

show_help() {
  cat <<'EOF'
Abora Gaming commands:
  abora gaming status       show installed gaming tools
  abora gaming welcome      open Abora Gaming Welcome (sign in, install a platform)
  abora gaming install steam
                            install a gaming app from the Abora app catalog
  abora gaming remove steam
                            remove a gaming app from the Abora app catalog
  abora gaming enable       enable desktop gaming
  abora gaming disable      disable the gaming layer
  abora gaming big-picture  launch Steam Big Picture
  abora gaming big-picture on|off
                            toggle the Steam Big Picture launcher
  abora gaming steam on|off
                            toggle Steam and Steam-dependent launchers
  abora gaming session      launch the controller session path
  abora gaming gamescope on|off
                            toggle the Gamescope login session
  abora gaming controllers on|off
                            toggle Steam/controller udev support
  abora gaming mangohud on|off
                            toggle MangoHud
  abora gaming gamemode on|off
                            toggle GameMode
  abora gaming vulkan on|off
                            toggle Vulkan diagnostic tools
  abora gaming launchers on|off
                            toggle common game launchers
  abora gaming autostart on|off
                            toggle Steam Big Picture autostart
  abora gaming doctor       check common gaming requirements
  abora gaming repair-cache clear stale local Nix fetch cache files
  abora gaming logs         show recent Abora install/config logs
  abora gaming help         show this help

After changing settings, run:
  sudo abora update
EOF
}

normalize_bool() {
  case "${1:-}" in
    true|yes|y|on|1|enable|enabled) printf 'true' ;;
    false|no|n|off|0|disable|disabled) printf 'false' ;;
    *)
      err "Use on/off, true/false, yes/no, or 1/0."
      exit 1
      ;;
  esac
}

config_file="${ABORA_SYSTEM_CONFIG:-/etc/nixos}/abora-local.nix"

write_bool_fallback() {
  local key="$1" value="$2" escaped_key tmp
  escaped_key="${key//./\\.}"
  [[ -f "$config_file" ]] || {
    err "No Abora config found at ${config_file}."
    err "Run this on an installed Abora system, or use: ABORA_SYSTEM_CONFIG=/path/to/etc/nixos"
    exit 1
  }
  if grep -Eq "^[[:space:]]*abora\\.${escaped_key}[[:space:]]*=" "$config_file"; then
    sed -i -E "s|^[[:space:]]*abora\\.${escaped_key}[[:space:]]*=.*|  abora.${key} = ${value};|" "$config_file"
    return 0
  fi
  tmp="$(mktemp)"
  awk -v line="  abora.${key} = ${value};" '
    /^[[:space:]]*}[[:space:]]*$/ && !done { print line; done=1 }
    { print }
    END { if (!done) print line }
  ' "$config_file" > "$tmp"
  cp "$tmp" "$config_file"
  rm -f "$tmp"
}

backup_config_state() {
  local backup_file="$1"

  if [[ -f "$config_file" ]]; then
    cp "$config_file" "$backup_file"
  else
    : > "${backup_file}.missing"
  fi
}

restore_config_state() {
  local backup_file="$1"

  if [[ -f "$backup_file" ]]; then
    cp "$backup_file" "$config_file"
  else
    rm -f "$config_file"
  fi
}

set_config_bool() {
  local key="$1" value="$2"
  case "$key" in
    gaming) key="gaming.enable" ;;
    gaming.steam) key="gaming.steam" ;;
    gaming.big-picture) key="gaming.bigPictureShortcut" ;;
    gaming.autostart) key="gaming.bigPictureAutostart" ;;
    gaming.gamescope) key="gaming.gamescopeSession" ;;
    gaming.controllers) key="gaming.controllerSupport" ;;
    gaming.mangohud) key="gaming.mangohud" ;;
    gaming.gamemode) key="gaming.gamemode" ;;
    gaming.vulkan) key="gaming.vulkanTools" ;;
    gaming.launchers) key="gaming.launchers" ;;
  esac
  if has_cmd abora-config; then
    abora-config set "$key" "$value"
  else
    write_bool_fallback "$key" "$value"
    ok "abora.${key} set to ${value}"
    warn "Run sudo abora update to rebuild the system."
  fi
}

enable_gaming() {
  set_config_bool gaming.enable true
  set_config_bool gaming.steam true
  set_config_bool gaming.bigPictureShortcut true
  set_config_bool gaming.controllerSupport true
  set_config_bool gaming.mangohud true
  set_config_bool gaming.gamemode true
  set_config_bool gaming.vulkanTools true
  set_config_bool gaming.launchers true
}

enable_gaming_layer() {
  set_config_bool gaming.enable true
}

enable_steam() {
  set_config_bool gaming.enable true
  set_config_bool gaming.steam true
}

disable_steam() {
  set_config_bool gaming.steam false
  set_config_bool gaming.bigPictureShortcut false
  set_config_bool gaming.bigPictureAutostart false
  set_config_bool gaming.gamescopeSession false
  set_config_bool gaming.controllerSupport false
}

disable_gaming() {
  set_config_bool gaming.enable false
  set_config_bool gaming.steam false
  set_config_bool gaming.bigPictureShortcut false
  set_config_bool gaming.bigPictureAutostart false
  set_config_bool gaming.gamescopeSession false
  set_config_bool gaming.controllerSupport false
  set_config_bool gaming.mangohud false
  set_config_bool gaming.gamemode false
  set_config_bool gaming.vulkanTools false
  set_config_bool gaming.launchers false
}

enable_big_picture() {
  set_config_bool gaming.enable true
  set_config_bool gaming.steam true
  set_config_bool gaming.bigPictureShortcut true
}

enable_for_installed_apps() {
  local app_id
  enable_gaming_layer
  for app_id in "$@"; do
    case "$app_id" in
      --*) ;;
      steam)
        set_config_bool gaming.steam true
        set_config_bool gaming.controllerSupport true
        ;;
      lutris|heroic|bottles|wine|winetricks)
        set_config_bool gaming.launchers true
        ;;
      mangohud)
        set_config_bool gaming.mangohud true
        ;;
      gamemode)
        set_config_bool gaming.gamemode true
        ;;
    esac
  done
}

disable_for_removed_apps() {
  local app_id
  for app_id in "$@"; do
    case "$app_id" in
      --*) ;;
      steam)
        disable_steam
        ;;
      lutris|heroic|bottles|wine|winetricks)
        set_config_bool gaming.launchers false
        ;;
      mangohud)
        set_config_bool gaming.mangohud false
        ;;
      gamemode)
        set_config_bool gaming.gamemode false
        ;;
    esac
  done
}

enable_gamescope_session() {
  set_config_bool gaming.enable true
  set_config_bool gaming.steam true
  set_config_bool gaming.gamescopeSession true
}

enable_big_picture_autostart() {
  enable_big_picture
  set_config_bool gaming.bigPictureAutostart true
}

config_bool_enabled() {
  local key="$1"
  [[ -r "$config_file" ]] && grep -Eq "abora\\.${key}[[:space:]]*=[[:space:]]*true" "$config_file"
}

print_config_row() {
  local label="$1" key="$2"
  if config_bool_enabled "$key"; then
    ok "$label: enabled"
  else
    warn "$label: disabled in ${config_file}"
  fi
}

print_status_row() {
  local label="$1"
  local command_name="$2"
  if has_cmd "$command_name"; then
    ok "$label: installed"
  else
    warn "$label: missing"
  fi
}

print_status_any() {
  local label="$1"
  local command_name
  shift
  for command_name in "$@"; do
    if has_cmd "$command_name"; then
      ok "$label: installed"
      return 0
    fi
  done
  warn "$label: missing"
}

check_disk_space() {
  local path="${1:-/nix/store}"
  local available_kb=""
  local available_gib=0

  [[ -e "$path" ]] || path="/"
  available_kb="$(df -Pk "$path" 2>/dev/null | awk 'NR == 2 { print $4 }')"
  [[ "$available_kb" =~ ^[0-9]+$ ]] || return 0
  available_gib=$((available_kb / 1024 / 1024))

  if [[ "$available_gib" -lt 8 ]]; then
    warn "Low free space near ${path}: ${available_gib} GiB available"
    info "Try: sudo nix-collect-garbage -d"
  else
    ok "Free space near ${path}: ${available_gib} GiB available"
  fi
}

check_fetcher_cache() {
  local cache_dir="${HOME:-}/.cache/nix"
  local cache

  [[ -n "${HOME:-}" && -d "$cache_dir" ]] || return 0
  shopt -s nullglob
  for cache in "$cache_dir"/fetcher-cache-v*.sqlite "$cache_dir"/fetcher-cache-v*.sqlite-*; do
    [[ -e "$cache" ]] || continue
    if [[ ! -r "$cache" ]]; then
      warn "Nix fetch cache is not readable: ${cache}"
      info "Try: rm -f ~/.cache/nix/fetcher-cache-v*.sqlite*"
      return 0
    fi
  done
}

repair_fetcher_cache() {
  local cache_dir="${HOME:-}/.cache/nix"
  local cache removed=false

  if [[ -z "${HOME:-}" ]]; then
    err "HOME is not set, so I cannot find the local Nix fetch cache."
    exit 1
  fi
  if [[ ! -d "$cache_dir" ]]; then
    ok "No local Nix fetch cache directory found at ${cache_dir}"
    return 0
  fi
  shopt -s nullglob
  for cache in "$cache_dir"/fetcher-cache-v*.sqlite "$cache_dir"/fetcher-cache-v*.sqlite-*; do
    [[ -e "$cache" ]] || continue
    rm -f -- "$cache"
    removed=true
  done
  if [[ "$removed" == "true" ]]; then
    ok "Cleared local Nix fetch cache files."
    info "Try the Gaming install or update again."
  else
    ok "No stale local Nix fetch cache files were found."
  fi
}

show_status() {
  printf '%sABORA OS%s  %sGaming%s\n\n' "${c_blue:-}" "${c_reset:-}" "${c_cyan:-}" "${c_reset:-}"
  print_status_row "Steam" steam
  print_status_row "Gamescope" gamescope
  print_status_row "MangoHud" mangohud
  print_status_any "GameMode" gamemoderun gamemoded
  print_status_any "Heroic" heroic heroic-games-launcher
  print_status_row "Lutris" lutris
  print_status_row "Bottles" bottles
  print_status_row "Wine" wine
  print_status_row "Winetricks" winetricks
  printf '\n'
  if [[ -r "$config_file" ]] && grep -Eq 'abora\.gaming\.enable[[:space:]]*=[[:space:]]*true' "$config_file"; then
    ok "Abora gaming option is enabled"
  else
    warn "Abora gaming option is not enabled in ${config_file}"
  fi
  if [[ -r "$config_file" ]] && grep -Eq 'abora\.gaming\.steam[[:space:]]*=[[:space:]]*false' "$config_file"; then
    warn "Steam is disabled in Abora Gaming"
  fi
}

run_doctor() {
  show_status
  printf '\n'
  print_config_row "Gaming layer" "gaming.enable"
  print_config_row "Steam option" "gaming.steam"
  print_config_row "Big Picture launcher" "gaming.bigPictureShortcut"
  print_config_row "Big Picture autostart" "gaming.bigPictureAutostart"
  print_config_row "Gamescope session" "gaming.gamescopeSession"
  print_config_row "Controller support" "gaming.controllerSupport"
  print_config_row "MangoHud option" "gaming.mangohud"
  print_config_row "GameMode option" "gaming.gamemode"
  print_config_row "Vulkan tools option" "gaming.vulkanTools"
  print_config_row "Launcher bundle" "gaming.launchers"
  printf '\n'
  if [[ -e /dev/dri/renderD128 || -d /dev/dri ]]; then
    ok "GPU render device found"
  else
    warn "No /dev/dri render device found"
  fi
  if has_cmd vulkaninfo; then
    ok "Vulkan tools installed"
  else
    warn "vulkaninfo missing; install vulkan-tools for deeper checks"
  fi
  check_disk_space /nix/store
  check_fetcher_cache
  if has_cmd steam; then
    info "Try: ${c_cyan:-}abora gaming big-picture${c_reset:-}"
  else
    info "Try: ${c_cyan:-}abora gaming install steam${c_reset:-}"
  fi
}

launch_big_picture() {
  if ! has_cmd steam; then
    err "Steam is not installed. Run: abora gaming install steam"
    exit 1
  fi
  export STEAM_FORCE_DESKTOPUI_SCALING="${STEAM_FORCE_DESKTOPUI_SCALING:-1}"
  if [[ "${1:-}" == "--session" ]]; then
    shift
    steam -gamepadui "$@" || {
      warn "Steam Gamepad UI failed; trying legacy Big Picture mode."
      exec steam -bigpicture "$@"
    }
    return 0
  fi
  if [[ $# -eq 0 ]]; then
    steam steam://open/bigpicture || steam -gamepadui || {
      warn "Steam URI/Gamepad UI failed; trying legacy Big Picture mode."
      exec steam -bigpicture
    }
  else
    steam -gamepadui "$@" || {
      warn "Steam Gamepad UI failed; trying legacy Big Picture mode."
      exec steam -bigpicture "$@"
    }
  fi
}

launch_session() {
  if has_cmd gamescope; then
    exec gamescope -e -f -- "$0" big-picture --session "$@"
  fi
  warn "Gamescope is not installed; starting Steam Big Picture directly."
  launch_big_picture --session "$@"
}

launch_welcome() {
  if ! has_cmd abora-gaming-welcome-gui; then
    err "abora-gaming-welcome-gui is not available on this system."
    exit 1
  fi
  exec abora-gaming-welcome-gui
}

show_gaming_logs() {
  local abora_cmd
  abora_cmd="$(command -v abora || true)"
  if [[ -z "$abora_cmd" ]]; then
    if [[ -x /etc/abora/abora.sh ]]; then
      abora_cmd="/etc/abora/abora.sh"
    else
      err "abora logs is not available on this system."
      exit 1
    fi
  fi
  "$abora_cmd" logs --lines "${1:-200}"
}

run_app_action() {
  local action="$1"
  shift
  require_app_args "$action" "$@"
  if ! has_cmd abora-apps; then
    err "abora-apps is not available on this system."
    exit 1
  fi
  abora-apps "$action" "$@"
}

validate_app_args() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --dry-run|--no-rebuild) ;;
      --*)
        err "Unknown app option: ${arg}"
        exit 1
      ;;
      *) ;;
    esac
  done
}

app_args_have_dry_run() {
  local arg
  for arg in "$@"; do
    [[ "$arg" == "--dry-run" ]] && return 0
  done
  return 1
}

app_args_include_id() {
  local wanted="$1" arg
  shift
  for arg in "$@"; do
    [[ "$arg" == --* ]] && continue
    [[ "$arg" == "$wanted" ]] && return 0
  done
  return 1
}

validate_app_ids() {
  local app_id seen_any=false
  if ! has_cmd abora-apps; then
    err "abora-apps is not available on this system."
    exit 1
  fi
  validate_app_args "$@"
  for app_id in "$@"; do
    [[ "$app_id" == --* ]] && continue
    seen_any=true
    if ! abora-apps info "$app_id" >/dev/null 2>&1; then
      err "Unknown gaming app id: ${app_id}"
      err "Try: abora apps search ${app_id}"
      exit 1
    fi
  done
  if [[ "$seen_any" != "true" ]]; then
    err "Usage: abora gaming install <app-id...> [--no-rebuild] [--dry-run]"
    err "Try: abora gaming install steam"
    exit 1
  fi
}

require_app_args() {
  local action="$1"
  shift
  if [[ $# -eq 0 ]]; then
    err "Usage: abora gaming ${action} <app-id...>"
    err "Try: abora gaming ${action} steam"
    exit 1
  fi
}

case "${1:-status}" in
  status)
    show_status
    ;;
  doctor)
    run_doctor
    ;;
  repair-cache|fix-cache|clear-cache)
    repair_fetcher_cache
    ;;
  logs|log)
    shift
    show_gaming_logs "${1:-200}"
    ;;
  welcome)
    launch_welcome
    ;;
  big-picture|bigpicture)
    shift
    case "${1:-}" in
      on|off|true|false|yes|no|1|0|enable|disable|enabled|disabled)
        value="$(normalize_bool "$1")"
        if [[ "$value" == "true" ]]; then
          enable_big_picture
        else
          set_config_bool gaming.big-picture false
        fi
        ;;
      "")
        launch_big_picture
        ;;
      *)
        launch_big_picture "$@"
        ;;
    esac
    ;;
  session|gamescope-session)
    shift
    launch_session "$@"
    ;;
  enable)
    enable_gaming
    ;;
  disable)
    disable_gaming
    ;;
  install|add)
    shift
    require_app_args add "$@"
    validate_app_ids "$@"
    config_backup=""
    if ! app_args_have_dry_run "$@"; then
      config_backup="$(mktemp)"
      backup_config_state "$config_backup"
      enable_for_installed_apps "$@"
    fi
    if ! run_app_action add "$@"; then
      if [[ -n "${config_backup:-}" ]]; then
        restore_config_state "$config_backup"
        rm -f "$config_backup" "${config_backup}.missing"
        warn "Restored previous gaming settings because the app install failed."
      fi
      exit 1
    fi
    [[ -z "${config_backup:-}" ]] || rm -f "$config_backup" "${config_backup}.missing"
    ;;
  uninstall|remove|rm)
    shift
    require_app_args remove "$@"
    validate_app_args "$@"
    config_backup=""
    if ! app_args_have_dry_run "$@"; then
      config_backup="$(mktemp)"
      backup_config_state "$config_backup"
      disable_for_removed_apps "$@"
    fi
    if ! run_app_action remove "$@"; then
      if [[ -n "${config_backup:-}" ]]; then
        restore_config_state "$config_backup"
        rm -f "$config_backup" "${config_backup}.missing"
        warn "Restored previous gaming settings because the app removal failed."
      fi
      exit 1
    fi
    [[ -z "${config_backup:-}" ]] || rm -f "$config_backup" "${config_backup}.missing"
    ;;
  steam)
    shift
    value="$(normalize_bool "${1:-}")"
    if [[ "$value" == "true" ]]; then
      enable_steam
      set_config_bool gaming.controllerSupport true
    else
      disable_steam
    fi
    ;;
  gamescope)
    shift
    value="$(normalize_bool "${1:-}")"
    if [[ "$value" == "true" ]]; then
      enable_gamescope_session
    else
      set_config_bool gaming.gamescope false
    fi
    ;;
  controllers|controller)
    shift
    set_config_bool gaming.controllers "$(normalize_bool "${1:-}")"
    ;;
  mangohud)
    shift
    set_config_bool gaming.mangohud "$(normalize_bool "${1:-}")"
    ;;
  gamemode)
    shift
    set_config_bool gaming.gamemode "$(normalize_bool "${1:-}")"
    ;;
  vulkan)
    shift
    set_config_bool gaming.vulkan "$(normalize_bool "${1:-}")"
    ;;
  launchers)
    shift
    set_config_bool gaming.launchers "$(normalize_bool "${1:-}")"
    ;;
  autostart)
    shift
    value="$(normalize_bool "${1:-}")"
    if [[ "$value" == "true" ]]; then
      enable_big_picture_autostart
    else
      set_config_bool gaming.autostart false
    fi
    ;;
  help|--help|-h)
    show_help
    ;;
  *)
    err "Unknown gaming command: $1"
    show_help >&2
    exit 1
    ;;
esac
