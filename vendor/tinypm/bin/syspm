#!/usr/bin/env bash
set -euo pipefail

script_path="${BASH_SOURCE[0]}"
while [[ -L "$script_path" ]]; do
  script_parent="$(cd -P "$(dirname "$script_path")" && pwd)"
  script_target="$(readlink "$script_path")"
  if [[ "$script_target" == /* ]]; then
    script_path="$script_target"
  else
    script_path="$script_parent/$script_target"
  fi
done

script_dir="$(cd -P "$(dirname "$script_path")" && pwd)"

tinypm_cmd="$script_dir/tinypm"
if [[ ! -x "$tinypm_cmd" && -x "$script_dir/bin/tinypm" ]]; then
  tinypm_cmd="$script_dir/bin/tinypm"
fi

print_help() {
  cat <<'EOH'
syspm routes TinyPM through the native system package manager.
On Abora, that native path is typically Nix.

Usage:
  syspm update
  syspm install <package> [<package>...]
  syspm search <query>
  syspm remove <package> [<package>...]
  syspm list
  syspm pin <package>
  syspm unpin <package>
  syspm pinned
  syspm doctor
  syspm version
EOH
}

case "${1:-help}" in
  update|upgrade)
    shift
    exec "$tinypm_cmd" update -n "$@"
    ;;
  install|add)
    shift
    exec "$tinypm_cmd" install -n "$@"
    ;;
  search|find)
    shift
    exec "$tinypm_cmd" search -n "$@"
    ;;
  remove|rm|uninstall)
    shift
    exec "$tinypm_cmd" remove -n "$@"
    ;;
  list|ls)
    shift
    exec "$tinypm_cmd" list -n "$@"
    ;;
  pin)
    shift
    exec "$tinypm_cmd" pin -n "$@"
    ;;
  unpin)
    shift
    exec "$tinypm_cmd" unpin "$@"
    ;;
  pinned)
    shift
    exec "$tinypm_cmd" pinned "$@"
    ;;
  doctor)
    shift
    exec "$tinypm_cmd" doctor "$@"
    ;;
  version|--version)
    shift
    exec "$tinypm_cmd" version "$@"
    ;;
  help|-h|--help|"")
    print_help
    ;;
  *)
    printf 'syspm: unknown command: %s\n\n' "$1" >&2
    print_help >&2
    exit 1
    ;;
esac
