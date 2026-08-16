#!/usr/bin/env bash
set -euo pipefail

repo_url="${ABORA_REPO_URL:-https://github.com/AnimatedGTVR/Abora-OS.git}"
repo_urls="${ABORA_REPO_URLS:-$repo_url https://github.com/AboraProject/Abora-OS.git}"
repo_ref="${ABORA_REPO_REF:-edge}"
default_checkout="${ABORA_SOURCE_DIR:-${HOME:-/tmp}/Abora-OS}"
target="${ABORA_BUILD_TARGET:-.#nixosConfigurations.abora.config.system.build.toplevel}"
fallback_target="${ABORA_BUILD_FALLBACK_TARGET:-.#nixosConfigurations.abora-live-cosmic.config.system.build.toplevel}"
default_target=".#nixosConfigurations.abora.config.system.build.toplevel"

usage() {
  cat <<'EOF'
Usage:
  abora build --from-source [--checkout DIR] [--ref BRANCH] [--target FLAKE_TARGET]

Clone or use an Abora OS source checkout, then build Abora with Nix.

Examples:
  abora build --from-source
  abora build --from-source --checkout ~/src/Abora-OS
  abora build --from-source --ref main
  abora build --from-source --target .#packages.x86_64-linux.iso
EOF
}

checkout="$default_checkout"
checkout_explicit=0
from_source=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-source)
      from_source=1
      shift
      ;;
    --checkout)
      [[ -n "${2:-}" ]] || { printf 'abora build: --checkout needs a directory\n' >&2; exit 2; }
      checkout="$2"
      checkout_explicit=1
      shift 2
      ;;
    --target)
      [[ -n "${2:-}" ]] || { printf 'abora build: --target needs a flake target\n' >&2; exit 2; }
      target="$2"
      shift 2
      ;;
    --ref|--branch)
      [[ -n "${2:-}" ]] || { printf 'abora build: --ref needs a branch or tag\n' >&2; exit 2; }
      repo_ref="$2"
      shift 2
      ;;
    help|--help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'abora build: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$from_source" != 1 ]]; then
  usage
  exit 2
fi

if ! command -v nix >/dev/null 2>&1; then
  printf 'abora build: nix is required. Install Nix with flakes enabled first.\n' >&2
  exit 1
fi

ref_fallback_candidates() {
  local selected_ref="$1"
  printf '%s\n' "$selected_ref"
  case "$selected_ref" in
    edge) printf '%s\n' main ;;
    main) printf '%s\n' edge ;;
  esac
}

clone_source_checkout() {
  local checkout="$1" url ref
  mkdir -p "$(dirname "$checkout")"

  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    for url in $repo_urls; do
      rm -rf "$checkout"
      printf 'abora build: cloning %s at %s\n' "$url" "$ref" >&2
      if git clone --depth=1 --branch "$ref" "$url" "$checkout"; then
        if [[ "$ref" != "$repo_ref" ]]; then
          printf 'abora build: selected ref "%s" was unavailable; using branch fallback "%s".\n' "$repo_ref" "$ref" >&2
        fi
        return 0
      fi
    done
  done < <(ref_fallback_candidates "$repo_ref")

  printf 'abora build: failed to clone Abora OS from every known remote.\n' >&2
  printf 'abora build: tried remotes: %s\n' "$repo_urls" >&2
  printf 'abora build: tried refs: %s\n' "$(ref_fallback_candidates "$repo_ref" | paste -sd ' ' -)" >&2
  printf 'abora build: use --ref <branch> or ABORA_REPO_URL=<url> for a custom mirror.\n' >&2
  return 1
}

if [[ "$checkout_explicit" != 1 && -f flake.nix && -d .git ]]; then
  checkout="$PWD"
elif [[ -d "$checkout/.git" && -f "$checkout/flake.nix" ]]; then
  :
else
  command -v git >/dev/null 2>&1 || {
    printf 'abora build: git is required to clone %s\n' "$repo_url" >&2
    exit 1
  }
  clone_source_checkout "$checkout"
fi

cd "$checkout"

if [[ "$target" == "$default_target" ]] && ! grep -q '^[[:space:]]*abora[[:space:]]*=' flake.nix; then
  printf 'This checkout does not expose the short "abora" flake alias yet.\n' >&2
  printf 'Using compatibility target instead.\n\n' >&2
  target="$fallback_target"
  fallback_target=""
fi

printf 'Abora source: %s\n' "$checkout"
printf 'Source ref:    %s\n' "$repo_ref"
printf 'Build target:  %s\n' "$target"
if [[ -n "$fallback_target" && "$target" != "$fallback_target" ]]; then
  printf 'Fallback:      %s\n' "$fallback_target"
fi
printf '\n'

if nix --extra-experimental-features "nix-command flakes" build "$target"; then
  printf '\nAbora build finished successfully.\n'
  exit 0
fi

if [[ -n "$fallback_target" && "$target" != "$fallback_target" ]]; then
  printf '\nPrimary build target failed.\n' >&2
  printf 'This can happen on older Abora checkouts before the short "abora" flake alias existed.\n' >&2
  printf 'Trying compatibility target: %s\n\n' "$fallback_target" >&2
  if nix --extra-experimental-features "nix-command flakes" build "$fallback_target"; then
    printf '\nAbora compatibility build finished successfully.\n'
    exit 0
  fi
fi

printf '\nAbora build failed.\n' >&2
exit 1
