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
  abora gaming enable       enable desktop gaming
  abora gaming disable      disable the gaming layer
  abora gaming big-picture  launch Steam Big Picture
  abora gaming big-picture on|off
                            toggle the Steam Big Picture launcher
  abora gaming gamescope on|off
                            toggle the Gamescope login session
  abora gaming vulkan on|off
                            toggle Vulkan diagnostic tools
  abora gaming autostart on|off
                            toggle Steam Big Picture autostart
  abora gaming doctor       check common gaming requirements
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

set_config_bool() {
  local key="$1" value="$2"
  case "$key" in
    gaming) key="gaming.enable" ;;
    gaming.big-picture) key="gaming.bigPictureShortcut" ;;
    gaming.autostart) key="gaming.bigPictureAutostart" ;;
    gaming.gamescope) key="gaming.gamescopeSession" ;;
    gaming.vulkan) key="gaming.vulkanTools" ;;
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
  set_config_bool gaming.bigPictureShortcut true
}

disable_gaming() {
  set_config_bool gaming.enable false
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

show_status() {
  printf '%sABORA OS%s  %sGaming%s\n\n' "${c_blue:-}" "${c_reset:-}" "${c_cyan:-}" "${c_reset:-}"
  print_status_row "Steam" steam
  print_status_row "Gamescope" gamescope
  print_status_row "MangoHud" mangohud
  print_status_row "GameMode" gamemoded
  print_status_row "Heroic" heroic
  print_status_row "Lutris" lutris
  print_status_row "Bottles" bottles
  printf '\n'
  if [[ -r "$config_file" ]] && grep -Eq 'abora\.gaming\.enable[[:space:]]*=[[:space:]]*true' "$config_file"; then
    ok "Abora gaming option is enabled"
  else
    warn "Abora gaming option is not enabled in ${config_file}"
  fi
}

run_doctor() {
  show_status
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
  if has_cmd steam; then
    info "Try: ${c_cyan:-}abora gaming big-picture${c_reset:-}"
  fi
}

launch_big_picture() {
  if ! has_cmd steam; then
    err "Steam is not installed. Enable abora.gaming.enable, then run sudo abora update."
    exit 1
  fi
  steam -gamepadui "$@" || exec steam -bigpicture "$@"
}

launch_welcome() {
  if ! has_cmd abora-gaming-welcome-gui; then
    err "abora-gaming-welcome-gui is not available on this system."
    exit 1
  fi
  exec abora-gaming-welcome-gui
}

case "${1:-status}" in
  status)
    show_status
    ;;
  doctor)
    run_doctor
    ;;
  welcome)
    launch_welcome
    ;;
  big-picture|bigpicture)
    shift
    case "${1:-}" in
      on|off|true|false|yes|no|1|0|enable|disable|enabled|disabled)
        set_config_bool gaming.big-picture "$(normalize_bool "$1")"
        ;;
      "")
        launch_big_picture
        ;;
      *)
        launch_big_picture "$@"
        ;;
    esac
    ;;
  enable)
    enable_gaming
    ;;
  disable)
    disable_gaming
    ;;
  gamescope)
    shift
    set_config_bool gaming.gamescope "$(normalize_bool "${1:-}")"
    ;;
  vulkan)
    shift
    set_config_bool gaming.vulkan "$(normalize_bool "${1:-}")"
    ;;
  autostart)
    shift
    set_config_bool gaming.autostart "$(normalize_bool "${1:-}")"
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
