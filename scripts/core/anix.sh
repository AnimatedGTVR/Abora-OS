#!/usr/bin/env bash
set -euo pipefail

# NixOS system binaries (nixos-rebuild, etc.) live under /run/current-system
# and the system Nix profile, not a normal user PATH -- prepend them so ANIX
# works the same whether it's invoked from a login shell, a systemd unit, or
# sudo with a stripped environment.
export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"
anix_version="1.0.5 DEMO"

if [[ ! -f "$ui_lib" && -f /etc/abora/ui.sh ]]; then
    ui_lib="/etc/abora/ui.sh"
fi

if [[ -f "$ui_lib" ]]; then
    # shellcheck source=/dev/null
    source "$ui_lib"
else
    # Minimal fallback UI — used when running outside Abora OS
    ABORA_DIM=$'\033[38;5;242m'
    ABORA_NC=$'\033[0m'
    ABORA_CYAN=$'\033[38;5;44m'
    ABORA_WHITE=$'\033[1;97m'
    ABORA_GREEN=$'\033[38;5;77m'
    ABORA_RED=$'\033[38;5;203m'
    ABORA_YELLOW=$'\033[38;5;222m'
    ABORA_BLUE=$'\033[38;5;39m'
    abora_banner()   { printf '\n  %b%s%b  %b%s%b\n\n' "$ABORA_WHITE" "${1:-}" "$ABORA_NC" "$ABORA_DIM" "${2:-}" "$ABORA_NC"; }
    abora_success()  { printf '  \033[38;5;77m✓\033[0m  \033[38;5;77m%s\033[0m\n' "$1"; }
    abora_warn()     { printf '  \033[38;5;222m!\033[0m  \033[38;5;222m%s\033[0m\n' "$1"; }
    abora_error()    { printf '  \033[38;5;203m✗\033[0m  \033[38;5;203m%s\033[0m\n' "$1" >&2; }
    abora_step()     { printf '  \033[38;5;44m▸\033[0m  %s\n' "$1"; }
    abora_dim_line() { printf '  \033[38;5;242m%s\033[0m\n' "$1"; }
    abora_card_start() {
        printf '  %b┌─ %s ─%b\n' "$ABORA_BLUE" "${1:-}" "$ABORA_NC"
    }
    abora_card_end() {
        printf '  %b└────────%b\n' "$ABORA_BLUE" "$ABORA_NC"
    }
    abora_kv() {
        printf '  %b│%b  %b%-18s%b  %b%s%b\n' \
            "$ABORA_BLUE" "$ABORA_NC" \
            "$ABORA_DIM" "$1" "$ABORA_NC" \
            "$ABORA_CYAN" "${2:-}" "$ABORA_NC"
    }
fi

# From abora-ui.sh (ASA/ABT). Outside Abora, with the fallback UI above,
# switches simply run without a transaction.
if ! declare -F abora_abt_prefix >/dev/null; then
    abora_abt_prefix() { ABORA_ABT_PREFIX=(); }
fi
if ! declare -F abora_abt_pending >/dev/null; then
    abora_abt_pending() { :; }
fi

# Every path ANIX reads or writes is a variable with an ANIX_* environment
# override, defaulting to the real installed-system location. That's what
# lets the test suites and the e2e tests point a whole ANIX invocation at a
# throwaway temp directory instead of the real /etc/nixos, without any of
# the functions below needing to know they're under test.
config_dir="${ANIX_SYSTEM_CONFIG:-/etc/nixos}"
anix_file="${ANIX_CONFIG_FILE:-$config_dir/anix.nix}"       # the file `anix set`/`enable`/`package` write
abora_local_file="${config_dir}/abora-local.nix"             # written by the installer, read-only from here
flake_config_name="${ANIX_FLAKE_CONFIG_NAME:-abora}"         # nixosConfigurations.<this> in flake.nix
wallpaper_dir="${ANIX_WALLPAPER_DIR:-/etc/abora/wallpapers}"
anix_state_dir="${ANIX_STATE_DIR:-$config_dir/.anix}"        # git snapshots + this tool's own settings
anix_tool_config="${ANIX_TOOL_CONFIG:-$anix_state_dir/config}"
docs_dir="${ANIX_DOCS_DIR:-/etc/abora/docs/wiki}"
anix_doc_file="${ANIX_DOC_FILE:-$docs_dir/ANIX-V1.md}"
packages_doc_file="${ANIX_PACKAGES_DOC_FILE:-$docs_dir/Packages.md}"
abora_tools_doc_file="${ANIX_ABORA_TOOLS_DOC_FILE:-$docs_dir/Abora-Tools.md}"
recovery_doc_file="${ANIX_RECOVERY_DOC_FILE:-$docs_dir/Recovery.md}"

# ANIX v2 — pluggable configuration languages (docs/wiki/ANIX-V2-Languages.md).
# System adapters are installed by packages; user adapters are personal,
# per-account additions. Both are plain JSON manifests naming an id,
# extensions, and an argv command that emits an ANIX Plan on stdout.
anix_system_language_dir="${ANIX_SYSTEM_LANGUAGE_DIR:-/etc/anix/languages}"
anix_user_language_dir="${ANIX_USER_LANGUAGE_DIR:-$HOME/.config/anix/languages}"
anix_plan_version=1
# Plan JSON structural validation/parsing (well-formed JSON, planVersion,
# operation shapes, the "set" key allowlist, package-name syntax) is a real
# Native AOT C# binary (tools/abora-plan-tool) -- see its PlanParser.cs for
# why: it's the same class of "structured data through jq shell-outs and
# string matching" problem as tools/abora-update-resolver, and it replaces
# what used to be many `jq` subprocess calls (one per field per operation)
# with a single call that parses the whole plan at once. ANIX-specific
# business rules that must stay a single source of truth with do_toggle/
# do_set (feature_to_anix_key, per-key value validation) are NOT duplicated
# there -- see parse_and_validate_plan() below and PlanParser.cs's comment.
plan_tool_bin="${ABORA_PLAN_TOOL_BIN:-abora-plan-tool}"

valid_desktops=(
    none gnome plasma hyprland sway xfce cinnamon mate budgie lxqt pantheon
    i3 awesome openbox niri river qtile bspwm fluxbox
    icewm herbstluftwm cosmic mangowm lumina
)

default_wallpapers=(
    alpine-glacier.jpg
    tannheimer-mountains.jpg
    titlis-alps.jpg
    aurora-lofoten.jpg
)

# These are NixOS's own generation symlinks, not anything ANIX creates:
# /run/current-system always points at the profile actually booted, and
# system_profile_link is the profile `nixos-rebuild` adds a new generation
# to. generation_lines()/do_rollback() read these to list and switch
# generations without needing their own bookkeeping of what's installed.
current_system_link="${ANIX_CURRENT_SYSTEM:-/run/current-system}"
system_profile_link="${ANIX_SYSTEM_PROFILE:-/nix/var/nix/profiles/system}"

# Every state-changing command in this file goes through here instead of
# calling sudo directly, for one reason: the test suite sets
# ANIX_NO_SUDO=1 to run as the invoking user with no privilege escalation
# at all (writing into a throwaway ANIX_SYSTEM_CONFIG temp dir instead of
# the real /etc/nixos), and ANIX_ROOT_PATH lets those tests also control
# exactly which fake `nixos-rebuild`/`git` binaries are on PATH once
# escalated. A real install never sets either.
run_as_root() {
    if is_yes "${ANIX_NO_SUDO:-}"; then
        if [[ -n "${ANIX_ROOT_PATH:-}" ]]; then
            PATH="$ANIX_ROOT_PATH" "$@"
            return
        fi
        "$@"
        return
    fi
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
        return
    fi
    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"
        return
    fi
    abora_error "This command needs root privileges."
    exit 1
}

# ANIX never parses anix.nix as real Nix -- it's a fixed, hand-authored
# template (see ensure_anix_file's render_template) where every setting is
# always written as `anix.<key> = "<value>";` on its own line, so a plain
# regex line-match is enough to read a value back out. This only handles
# quoted string values; read_anix_bool_option (further down) is the
# unquoted true/false counterpart for booleans like anix.services.bluetooth.
read_anix_option() {
    local key="$1"
    local escaped_key="${key//./\\.}"
    [[ -f "$anix_file" ]] || return 0
    sed -nE "s|^[[:space:]]*anix\\.${escaped_key}[[:space:]]*=[[:space:]]*\"([^\"]+)\";.*|\1|p" "$anix_file" | head -n1
}

# Same idea as read_anix_option, but reads abora-local.nix (the installer's
# own generated file, e.g. abora.hostname / abora.desktop) instead of
# anix.nix -- used where ANIX needs to know what the installer originally
# set even before any `anix set` has ever touched anix.nix itself.
read_abora_option() {
    local key="$1"
    local escaped_key="${key//./\\.}"
    [[ -f "$abora_local_file" ]] || return 0
    sed -nE "s|^[[:space:]]*abora\\.${escaped_key}[[:space:]]*=[[:space:]]*\"([^\"]+)\";.*|\1|p" "$abora_local_file" | head -n1
}

# The installer sets abora.desktop once at install time; `anix set desktop`
# later overrides it by writing anix.desktop instead (abora-local.nix isn't
# touched again after install). Checking abora first, falling back to anix,
# means this always returns whichever one actually reflects reality.
current_configured_desktop() {
    local value=""
    value="$(read_abora_option "desktop")"
    if [[ -z "$value" ]]; then
        value="$(read_anix_option "desktop")"
    fi
    printf '%s' "${value:-unknown}"
}

# The "raw" counterpart to do_set: do_set always wraps its value in quotes
# (it's for user-facing strings like hostname/timezone), but some
# anix.<key> settings are booleans or Nix list/attrset literals
# (anix.services.bluetooth = true;, anix.packages = with pkgs; [ ... ];)
# that must NOT be quoted. Callers are responsible for passing $value
# already in its final Nix-literal form.
write_anix_raw_option() {
    local key="$1"
    local value="$2"
    local escaped_key="${key//./\\.}"

    ensure_anix_file
    abora_abt_pending "anix config changes" "$config_dir" run_as_root
    if grep -Eq "^[[:space:]]*anix\\.${escaped_key}[[:space:]]*=" "$anix_file"; then
        run_as_root sed -i -E \
            "s|^([[:space:]]*anix\\.${escaped_key}[[:space:]]*=).*$|\\1 ${value};|" \
            "$anix_file"
    else
        run_as_root sed -i -E \
            "/^[[:space:]]*}$/i\\  anix.${key} = ${value};" \
            "$anix_file"
    fi
}

# Minimal Nix string escaper: doubles backslashes, escapes double quotes.
# Deliberately narrower than do_set's own belt-and-suspenders check (which
# also bans literal ${ Nix antiquotation) -- this is used only for values
# already constrained elsewhere (see its call sites), not as a general-
# purpose safe-for-Nix-strings function on its own.
quote_nix_string() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

# nixos-rebuild's raw stderr is long and not written for end users. This
# pattern-matches the log for the handful of failures people actually hit
# (a typo'd option name, an unfree package with no allowUnfree, a plain
# syntax error) and prints a one-line plain-English explanation plus the
# relevant snippet, falling back to just the last few log lines for
# anything it doesn't recognize.
explain_nix_failure() {
    local log_file="$1"
    local line=""

    [[ -s "$log_file" ]] || return 0

    printf '\n'
    abora_error "Nix stopped before applying the config."

    if grep -q "The option .* does not exist" "$log_file"; then
        line="$(grep -m1 "The option .* does not exist" "$log_file" || true)"
        abora_warn "Unknown option in your config."
        printf '  %b%s%b\n' "$ABORA_DIM" "$line" "$ABORA_NC"
        if grep -q "The option \`abora'" "$log_file"; then
            abora_dim_line "Use nested options like 'abora.desktop = \"gnome\";', not 'abora = ...'."
        fi
    elif grep -qi "unfree" "$log_file"; then
        abora_warn "This looks like an unfree package block."
        abora_dim_line "ANIX normally sets 'anix.allowUnfree = true;'. Run: anix enable allowUnfree"
        abora_dim_line "Then retry the command. A one-off install (anix package install) follows the same setting."
    elif grep -q "syntax error" "$log_file"; then
        line="$(grep -m1 -B2 -A3 "syntax error" "$log_file" || true)"
        abora_warn "This looks like a Nix syntax error."
        printf '%s\n' "$line" | sed 's/^/    /'
    else
        abora_warn "Last lines from the Nix error:"
        tail -n 14 "$log_file" | sed 's/^/    /'
    fi

    abora_dim_line "Full log: ${log_file}"
    printf '\n'
}

validate_desktop() {
    local candidate="$1"
    local valid=""

    for valid in "${valid_desktops[@]}"; do
        [[ "$candidate" == "$valid" ]] && return 0
    done

    abora_error "Unknown desktop: ${candidate}"
    printf '  %bValid options:%b %s\n\n' "$ABORA_DIM" "$ABORA_NC" "${valid_desktops[*]}"
    exit 1
}

wallpaper_candidates() {
    if [[ -d "$wallpaper_dir" ]]; then
        find "$wallpaper_dir" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort
        return 0
    fi

    printf '%s\n' "${default_wallpapers[@]}"
}

validate_wallpaper() {
    local candidate="$1"
    if wallpaper_candidates | grep -Fxq "$candidate"; then
        return 0
    fi

    abora_error "Unknown wallpaper: ${candidate}"
    printf '  %bAvailable wallpapers:%b\n' "$ABORA_DIM" "$ABORA_NC"
    wallpaper_candidates | sed 's/^/    /'
    printf '\n'
    exit 1
}

# Shared truthy-string parser for every ANIX_* boolean env override in this
# file (ANIX_NO_SUDO, ANIX_ASSUME_YES, ...) so they all accept the same
# set of spellings instead of each call site inventing its own.
is_yes() {
    case "${1:-}" in
        1|yes|true|on|y|Y|YES|TRUE|ON) return 0 ;;
        *) return 1 ;;
    esac
}

# Every "are you sure?" prompt in this file goes through here. ANIX_ASSUME_YES
# is what lets --yes flags and the test suite skip prompts entirely; running
# with stdin that isn't a real terminal (a script, a CI runner) falls back to
# just taking $default rather than hanging on a read that can never return
# an answer.
confirm() {
    local prompt="$1"
    local default="${2:-yes}"
    local answer=""

    if is_yes "${ANIX_ASSUME_YES:-}"; then
        return 0
    fi

    if [[ ! -t 0 ]]; then
        [[ "$default" == "yes" ]]
        return
    fi

    if [[ "$default" == "yes" ]]; then
        printf '  %b%s [Y/n]%b ' "$ABORA_YELLOW" "$prompt" "$ABORA_NC"
    else
        printf '  %b%s [y/N]%b ' "$ABORA_YELLOW" "$prompt" "$ABORA_NC"
    fi

    read -r answer
    case "$answer" in
        "") [[ "$default" == "yes" ]] ;;
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

require_command() {
    local command="$1"
    if command -v "$command" >/dev/null 2>&1; then
        return 0
    fi
    abora_error "Missing required command: ${command}"
    exit 1
}

# Restricting profile names to this charset (no spaces, quotes, slashes, etc.)
# is what makes it safe to interpolate $profile directly into a flake
# reference string (`$config_dir#$profile`) below without any escaping.
validate_profile_name() {
    local profile="$1"
    if [[ "$profile" =~ ^[A-Za-z0-9._-]+$ ]]; then
        return 0
    fi
    abora_error "Invalid profile name: ${profile}"
    abora_dim_line "Use a flake config name like nix, minimal, stable, creator, or gaming."
    printf '\n'
    exit 1
}

# "nix" is the only profile family today, but the family/profile split
# (`anix switch nix <profile>`) exists so other flake families can be added
# later without changing the CLI shape.
profile_target() {
    local family="$1"
    local profile="${2:-}"

    case "$family" in
        nix) ;;
        *)
            abora_error "Unknown profile family: ${family}"
            abora_dim_line "Use: anix switch nix <profile>"
            printf '\n'
            exit 1
            ;;
    esac

    if [[ -z "$profile" ]]; then
        profile="$flake_config_name"
    fi

    validate_profile_name "$profile"
    printf '%s#%s' "$config_dir" "$profile"
}

# Reads a `key = value` line out of ANIX's own tool config (anix_tool_config —
# separate from anix.nix/abora-local.nix, this one stores anix.sh's own
# settings like snapshots.push). Missing file or missing key both fall
# through to $fallback rather than erroring, since most callers just want a
# sane default on a fresh system.
anix_config_get() {
    local key="$1"
    local fallback="${2:-}"
    [[ -f "$anix_tool_config" ]] || {
        printf '%s' "$fallback"
        return 0
    }
    sed -nE "s|^[[:space:]]*${key//./\\.}[[:space:]]*=[[:space:]]*(.+)[[:space:]]*$|\\1|p" "$anix_tool_config" | head -n1
}

anix_config_set() {
    local key="$1"
    local value="$2"
    run_as_root mkdir -p "$anix_state_dir"
    if [[ -f "$anix_tool_config" ]] && grep -Eq "^[[:space:]]*${key//./\\.}[[:space:]]*=" "$anix_tool_config"; then
        run_as_root sed -i -E "s|^([[:space:]]*${key//./\\.}[[:space:]]*=[[:space:]]*).*$|\\1${value}|" "$anix_tool_config"
    else
        run_as_root bash -c "$(printf 'printf '"'"'%%s\\n'"'"' %q >> %q' "${key}=${value}" "$anix_tool_config")"
    fi
}

git_available_for_config() {
    command -v git >/dev/null 2>&1 && [[ -d "$config_dir" ]]
}

config_is_git_repo() {
    git_available_for_config && {
        git -C "$config_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
            || run_as_root git -C "$config_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
    }
}

config_is_dirty() {
    config_is_git_repo || return 1
    [[ -n "$(git -C "$config_dir" status --porcelain 2>/dev/null || run_as_root git -C "$config_dir" status --porcelain 2>/dev/null || true)" ]]
}

# Nix flakes only see files that Git knows about (tracked or staged) inside a
# flake's directory — an untracked new .nix file is invisible to
# `nixos-rebuild --flake`. So every rebuild path stages the config dir first;
# this is silent/best-effort (errors swallowed) because it's a convenience
# step, not the operation the user actually asked for.
stage_config_for_flake() {
    command -v git >/dev/null 2>&1 || return 0
    [[ -d "$config_dir" ]] || return 0
    run_as_root git -C "$config_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    run_as_root git -C "$config_dir" add -A >/dev/null 2>&1 || true
}

# Best-effort secret scan run before any local snapshot: config repos can
# contain hand-edited files, and it's easy to paste a real API key/password
# into a .nix file without thinking of it as "committing a secret." This
# doesn't block the save, just warns and asks for confirmation.
warn_possible_secrets() {
    [[ -d "$config_dir" ]] || return 0

    local matches=""
    matches="$(
        grep -RInE \
            --exclude-dir=.git \
            --exclude-dir=.anix \
            --exclude='*.lock' \
            '(api[_-]?key|token|secret|password|passwd)[[:space:]]*[:=]' \
            "$config_dir" 2>/dev/null | head -n 8 || true
    )"

    [[ -n "$matches" ]] || return 0

    abora_warn "Possible secret found in your Nix config."
    abora_dim_line "Move real secrets to sops-nix or agenix before saving snapshots."
    printf '%s\n' "$matches" | sed 's/^/    /'
    printf '\n'

    confirm "Continue with the local snapshot anyway?" "no"
}

ensure_config_git_repo() {
    require_command git
    [[ -d "$config_dir" ]] || run_as_root mkdir -p "$config_dir"
    if config_is_git_repo; then
        return 0
    fi
    abora_warn "${config_dir} is not a Git repo yet."
    if confirm "Initialize a local Git repo for ANIX snapshots?" "yes"; then
        run_as_root git -C "$config_dir" -c init.defaultBranch=main init >/dev/null
    else
        abora_error "Snapshot cancelled."
        exit 1
    fi
}

# "Snapshot" == a plain local git commit of /etc/nixos. Pushing is opt-in
# (snapshots.push) and off by default so a fresh install never silently
# tries to push to a remote that doesn't exist/isn't authenticated.
do_save() {
    local message="${1:-anix: local config snapshot}"
    ensure_config_git_repo

    if ! warn_possible_secrets; then
        abora_error "Snapshot cancelled."
        exit 1
    fi

    run_as_root git -C "$config_dir" add -A
    if run_as_root git -C "$config_dir" diff --cached --quiet; then
        abora_warn "No config changes to snapshot."
        printf '\n'
        return 0
    fi

    run_as_root git -C "$config_dir" \
        -c user.name="${ANIX_GIT_USER_NAME:-ANIX}" \
        -c user.email="${ANIX_GIT_USER_EMAIL:-anix@localhost}" \
        commit -m "$message" >/dev/null

    abora_success "Saved local snapshot: ${message}"

    if is_yes "$(anix_config_get "snapshots.push" "false")"; then
        abora_step "Pushing snapshot because snapshots.push is true"
        run_as_root git -C "$config_dir" push
    else
        abora_dim_line "Snapshot stayed local. Enable pushing with: anix config set snapshots.push true"
    fi
    printf '\n'
}

maybe_snapshot_dirty_config() {
    local message="$1"

    if ! config_is_git_repo; then
        [[ -d "$config_dir" ]] || return 0
        abora_warn "No local snapshot history exists for ${config_dir}."
        if confirm "Create a snapshot before switching?" "yes"; then
            do_save "$message"
        else
            abora_warn "Continuing without a snapshot."
            printf '\n'
        fi
        return 0
    fi

    if ! config_is_dirty; then
        return 0
    fi

    abora_warn "You have unsaved local changes."
    if confirm "Save snapshot before switching?" "yes"; then
        do_save "$message"
    else
        abora_warn "Continuing without a snapshot."
        printf '\n'
    fi
}

# Every nixos-rebuild invocation goes through here so stderr is captured to a
# log file (via `tee`) as well as shown live — explain_nix_failure() then
# pattern-matches that same log on failure to turn a wall of Nix trace output
# into a specific, friendly hint.
run_rebuild() {
    local action="$1"
    local target="${2:-}"
    local log_file=""
    local rc=0

    log_file="$(mktemp "${TMPDIR:-/tmp}/anix-${action}.XXXXXX.log")"
    stage_config_for_flake

    case "$action" in
        dry-build)
            run_as_root nixos-rebuild dry-build --flake "$target" 2> >(tee "$log_file" >&2) || rc=$?
            ;;
        switch)
            abora_abt_prefix "anix switch ${target##*#}" "$config_dir"
            run_as_root "${ABORA_ABT_PREFIX[@]}" nixos-rebuild switch --flake "$target" 2> >(tee "$log_file" >&2) || rc=$?
            ;;
        build)
            run_as_root nixos-rebuild build --flake "$target" 2> >(tee "$log_file" >&2) || rc=$?
            ;;
        test)
            run_as_root nixos-rebuild test --flake "$target" 2> >(tee "$log_file" >&2) || rc=$?
            ;;
        boot)
            run_as_root nixos-rebuild boot --flake "$target" 2> >(tee "$log_file" >&2) || rc=$?
            ;;
        rollback)
            run_as_root nixos-rebuild switch --rollback 2> >(tee "$log_file" >&2) || rc=$?
            ;;
        *)
            abora_error "Unknown rebuild action: ${action}"
            exit 1
            ;;
    esac

    if [[ "$rc" -ne 0 ]]; then
        explain_nix_failure "$log_file"
        return "$rc"
    fi
}

git_branch_name() {
    config_is_git_repo || {
        printf 'none'
        return 0
    }
    git -C "$config_dir" branch --show-current 2>/dev/null | sed 's/^$/detached/' || printf 'unknown'
}

git_snapshot_count() {
    config_is_git_repo || {
        printf '0'
        return 0
    }
    git -C "$config_dir" rev-list --count HEAD 2>/dev/null || printf '0'
}

# Tries a real `nix eval` first (accurate, but needs flakes enabled and a
# working evaluation); falls back to grepping flake.nix's text for
# `name = nixpkgs.lib.nixosSystem` attributes if nix isn't usable, so profile
# tab-completion/listing still works on a system without experimental-features on.
flake_profile_candidates() {
    local flake_file="$config_dir/flake.nix"
    local profiles=""

    if command -v nix >/dev/null 2>&1 && [[ -f "$flake_file" ]]; then
        profiles="$(nix --extra-experimental-features "nix-command flakes" \
            eval --json "$config_dir#nixosConfigurations" --apply 'builtins.attrNames' 2>/dev/null \
            | tr -d '[]",' \
            | tr ' ' '\n' \
            | sed '/^$/d' \
            || true)"
        if [[ -n "$profiles" ]]; then
            printf '%s\n' "$profiles"
            return 0
        fi
    fi

    if [[ -f "$flake_file" ]]; then
        sed -nE 's|^[[:space:]]*([A-Za-z0-9._-]+)[[:space:]]*=[[:space:]]*nixpkgs\.lib\.nixosSystem.*|\1|p' "$flake_file" | sort -u
    fi
}

# Same fallback pattern as flake_profile_candidates(): prefer nix-env's real
# generation listing, but fall back to reading the profile's `-N-link`
# symlinks directly off disk if nix-env isn't available.
generation_lines() {
    if command -v nix-env >/dev/null 2>&1 && [[ -e "$system_profile_link" || -e "${system_profile_link}-1-link" ]]; then
        nix-env --list-generations --profile "$system_profile_link" 2>/dev/null || true
        return 0
    fi

    local generation
    { compgen -G "${system_profile_link}-*-link" 2>/dev/null || true; } | sort -V | while IFS= read -r generation; do
        printf '%s\n' "$(basename "$generation")"
    done
}

# Builds $target into a throwaway result link (without switching to it) so
# `nix store diff-closures` can compare it against /run/current-system —
# shows the user what packages would actually change before they commit to
# a real switch.
show_package_changes() {
    local target="$1"
    local tmp_dir=""

    if ! command -v nix >/dev/null 2>&1; then
        abora_warn "Cannot show package changes because nix is unavailable."
        return 0
    fi

    if [[ ! -e /run/current-system ]]; then
        abora_warn "Cannot compare package changes because /run/current-system is missing."
        return 0
    fi

    tmp_dir="$(mktemp -d)"
    abora_step "Building ${target} for package comparison"

    if (
        cd "$tmp_dir"
        run_rebuild build "$target" >/dev/null
    ); then
        if [[ -e "$tmp_dir/result" ]]; then
            abora_step "Package changes"
            nix store diff-closures /run/current-system "$tmp_dir/result" || true
        else
            abora_warn "Build finished, but no result link was created."
        fi
    else
        abora_warn "Package comparison build failed; dry-build output is still shown above."
    fi

    run_as_root rm -rf "$tmp_dir"
}

seed_value() {
    local key="$1"
    local fallback="$2"
    local value=""

    value="$(read_abora_option "$key")"
    if [[ -n "$value" ]]; then
        printf '%s' "$value"
    else
        printf '%s' "$fallback"
    fi
}

render_template() {
    local hostname timezone keyboard_console keyboard_xkb desktop wallpaper

    hostname="$(seed_value "hostname" "abora")"
    timezone="$(seed_value "timezone" "UTC")"
    keyboard_console="$(seed_value "keyboard.console" "us")"
    keyboard_xkb="$(seed_value "keyboard.xkb" "$keyboard_console")"
    desktop="$(seed_value "desktop" "gnome")"
    wallpaper="$(seed_value "wallpaper" "titlis-alps.jpg")"

    cat <<EOF
## ANIX is the simple layer on top of NixOS.
## Change values here, save the file, then run: anix apply
{ pkgs, ... }:
{
  ## Turns ANIX on.
  anix.enable = true;

  ## Your system name on the network.
  ## Command: anix set hostname <name>
  anix.hostname = "${hostname}";

  ## Timezone example: America/New_York
  ## Command: anix set timezone America/New_York
  anix.timezone = "${timezone}";

  ## Keyboard layouts for console and desktop sessions.
  ## Commands: anix set keyboard us ; anix set keyboard.xkb us
  anix.keyboard.console = "${keyboard_console}";
  anix.keyboard.xkb = "${keyboard_xkb}";

  ## Pick one desktop or use "none" for a console-only system.
  ## Command: anix set desktop gnome
  anix.desktop = "${desktop}";

  ## Wallpaper filename (used by Abora OS integrations when available).
  ## Command: anix set wallpaper titlis-alps.jpg
  anix.wallpaper = "${wallpaper}";

  ## Allow unfree apps like Discord and Steam.
  ## Command: anix enable allowUnfree
  anix.allowUnfree = true;

  ## Optional Abora Gaming layer.
  ## Commands: anix enable gaming ; anix enable gaming.steam ; anix enable gaming.big-picture ; anix enable gaming.vulkan
  anix.gaming.enable = false;
  anix.gaming.steam = true;
  anix.gaming.bigPictureShortcut = true;
  anix.gaming.bigPictureAutostart = false;
  anix.gaming.gamescopeSession = true;
  anix.gaming.controllerSupport = true;
  anix.gaming.mangohud = true;
  anix.gaming.gamemode = true;
  anix.gaming.vulkanTools = true;
  anix.gaming.launchers = true;

  ## Modern Nix CLI and flakes.
  ## Command: anix enable experimentalNix
  anix.experimentalNix = true;

  ## Default shell for normal users: "bash", "zsh", or "fish".
  ## Command: anix set shell zsh
  anix.shell = "zsh";

  ## System services.
  ## Commands: anix enable bluetooth ; anix disable openssh
  anix.services.bluetooth = true;
  anix.services.printing = true;
  anix.services.flatpak = true;
  anix.services.audio = true;
  anix.services.openssh = false;

  ## Laptop and power helpers. thermald is Intel's laptop-specific thermal
  ## daemon -- it fails to start on non-mobile hardware, and a failed unit
  ## makes every "anix apply"/nixos-rebuild report an error, so it's off
  ## by default; enable it only if this is a laptop.
  ## Commands: anix enable thermald ; anix enable tlp
  anix.power.thermald = false;
  anix.power.tlp = false;

  ## Extra packages and fonts.
  ## Commands: anix package add vim ; anix package remove vim
  anix.packages = with pkgs; [ ];
  anix.fonts = with pkgs; [ inter nerd-fonts.jetbrains-mono ];

  ## Trusted Nix users and scheduled cleanup.
  ## Commands: anix enable garbageCollect ; anix set gc.days 14d
  anix.trustedUsers = [ "root" "@wheel" ];
  anix.garbageCollect.enable = true;
  anix.garbageCollect.dates = "weekly";
  anix.garbageCollect.options = "--delete-older-than 14d";
}
EOF
}

# Creates anix.nix from render_template() on first use; on an existing file,
# repairs it instead of touching user content (see repair_anix_module_args).
ensure_anix_file() {
    if [[ -f "$anix_file" ]]; then
        repair_anix_module_args
        return 0
    fi

    run_as_root mkdir -p "$config_dir"
    run_as_root bash -c "$(printf 'cat > %q <<'"'"'EOF'"'"'\n%s\nEOF' "$anix_file" "$(render_template)")"
}

# Older anix.nix files were rendered with a bare `{ ... }:` module header
# (or a user may have hand-edited it to something like `{ lib, ... }:`),
# which breaks the moment the body references `pkgs` (as `anix.packages`/
# `anix.fonts` do). This adds `pkgs, ` to whatever single-line arg header is
# there, on an already-existing user file, without touching anything else
# they've edited (existing bound names like `lib` are preserved).
repair_anix_module_args() {
    [[ -f "$anix_file" ]] || return 0
    grep -Eq 'with[[:space:]]+pkgs[[:space:]]*;' "$anix_file" || return 0
    local header
    header="$(grep -m1 -E '^[[:space:]]*\{[^{}]*\}:[[:space:]]*$' "$anix_file")"
    [[ -n "$header" ]] || return 0
    printf '%s' "$header" | grep -Eq '(^|[^A-Za-z0-9_])pkgs([^A-Za-z0-9_]|$)' && return 0
    run_as_root sed -i -E '0,/^([[:space:]]*)\{([[:space:]]*)/s//\1{ pkgs, /' "$anix_file"
}

# All values here are read back out with sed rather than a real Nix parser
# (anix.nix is a fixed template, not arbitrary Nix — see read_anix_option),
# so this only ever displays what ANIX itself wrote.
show_config() {
    if [[ ! -f "$anix_file" ]]; then
        abora_banner "ANIX" "No ANIX config exists yet."
        abora_dim_line "Run 'anix init' to create ${anix_file}."
        printf '\n'
        return 0
    fi

    local hostname timezone kb_console kb_xkb desktop wallpaper
    local allow_unfree bluetooth flatpak audio openssh gc shell
    local gaming gaming_steam gaming_big_picture gaming_autostart gaming_gamescope gaming_controller gaming_mangohud gaming_gamemode gaming_vulkan gaming_launchers
    hostname="$(read_anix_option "hostname")"
    timezone="$(read_anix_option "timezone")"
    kb_console="$(read_anix_option "keyboard.console")"
    kb_xkb="$(read_anix_option "keyboard.xkb")"
    desktop="$(read_anix_option "desktop")"
    wallpaper="$(read_anix_option "wallpaper")"
    shell="$(read_anix_option "shell")"
    allow_unfree="$(sed -nE 's|^[[:space:]]*anix\.allowUnfree[[:space:]]*=[[:space:]]*([^;]+);.*|\1|p' "$anix_file" | head -n1)"
    bluetooth="$(sed -nE 's|^[[:space:]]*anix\.services\.bluetooth[[:space:]]*=[[:space:]]*([^;]+);.*|\1|p' "$anix_file" | head -n1)"
    flatpak="$(sed -nE 's|^[[:space:]]*anix\.services\.flatpak[[:space:]]*=[[:space:]]*([^;]+);.*|\1|p' "$anix_file" | head -n1)"
    audio="$(sed -nE 's|^[[:space:]]*anix\.services\.audio[[:space:]]*=[[:space:]]*([^;]+);.*|\1|p' "$anix_file" | head -n1)"
    openssh="$(sed -nE 's|^[[:space:]]*anix\.services\.openssh[[:space:]]*=[[:space:]]*([^;]+);.*|\1|p' "$anix_file" | head -n1)"
    gc="$(sed -nE 's|^[[:space:]]*anix\.garbageCollect\.enable[[:space:]]*=[[:space:]]*([^;]+);.*|\1|p' "$anix_file" | head -n1)"
    gaming="$(read_anix_bool_option "gaming.enable")"
    gaming_steam="$(read_anix_bool_option "gaming.steam")"
    gaming_big_picture="$(read_anix_bool_option "gaming.bigPictureShortcut")"
    gaming_autostart="$(read_anix_bool_option "gaming.bigPictureAutostart")"
    gaming_gamescope="$(read_anix_bool_option "gaming.gamescopeSession")"
    gaming_controller="$(read_anix_bool_option "gaming.controllerSupport")"
    gaming_mangohud="$(read_anix_bool_option "gaming.mangohud")"
    gaming_gamemode="$(read_anix_bool_option "gaming.gamemode")"
    gaming_vulkan="$(read_anix_bool_option "gaming.vulkanTools")"
    gaming_launchers="$(read_anix_bool_option "gaming.launchers")"

    abora_banner "ANIX" "${anix_file}"

    abora_card_start "Current Settings"

    abora_kv "hostname"    "${hostname:-—}"
    abora_kv "timezone"    "${timezone:-—}"
    printf '  %b│%b  %b%-18s%b  %b%s%b / %b%s%b\n' \
        "$ABORA_BLUE" "$ABORA_NC" \
        "$ABORA_DIM" "keyboard" "$ABORA_NC" \
        "$ABORA_CYAN" "${kb_console:-—}" "$ABORA_NC" \
        "$ABORA_DIM" "${kb_xkb:-—}" "$ABORA_NC"
    abora_kv "desktop"     "${desktop:-—}"
    abora_kv "wallpaper"   "${wallpaper:-—}"
    abora_kv "shell"       "${shell:-—}"
    abora_kv "allowUnfree" "${allow_unfree:-—}"
    abora_kv "gaming"      "${gaming:-—}"
    abora_kv "steam"       "${gaming_steam:-—}"
    abora_kv "big picture" "${gaming_big_picture:-—}"
    abora_kv "gamescope"   "${gaming_gamescope:-—}"
    abora_kv "controllers" "${gaming_controller:-—}"
    abora_kv "MangoHud"    "${gaming_mangohud:-—}"
    abora_kv "GameMode"    "${gaming_gamemode:-—}"
    abora_kv "vulkan tools" "${gaming_vulkan:-—}"
    abora_kv "launchers"   "${gaming_launchers:-—}"
    abora_kv "gaming autostart" "${gaming_autostart:-—}"

    abora_card_end

    abora_card_start "Services"
    abora_kv "Bluetooth"   "${bluetooth:-—}"
    abora_kv "Flatpak"     "${flatpak:-—}"
    abora_kv "Audio"       "${audio:-—}"
    abora_kv "OpenSSH"     "${openssh:-—}"
    abora_kv "GC"          "${gc:-—}"
    abora_card_end

    printf '\n'
    abora_dim_line "Run 'anix set <key> <value>' to change a setting."
    abora_dim_line "Run 'anix apply' to rebuild with the ANIX layer."
    printf '\n'
}

do_init() {
    if [[ -f "$anix_file" ]]; then
        abora_warn "ANIX config already exists at ${anix_file}."
        abora_dim_line "Use 'anix show' or edit the file directly."
        printf '\n'
        return 0
    fi

    run_as_root mkdir -p "$config_dir"
    run_as_root bash -c "$(printf 'cat > %q <<'"'"'EOF'"'"'\n%s\nEOF' "$anix_file" "$(render_template)")"
    abora_success "Created ${anix_file}"
    abora_dim_line "Run 'anix apply' when you are ready."
    printf '\n'
}

do_set() {
    local key="${1:-}"
    local value="${2:-}"
    local escaped_key=""

    if [[ -z "$key" || -z "$value" ]]; then
        abora_error "Usage: anix set <key> <value>"
        printf '\n'
        exit 1
    fi

    # Belt-and-suspenders, matching abora-config.sh's do_set: no settable
    # value may contain characters that could break out of the Nix
    # double-quoted string it gets written into ('"' ends the string; '\'
    # starts an escape; '${' begins Nix antiquotation), no matter which
    # key-specific check below runs. hostname/desktop/wallpaper/shell are
    # already restricted to safe enums or regexes below, but timezone,
    # keyboard.console, keyboard.xkb, gc.days, and gc.dates accept arbitrary
    # text with no further validation -- without this, "anix set timezone
    # 'x\"; services.openssh.enable = true; anix.timezone = \"x'" writes
    # that second statement as real, unquoted Nix source into anix.nix. This
    # is also the path apply-plan/anix run use for every "set" operation, so
    # it's reachable from an external language adapter's Plan
    # JSON output, not just direct interactive use.
    if [[ "$value" == *'"'* || "$value" == *'\'* || "$value" == *'${'* ]]; then
        abora_error "Invalid value '${value}' — it cannot contain '\"', '\\', or '\${'."
        exit 1
    fi

    ensure_anix_file
    abora_abt_pending "anix config changes" "$config_dir" run_as_root

    case "$key" in
        hostname)
            if [[ ! "$value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
                abora_error "Invalid hostname '${value}'."
                exit 1
            fi
            ;;
        timezone) ;;
        keyboard|keyboard.console)
            key="keyboard.console"
            ;;
        keyboard.xkb) ;;
        desktop)
            validate_desktop "$value"
            ;;
        wallpaper)
            validate_wallpaper "$value"
            ;;
        shell)
            case "$value" in bash|zsh|fish) ;; *) abora_error "Shell must be bash, zsh, or fish."; exit 1 ;; esac
            ;;
        gc.days)
            key="garbageCollect.options"
            value="--delete-older-than ${value}"
            ;;
        garbageCollect.dates|gc.dates)
            key="garbageCollect.dates"
            ;;
        *)
            abora_error "Unknown key: ${key}"
            printf '  %bSettable keys:%b hostname timezone keyboard keyboard.xkb desktop wallpaper shell gc.days gc.dates\n\n' "$ABORA_DIM" "$ABORA_NC"
            exit 1
            ;;
    esac

    if [[ "$key" == "desktop" ]]; then
        local current=""
        current="$(current_configured_desktop)"
        if [[ "$current" != "unknown" && "$current" != "$value" ]]; then
            abora_warn "Desktop change: ${current} -> ${value}"
            abora_dim_line "This can download a large desktop stack and boot into ${value} after apply."
            if ! confirm "Keep this desktop change?" "no"; then
                abora_warn "Desktop change cancelled."
                printf '\n'
                return 0
            fi
        fi
    fi

    escaped_key="${key//./\\.}"
    if grep -Eq "^[[:space:]]*anix\\.${escaped_key}[[:space:]]*=" "$anix_file"; then
        # @ instead of | as the delimiter: timezone/keyboard.xkb/gc.days/
        # gc.dates have no character restriction beyond the "|\${ ban
        # above, so a value containing a literal | would otherwise collide
        # with | used as the sed delimiter (same class of bug as do_package
        # remove's sed, fixed earlier).
        run_as_root sed -i -E \
            "s@^([[:space:]]*anix\\.${escaped_key}[[:space:]]*=[[:space:]]*)\"[^\"]*\";@\\1\"${value}\";@" \
            "$anix_file"
    else
        run_as_root sed -i -E \
            "/^[[:space:]]*}$/i\\  anix.${key} = \"${value}\";" \
            "$anix_file"
    fi

    abora_success "'anix.${key}' set to '${value}'"
    abora_dim_line "Run 'anix apply' to rebuild with the ANIX layer."
    printf '\n'
}

# Single source of truth for feature name -> anix.nix key, shared by
# do_toggle (writes), parse_and_validate_plan (allowlist), and do_diff_plan
# (reads current state) so the three can never drift out of sync with each
# other. Prints the key on success; returns non-zero and prints nothing on
# an unknown feature.
feature_to_anix_key() {
    local name="$1"
    case "$name" in
        allowUnfree|unfree) printf 'allowUnfree' ;;
        experimentalNix|flakes) printf 'experimentalNix' ;;
        bluetooth) printf 'services.bluetooth' ;;
        printing|printers) printf 'services.printing' ;;
        flatpak) printf 'services.flatpak' ;;
        audio|sound) printf 'services.audio' ;;
        openssh|ssh) printf 'services.openssh' ;;
        thermald) printf 'power.thermald' ;;
        tlp) printf 'power.tlp' ;;
        gaming) printf 'gaming.enable' ;;
        gaming.steam|steam) printf 'gaming.steam' ;;
        gaming.big-picture|gaming.bigPictureShortcut|bigPicture|big-picture) printf 'gaming.bigPictureShortcut' ;;
        gaming.autostart|gaming.bigPictureAutostart) printf 'gaming.bigPictureAutostart' ;;
        gaming.gamescope|gaming.gamescopeSession|gamescope) printf 'gaming.gamescopeSession' ;;
        gaming.controllers|gaming.controller|gaming.controllerSupport|controllers|controller) printf 'gaming.controllerSupport' ;;
        gaming.mangohud|mangohud) printf 'gaming.mangohud' ;;
        gaming.gamemode|gamemode) printf 'gaming.gamemode' ;;
        gaming.vulkan|gaming.vulkanTools|vulkan|vulkanTools) printf 'gaming.vulkanTools' ;;
        gaming.launchers|launchers) printf 'gaming.launchers' ;;
        garbageCollect|gc) printf 'garbageCollect.enable' ;;
        *) return 1 ;;
    esac
}

# Reads a boolean anix.<key> value (unquoted true/false, as written by
# write_anix_raw_option) — the boolean counterpart to read_anix_option,
# which only matches quoted string values.
read_anix_bool_option() {
    local key="$1"
    local escaped_key="${key//./\\.}"
    [[ -f "$anix_file" ]] || return 0
    sed -nE "s@^[[:space:]]*anix\\.${escaped_key}[[:space:]]*=[[:space:]]*(true|false);.*@\1@p" "$anix_file" | head -n1
}

write_anix_gaming_dependencies() {
    local wanted="$1"
    local key="$2"

    if [[ "$wanted" == "true" ]]; then
        case "$key" in
            gaming.steam)
                write_anix_raw_option "gaming.enable" "true"
                write_anix_raw_option "gaming.controllerSupport" "true"
                ;;
            gaming.bigPictureShortcut)
                write_anix_raw_option "gaming.enable" "true"
                write_anix_raw_option "gaming.steam" "true"
                ;;
            gaming.bigPictureAutostart)
                write_anix_raw_option "gaming.enable" "true"
                write_anix_raw_option "gaming.steam" "true"
                write_anix_raw_option "gaming.bigPictureShortcut" "true"
                ;;
            gaming.gamescopeSession)
                write_anix_raw_option "gaming.enable" "true"
                write_anix_raw_option "gaming.steam" "true"
                ;;
            gaming.controllerSupport|gaming.mangohud|gaming.gamemode|gaming.vulkanTools|gaming.launchers)
                write_anix_raw_option "gaming.enable" "true"
                ;;
        esac
    else
        case "$key" in
            gaming.steam)
                write_anix_raw_option "gaming.bigPictureShortcut" "false"
                write_anix_raw_option "gaming.bigPictureAutostart" "false"
                write_anix_raw_option "gaming.gamescopeSession" "false"
                write_anix_raw_option "gaming.controllerSupport" "false"
                ;;
        esac
    fi
}

anix_gaming_dependency_keys() {
    local wanted="$1"
    local key="$2"

    if [[ "$wanted" == "true" ]]; then
        case "$key" in
            gaming.steam)
                printf '%s\n' gaming.enable gaming.controllerSupport
                ;;
            gaming.bigPictureShortcut)
                printf '%s\n' gaming.enable gaming.steam
                ;;
            gaming.bigPictureAutostart)
                printf '%s\n' gaming.enable gaming.steam gaming.bigPictureShortcut
                ;;
            gaming.gamescopeSession)
                printf '%s\n' gaming.enable gaming.steam
                ;;
            gaming.controllerSupport|gaming.mangohud|gaming.gamemode|gaming.vulkanTools|gaming.launchers)
                printf '%s\n' gaming.enable
                ;;
        esac
    else
        case "$key" in
            gaming.steam)
                printf '%s\n' gaming.bigPictureShortcut gaming.bigPictureAutostart gaming.gamescopeSession gaming.controllerSupport
                ;;
        esac
    fi
}

do_toggle() {
    local wanted="$1"
    local name="${2:-}"
    local key=""

    if [[ -z "$name" ]]; then
        abora_error "Usage: anix enable <feature> OR anix disable <feature>"
        exit 1
    fi

    if ! key="$(feature_to_anix_key "$name")"; then
        abora_error "Unknown feature: ${name}"
        abora_dim_line "Known: allowUnfree experimentalNix bluetooth printing flatpak audio openssh thermald tlp gaming gaming.steam gaming.big-picture gaming.autostart gaming.gamescope gaming.controllers gaming.mangohud gaming.gamemode gaming.vulkan gaming.launchers garbageCollect"
        exit 1
    fi

    write_anix_gaming_dependencies "$wanted" "$key"
    write_anix_raw_option "$key" "$wanted"
    abora_success "'anix.${key}' set to '${wanted}'"
    abora_dim_line "Run 'anix apply' to rebuild."
    printf '\n'
}

package_usage() {
    cat <<'USAGE'
Usage:
  anix package add <pkg>          declare it in anix.nix (arrives with anix apply)
  anix package remove <pkg>       take it out of anix.nix
  anix package install <pkg>...   install it now, no config edit or rebuild
                                  (also github:owner/repo for a program that lives in a GitHub flake)
  anix package uninstall <pkg>... remove a package installed that way
  anix package list               show declared and installed packages
  anix package search <word>...   search the system's nixpkgs
  anix package upgrade [<pkg>...] upgrade installed packages (all by default)
  anix package try <pkg> [-- cmd] open a shell with it, install nothing
  anix package keep <pkg>         move an installed package into anix.nix
USAGE
}

do_package() {
    local action="${1:-}"
    local pkg="${2:-}"
    local file=""

    case "$action" in
        install|get) shift; do_package_install "$@"; return ;;
        uninstall) shift; do_package_uninstall "$@"; return ;;
        list|ls|"") shift || true; do_package_list "$@"; return ;;
        search|find) shift; do_package_search "$@"; return ;;
        upgrade|update) shift; do_package_upgrade "$@"; return ;;
        try|shell) shift; do_package_try "$@"; return ;;
        keep) shift; do_package_keep "$@"; return ;;
        help|--help|-h) package_usage; return ;;
    esac

    if [[ -z "$pkg" ]]; then
        package_usage >&2
        exit 1
    fi
    if [[ ! "$pkg" =~ ^[A-Za-z0-9._+-]+$ ]]; then
        abora_error "Invalid package name: ${pkg}"
        exit 1
    fi

    ensure_anix_file
    abora_abt_pending "anix config changes" "$config_dir" run_as_root
    file="$anix_file"
    case "$action" in
        add)
            # (^|[[:space:]]) is not a real word-boundary check: ^ anchors to
            # the start of the whole line, not to right after "[", so a
            # package sitting immediately against "[" with no space would
            # slip past this duplicate check and get appended again. Not
            # reachable through this tool's own writes today (every write
            # path already inserts a leading space), but this is the correct
            # general form regardless: an optional run of non-"]" characters
            # ending in whitespace before the name, so the name can sit right
            # after "[" or after any other package.
            if grep -Eq "anix\\.packages = with pkgs; \\[([^]]*[[:space:]])?${pkg}([[:space:]]|\\])" "$file"; then
                # abora_success below used to run unconditionally after this
                # if/elif/else, so this branch printed both "already in
                # anix.packages" and a false "Added package" success message
                # for a no-op. Return here instead so only the warning shows.
                abora_warn "${pkg} is already in anix.packages"
                abora_dim_line "Run 'anix apply' to rebuild."
                printf '\n'
                return 0
            elif grep -Eq "^[[:space:]]*anix\\.packages[[:space:]]*=[[:space:]]*with pkgs; \\[" "$file"; then
                run_as_root sed -i -E "s|^([[:space:]]*anix\\.packages[[:space:]]*=[[:space:]]*with pkgs; \\[)(.*)(\\];)|\\1\\2 ${pkg} \\3|" "$file"
            else
                write_anix_raw_option "packages" "with pkgs; [ ${pkg} ]"
            fi
            abora_success "Added package: ${pkg}"
            ;;
        remove|rm)
            # Was using | as both the sed delimiter and the regex alternation
            # operator inside the pattern ([[:space:]]|\]) -- sed has no way
            # to tell those apart, so this always failed with "unknown
            # option to 's'" and the exit status was never checked, meaning
            # every "anix package remove" silently did nothing while still
            # printing success. @ doesn't appear in package names (validated
            # above against ^[A-Za-z0-9._+-]+$) or the rest of the pattern,
            # so it's a safe delimiter here.
            if ! run_as_root sed -i -E "s@([[:space:][])${pkg}([[:space:]]|\])@\1\2@g; s@[[:space:]]+\]@ \]@g" "$file"; then
                abora_error "Failed to remove package: ${pkg}"
                exit 1
            fi
            abora_success "Removed package if present: ${pkg}"
            ;;
        *)
            package_usage >&2
            exit 1
            ;;
    esac
    abora_dim_line "Run 'anix apply' to rebuild."
    printf '\n'
}

do_service() {
    local action="${1:-status}"
    local service="${2:-}"

    if [[ -z "$service" ]]; then
        abora_error "Usage: anix service <start|stop|restart|status|enable|disable> <unit>"
        exit 1
    fi

    case "$action" in
        start|stop|restart|status)
            run_as_root systemctl "$action" "$service"
            ;;
        enable|disable)
            run_as_root systemctl "$action" --now "$service"
            ;;
        *)
            abora_error "Unknown service action: ${action}"
            exit 1
            ;;
    esac
}

# Sanity-checks anix.nix before every apply, catching mistakes a raw
# nixos-rebuild would otherwise reject deep in a Nix eval trace: a stray
# top-level `abora =` (should be per-key `abora.desktop = ...`), a missing
# trailing semicolon, or an unknown/changed desktop name. Also re-confirms
# with the user when the desktop in anix.nix differs from what's actually
# installed, since applying downloads a whole new DE stack.
preflight_anix_config() {
    local prompt_desktop="${1:-yes}"
    local failures=0
    local bad_line=""
    local desktop=""
    local current=""

    [[ -f "$anix_file" ]] || return 0

    bad_line="$(grep -nE '^[[:space:]]*abora[[:space:]]*=' "$anix_file" | head -1 || true)"
    if [[ -n "$bad_line" ]]; then
        abora_error "ANIX config has a top-level 'abora =' assignment."
        abora_dim_line "Line ${bad_line%%:*}: use 'abora.desktop = \"gnome\";' or ANIX options instead."
        failures=$((failures + 1))
    fi

    if grep -nE '^[[:space:]]*anix\.[A-Za-z0-9_.-]+[[:space:]]*=[[:space:]]*"[^"]*"[[:space:]]*$' "$anix_file" >/dev/null; then
        abora_warn "Some ANIX lines may be missing a semicolon."
        grep -nE '^[[:space:]]*anix\.[A-Za-z0-9_.-]+[[:space:]]*=[[:space:]]*"[^"]*"[[:space:]]*$' "$anix_file" | head -4 | sed 's/^/    /'
        failures=$((failures + 1))
    fi

    desktop="$(read_anix_option "desktop")"
    if [[ -n "$desktop" ]]; then
        local valid=""
        local known="false"
        for valid in "${valid_desktops[@]}"; do
            [[ "$desktop" == "$valid" ]] && known="true"
        done
        if [[ "$known" != "true" ]]; then
            abora_error "Invalid desktop in ANIX config: ${desktop}"
            abora_dim_line "Valid desktops: ${valid_desktops[*]}"
            failures=$((failures + 1))
        fi
        current="$(read_abora_option "desktop")"
        if [[ -n "$current" && "$current" != "$desktop" ]]; then
            abora_warn "ANIX desktop differs from installed Abora desktop: ${current} -> ${desktop}"
            abora_dim_line "This can download a large DE and make ${desktop} the next desktop."
            if [[ "$prompt_desktop" != "yes" ]]; then
                return 1
            fi
            if ! confirm "Apply this desktop change?" "no"; then
                abora_warn "Apply cancelled."
                printf '\n'
                return 1
            fi
        fi
    fi

    [[ "$failures" -eq 0 ]]
}

do_apply() {
    ensure_anix_file
    repair_anix_module_args

    abora_banner "ANIX Apply" "Rebuilding with ${anix_file}"
    if ! preflight_anix_config yes; then
        abora_error "Fix the ANIX config before applying."
        printf '\n'
        exit 1
    fi
    abora_step "Running nixos-rebuild switch"
    printf '\n'

    stage_config_for_flake
    abora_abt_prefix "anix apply" "$config_dir"
    run_as_root "${ABORA_ABT_PREFIX[@]}" nixos-rebuild switch --flake "${config_dir}#${flake_config_name}"

    printf '\n'
    abora_success "Done. The ANIX layer is now active."
    printf '\n'
}

do_version() {
    abora_banner "ANIX v${anix_version}" "Abora/NixOS profile manager."
    abora_card_start "Runtime"
    abora_kv "config_dir" "$config_dir"
    abora_kv "config" "$anix_file"
    abora_kv "flake_config" "$flake_config_name"
    abora_kv "git_branch" "$(git_branch_name)"
    abora_kv "snapshots" "$(git_snapshot_count)"
    abora_card_end
    printf '\n'
}

do_status() {
    local dirty="no"
    local flake="missing"
    local generation="unknown"

    config_is_dirty && dirty="yes"
    [[ -f "$config_dir/flake.nix" ]] && flake="present"
    if [[ -e "$current_system_link" ]]; then
        generation="$(readlink "$current_system_link" 2>/dev/null || printf 'active')"
    fi

    abora_banner "ANIX Status" "What ANIX sees right now."
    abora_card_start "System"
    abora_kv "version" "$anix_version"
    abora_kv "config_dir" "$config_dir"
    abora_kv "anix_config" "$([[ -f "$anix_file" ]] && printf present || printf missing)"
    abora_kv "flake" "$flake"
    abora_kv "default_profile" "$flake_config_name"
    abora_kv "generation" "$generation"
    abora_card_end

    abora_card_start "Snapshots"
    abora_kv "git_repo" "$(config_is_git_repo && printf yes || printf no)"
    abora_kv "branch" "$(git_branch_name)"
    abora_kv "dirty" "$dirty"
    abora_kv "commits" "$(git_snapshot_count)"
    abora_kv "push" "$(anix_config_get "snapshots.push" "false")"
    abora_card_end

    abora_card_start "Packages"
    abora_kv "declared" "$(declared_packages | wc -w | tr -d ' ') in anix.packages"
    abora_kv "installed" "$(profile_package_names 2>/dev/null | wc -l | tr -d ' ') with anix package install"
    abora_card_end
    printf '\n'
}

# ANIX packages (4.2 Solstice, replacing TinyPM). Two ways to get a program:
#
#   declared   `anix package add/remove` edits anix.packages in anix.nix; it
#              arrives with the next `anix apply` and is part of every
#              generation, so a rollback takes it away again.
#   installed  `anix package install/uninstall` puts it in the user's own Nix
#              profile right away: no anix.nix or flake.nix edit and no
#              rebuild. `anix package keep` turns one into a declared package.
#
# Installs resolve `nixpkgs` through --inputs-from the system flake, so they
# use the exact nixpkgs revision the system is pinned to (flake.lock) and
# reuse what's already in the store, instead of whatever the registry's
# nixpkgs-unstable happens to be today. TinyPM wrapped Flatpak, Snap and Nix
# behind one command; Flatpak stays `abora apps`, and this is the Nix part.
nix_bin="${ANIX_NIX_BIN:-nix}"

validate_package_name() {
    local pkg="$1"
    # Attribute paths like python3Packages.requests are fine; a leading '-'
    # would be read by nix as an option, and '..' is never a real attribute.
    if [[ ! "$pkg" =~ ^[A-Za-z0-9_+][A-Za-z0-9._+-]*$ || "$pkg" == *..* ]]; then
        abora_error "Invalid package name: ${pkg}"
        exit 1
    fi
}

# A program that lives in a GitHub (or GitLab/SourceHut/git) flake instead of nixpkgs:
# `anix package install github:owner/repo` or `github:owner/repo#attribute`. Only these schemes, and
# only characters a flake ref needs, so a name can never be read by nix as an option or by the shell.
# This is how software outside nixpkgs (Modularity, since 4.2) installs; the flake is fetched and
# built by nix like any other, and what it builds is the author's code, so install only flakes
# you trust.
is_flake_ref() {
    [[ "$1" =~ ^(github|gitlab|sourcehut|git\+https|git\+ssh):[A-Za-z0-9._/+@:#?=\&~-]+$ && "$1" != *..* ]]
}

# The name `nix profile` will list it under: the repository, or the #attribute when there is one.
flake_ref_name() {
    local ref="$1" name=""
    if [[ "$ref" == *"#"* ]]; then
        name="${ref##*#}"
    else
        ref="${ref%%\?*}"
        case "$ref" in
            github:*|gitlab:*|sourcehut:*) name="$(cut -d/ -f2 <<<"${ref#*:}")" ;;
            *) name="${ref##*/}"; name="${name%.git}" ;;
        esac
    fi
    printf '%s' "${name:-$1}"
}

declared_packages() {
    [[ -f "$anix_file" ]] || return 0
    sed -nE 's|^[[:space:]]*anix\.packages[[:space:]]*=[[:space:]]*with pkgs; \[(.*)\];.*|\1|p' "$anix_file" \
        | head -n1 | tr -s '[:space:]' '\n' | sed '/^$/d'
}

# Fills the global nixpkgs_args with the flags that pin `nixpkgs` to the
# system's own lock. Without a flake.lock (plain NixOS, or before the first
# rebuild) nix falls back to the registry's nixpkgs, which NixOS also points
# at the system's nixpkgs on flake-based installs.
nixpkgs_args=()
resolve_nixpkgs_args() {
    nixpkgs_args=()
    if [[ -f "$config_dir/flake.lock" ]]; then
        nixpkgs_args=(--inputs-from "$config_dir")
    fi
    # Same rule as the system config: if anix.allowUnfree is on, a one-off
    # install of an unfree package should work too. nix only reads
    # NIXPKGS_ALLOW_UNFREE in impure mode.
    if [[ "$(read_anix_bool_option allowUnfree)" == "true" ]]; then
        export NIXPKGS_ALLOW_UNFREE=1
        nixpkgs_args+=(--impure)
    fi
}

# `nix profile install` was renamed `add` in Nix 2.26; older Nix (the 26.05
# default is newer, but a standalone ANIX may sit on anything) only knows
# install, and newer Nix still accepts install as an alias.
nix_profile_add_verb() {
    if "$nix_bin" profile add --help >/dev/null 2>&1; then
        printf 'add'
    else
        printf 'install'
    fi
}

# Names of the packages in the user's profile, one per line. `nix profile
# list --json` keys elements by name since Nix 2.20 (an object); older Nix
# returns a list without names, so fall back to the attribute path's last part.
profile_package_names() {
    local json=""
    json="$("$nix_bin" profile list --json 2>/dev/null)" || return 1
    [[ -n "$json" ]] || return 0
    jq -r '
        .elements
        | if type == "object" then keys[]
          else .[] | (.attrPath // "") | split(".") | last
          end' <<<"$json" 2>/dev/null | sed '/^$/d'
}

package_in_profile() {
    profile_package_names 2>/dev/null | grep -Fxq -- "$1"
}

# Runs nix with its progress still on screen, keeping a copy of stderr so a
# failure can be explained in a sentence instead of a Nix trace.
run_nix_package_command() {
    local log_file="" rc=0
    log_file="$(mktemp "${TMPDIR:-/tmp}/anix-package.XXXXXX")"
    "$nix_bin" "$@" 2> >(tee "$log_file" >&2) || rc=$?
    # Let tee finish writing before the log is read or removed. Bash doesn't
    # always set $! for a process substitution used in a redirection.
    if [[ -n "${!:-}" ]]; then
        wait "$!" 2>/dev/null || true
    fi
    if [[ "$rc" -eq 0 ]]; then
        rm -f "$log_file"
        return 0
    fi
    printf '\n'
    if grep -qi "unfree" "$log_file"; then
        abora_error "That package is unfree and anix.allowUnfree is off."
        abora_dim_line "Run 'anix enable allowUnfree', then 'anix apply', and try again."
    elif grep -qE "does not provide attribute|flake '.*' does not provide" "$log_file"; then
        abora_error "nixpkgs has no package by that name."
        abora_dim_line "Search for it: anix package search <word>"
    elif grep -qiE "unable to download|Could not resolve host|Connection timed out" "$log_file"; then
        abora_error "Nix couldn't download the package. Check the network: abora network"
    else
        abora_error "Nix failed. Last lines:"
        tail -n 8 "$log_file" | sed 's/^/    /'
    fi
    rm -f "$log_file"
    return 1
}

do_package_install() {
    local pkg="" verb=""
    [[ $# -gt 0 ]] || { abora_error "Usage: anix package install <pkg>..."; exit 1; }
    require_command "$nix_bin"
    resolve_nixpkgs_args
    verb="$(nix_profile_add_verb)"
    local installable="" name=""
    for pkg in "$@"; do
        if is_flake_ref "$pkg"; then
            installable="$pkg"
            name="$(flake_ref_name "$pkg")"
            abora_step "Installing ${name} from ${pkg}"
            abora_dim_line "This builds the flake's own code. Install flakes you trust."
        else
            validate_package_name "$pkg"
            installable="nixpkgs#${pkg}"
            name="$pkg"
        fi
        if package_in_profile "$name"; then
            abora_warn "${name} is already installed. Update it with: anix package upgrade"
            continue
        fi
        if declared_packages | grep -Fxq -- "$name"; then
            abora_dim_line "${name} is also in anix.packages; installing a second copy for this user."
        fi
        [[ "$installable" == nixpkgs#* ]] && abora_step "Installing ${name} from the system's nixpkgs"
        run_nix_package_command profile "$verb" "${nixpkgs_args[@]}" "$installable" || exit 1
        abora_success "Installed ${name}. It's ready now, no rebuild needed."
    done
    abora_dim_line "Keep it in your system config too: anix package keep <pkg>"
    printf '\n'
}

do_package_uninstall() {
    local pkg=""
    [[ $# -gt 0 ]] || { abora_error "Usage: anix package uninstall <pkg>..."; exit 1; }
    require_command "$nix_bin"
    for pkg in "$@"; do
        validate_package_name "$pkg"
        if ! package_in_profile "$pkg"; then
            if declared_packages | grep -Fxq -- "$pkg"; then
                abora_warn "${pkg} comes from anix.packages, not a one-off install."
                abora_dim_line "Remove it from the config instead: anix package remove ${pkg} && anix apply"
            else
                abora_warn "${pkg} isn't installed."
            fi
            continue
        fi
        run_nix_package_command profile remove "$pkg" || exit 1
        abora_success "Uninstalled ${pkg}."
    done
    printf '\n'
}

do_package_list() {
    local declared="" installed=""
    declared="$(declared_packages)"
    installed="$(profile_package_names 2>/dev/null || true)"

    abora_banner "ANIX Packages" "Declared in anix.nix, and installed without a rebuild."
    abora_card_start "Declared (anix.packages)"
    if [[ -n "$declared" ]]; then
        printf '%s\n' "$declared" | sed 's/^/  /'
    else
        abora_dim_line "none. Add one with: anix package add <pkg>"
    fi
    abora_card_end
    abora_card_start "Installed (anix package install)"
    if [[ -n "$installed" ]]; then
        printf '%s\n' "$installed" | sed 's/^/  /'
    else
        abora_dim_line "none. Try one with: anix package install <pkg>"
    fi
    abora_card_end
    printf '\n'
}

do_package_search() {
    [[ $# -gt 0 ]] || { abora_error "Usage: anix package search <word>..."; exit 1; }
    require_command "$nix_bin"
    resolve_nixpkgs_args
    run_nix_package_command search "${nixpkgs_args[@]}" nixpkgs "$@" || exit 1
}

do_package_upgrade() {
    require_command "$nix_bin"
    resolve_nixpkgs_args
    if [[ $# -eq 0 ]]; then
        run_nix_package_command profile upgrade "${nixpkgs_args[@]}" --all || exit 1
        abora_success "Upgraded every installed package."
    else
        local pkg=""
        for pkg in "$@"; do
            validate_package_name "$pkg"
            run_nix_package_command profile upgrade "${nixpkgs_args[@]}" "$pkg" || exit 1
            abora_success "Upgraded ${pkg}."
        done
    fi
    abora_dim_line "Declared packages update with the system: abora update"
    printf '\n'
}

# A throwaway shell with the package in it; nothing is installed.
do_package_try() {
    local pkg="${1:-}"
    [[ -n "$pkg" ]] || { abora_error "Usage: anix package try <pkg> [-- command...]"; exit 1; }
    shift
    local installable="nixpkgs#${pkg}"
    if is_flake_ref "$pkg"; then
        installable="$pkg"
    else
        validate_package_name "$pkg"
    fi
    require_command "$nix_bin"
    resolve_nixpkgs_args
    [[ "${1:-}" == "--" ]] && shift
    if [[ $# -gt 0 ]]; then
        exec "$nix_bin" shell "${nixpkgs_args[@]}" "$installable" --command "$@"
    fi
    abora_dim_line "Starting a shell with ${pkg}. Type 'exit' to leave; nothing stays installed."
    exec "$nix_bin" shell "${nixpkgs_args[@]}" "$installable"
}

# Moves a one-off install into anix.packages, so it survives a reinstall
# and is part of the system generation. The profile copy stays until the
# next `anix apply` has the declared one in place.
do_package_keep() {
    local pkg="${1:-}"
    [[ -n "$pkg" ]] || { abora_error "Usage: anix package keep <pkg>"; exit 1; }
    validate_package_name "$pkg"
    do_package add "$pkg"
    if package_in_profile "$pkg"; then
        abora_dim_line "After 'anix apply', drop the one-off copy: anix package uninstall ${pkg}"
        printf '\n'
    fi
}

do_docs() {
    abora_banner "ANIX Docs" "Local documentation for ANIX and optional companion tools."
    abora_card_start "Docs"
    abora_kv "ANIX" "$anix_doc_file"
    abora_kv "Packages" "$packages_doc_file"
    abora_kv "Abora tools" "$abora_tools_doc_file"
    abora_kv "Recovery" "$recovery_doc_file"
    abora_card_end
    printf '\n'
    abora_dim_line "Packaged docs can live anywhere; override the paths with ANIX_* env vars."
    printf '\n'
}

# ── Terminal menus (`anix --gui`) ──────────────────────────────────────────────
# The same operations the CLI exposes, grouped into numbered menus. (Until 4.2 there was also a zenity
# dialog version; the config app, `abora config-gui`, is the graphical way now.)

terminal_pick_profile() {
    local profiles profile
    profiles="$(flake_profile_candidates)"
    [[ -n "$profiles" ]] || profiles="$flake_config_name"

    printf '\nAvailable profiles:\n'
    printf '%s\n' "$profiles" | sed 's/^/  /'
    printf 'Profile [%s]: ' "$flake_config_name"
    read -r profile || profile=""
    printf '%s\n' "${profile:-$flake_config_name}"
}

terminal_show_doc() {
    local doc="$1"
    [[ "$doc" == "back" || -z "$doc" ]] && return 0
    if [[ -f "$doc" ]]; then
        printf '\nANIX Docs\n'
        sed -n '1,220p' "$doc"
    else
        abora_warn "This local doc was not found: ${doc}"
    fi
}

terminal_prompt_setting_key() {
    printf '\nSettings\n'
    printf '  1  Show current config\n'
    printf '  2  Hostname\n'
    printf '  3  Timezone\n'
    printf '  4  Console keyboard\n'
    printf '  5  Desktop keyboard\n'
    printf '  6  Desktop\n'
    printf '  7  Wallpaper\n'
    printf '  8  Shell\n'
    printf '  0  Back\n\n'
    printf '  Select: '
}

terminal_prompt_feature_action() {
    printf '\nFeatures\n'
    printf '  1  Allow unfree\n'
    printf '  2  Experimental Nix / flakes\n'
    printf '  3  Bluetooth\n'
    printf '  4  Printing\n'
    printf '  5  Flatpak\n'
    printf '  6  Audio\n'
    printf '  7  OpenSSH\n'
    printf '  8  Thermald\n'
    printf '  9  TLP\n'
    printf '  10 Garbage collect\n'
    printf '  0  Back\n\n'
    printf '  Select: '
}

terminal_prompt_feature_state() {
    printf '  State [on/off]: '
}

terminal_settings_menu() {
    local choice key current value

    while true; do
        abora_banner "ANIX Settings" "Change common ANIX values."
        terminal_prompt_setting_key
        read -r choice || choice="0"
        case "$choice" in
            1) ( show_config ) || true ;;
            2) key="hostname" ;;
            3) key="timezone" ;;
            4) key="keyboard.console" ;;
            5) key="keyboard.xkb" ;;
            6) key="desktop" ;;
            7) key="wallpaper" ;;
            8) key="shell" ;;
            0|"") return 0 ;;
            *) abora_warn "Choose a menu number."; printf '\n'; continue ;;
        esac

        if [[ "$choice" == "1" ]]; then
            printf '\nPress Enter to return to settings.'
            read -r _ || true
            continue
        fi

        current="$(read_anix_option "$key")"
        [[ -n "$current" ]] || current="$(read_abora_option "$key")"
        printf '  Current [%s]: ' "${current:-unset}"
        read -r value || value=""
        [[ -n "$value" ]] || continue
        # do_set exit 1's on invalid input (belt-and-suspenders value
        # checks, invalid hostname/desktop/wallpaper/shell) -- that's
        # correct for direct CLI `anix set`, but here it silently killed
        # this entire interactive menu (and the whole `anix --gui` session)
        # on a plain typo, with no way back to the menu. Reproduced
        # directly: typing a hostname containing a space exited the whole
        # process. A subshell contains do_set's exit to just this call.
        ( do_set "$key" "$value" ) || true
        printf '\nPress Enter to return to settings.'
        read -r _ || true
    done
}

terminal_features_menu() {
    local choice feature wanted state

    while true; do
        abora_banner "ANIX Features" "Toggle ANIX feature flags."
        terminal_prompt_feature_action
        read -r choice || choice="0"
        case "$choice" in
            1) feature="allowUnfree" ;;
            2) feature="experimentalNix" ;;
            3) feature="bluetooth" ;;
            4) feature="printing" ;;
            5) feature="flatpak" ;;
            6) feature="audio" ;;
            7) feature="openssh" ;;
            8) feature="thermald" ;;
            9) feature="tlp" ;;
            10) feature="garbageCollect" ;;
            0|"") return 0 ;;
            *) abora_warn "Choose a menu number."; printf '\n'; continue ;;
        esac

        terminal_prompt_feature_state
        read -r state || state=""
        case "$state" in
            on|enable|enabled|true|yes|y) wanted="true" ;;
            off|disable|disabled|false|no|n) wanted="false" ;;
            *) abora_warn "Type on or off."; printf '\n'; continue ;;
        esac
        # do_toggle can exit on a bad state; see the identical do_set fix
        # in terminal_settings_menu above for why this needs a subshell.
        ( do_toggle "$wanted" "$feature" ) || true
        printf '\nPress Enter to return to features.'
        read -r _ || true
    done
}

terminal_profiles_menu() {
    local choice profile

    while true; do
        abora_banner "ANIX Profiles" "Inspect, build, and switch profiles."
        printf '  1  List profiles\n'
        printf '  2  Show generations\n'
        printf '  3  Diff profile\n'
        printf '  4  Build profile\n'
        printf '  5  Test profile\n'
        printf '  6  Boot profile\n'
        printf '  7  Switch profile\n'
        printf '  8  Rollback previous generation\n'
        printf '  0  Back\n\n'
        printf '  Select: '
        read -r choice || choice="0"
        # Every action below is subshell + `|| true`-guarded: do_switch and
        # do_rollback exit on failure (a real, plausible outcome here --
        # e.g. no previous generation to roll back to), which would
        # otherwise kill this whole interactive menu on `set -e`. See the
        # identical do_set fix in terminal_settings_menu above.
        case "$choice" in
            1) ( do_profiles ) || true ;;
            2) ( do_generations ) || true ;;
            3) profile="$(terminal_pick_profile)"; ( do_diff nix "$profile" ) || true ;;
            4) profile="$(terminal_pick_profile)"; ( do_build_profile nix "$profile" ) || true ;;
            5) profile="$(terminal_pick_profile)"; ( do_test nix "$profile" ) || true ;;
            6) profile="$(terminal_pick_profile)"; ( do_boot nix "$profile" ) || true ;;
            7) profile="$(terminal_pick_profile)"; ( do_switch nix "$profile" ) || true ;;
            8) ( do_rollback ) || true ;;
            0|"") return 0 ;;
            *) abora_warn "Choose a menu number."; printf '\n'; continue ;;
        esac
        printf '\nPress Enter to return to profiles.'
        read -r _ || true
    done
}

terminal_snapshots_menu() {
    local choice message current

    while true; do
        current="$(anix_config_get "snapshots.push" "false")"
        abora_banner "ANIX Snapshots" "Manage local config history."
        printf '  1  Status\n'
        printf '  2  Save snapshot\n'
        printf '  3  Toggle snapshots.push (current: %s)\n' "$current"
        printf '  4  Show ANIX tool config\n'
        printf '  0  Back\n\n'
        printf '  Select: '
        read -r choice || choice="0"
        # Subshell + `|| true`-guarded: do_save/do_tool_config exit on
        # failure, which would otherwise kill this whole interactive menu
        # on `set -e`. See the identical do_set fix in
        # terminal_settings_menu above.
        case "$choice" in
            1) ( do_status ) || true ;;
            2)
                printf '  Message [anix: local config snapshot]: '
                read -r message || message=""
                ( do_save "${message:-anix: local config snapshot}" ) || true
                ;;
            3)
                if is_yes "$current"; then
                    ( do_tool_config set snapshots.push false ) || true
                else
                    ( do_tool_config set snapshots.push true ) || true
                fi
                ;;
            4) ( do_tool_config show ) || true ;;
            0|"") return 0 ;;
            *) abora_warn "Choose a menu number."; printf '\n'; continue ;;
        esac
        printf '\nPress Enter to return to snapshots.'
        read -r _ || true
    done
}

terminal_packages_menu() {
    local choice pkg

    while true; do
        abora_banner "ANIX Packages" "Install packages now, or declare them in anix.nix."
        printf '  1  List packages\n'
        printf '  2  Install a package now (no rebuild)\n'
        printf '  3  Add package to anix.packages\n'
        printf '  4  Remove package from anix.packages\n'
        printf '  5  Uninstall a package installed now\n'
        printf '  0  Back\n\n'
        printf '  Select: '
        read -r choice || choice="0"
        # Subshell + `|| true`-guarded: do_package exits on
        # failure (e.g. an unknown package name -- a very plausible typo
        # here), which would otherwise kill this whole interactive menu on
        # `set -e`. See the identical do_set fix in terminal_settings_menu
        # above.
        case "$choice" in
            1) ( do_package list ) || true ;;
            2)
                printf '  Package to install: '
                read -r pkg || pkg=""
                if [[ -n "$pkg" ]]; then ( do_package install "$pkg" ) || true; fi
                ;;
            3)
                printf '  Package to add: '
                read -r pkg || pkg=""
                if [[ -n "$pkg" ]]; then ( do_package add "$pkg" ) || true; fi
                ;;
            4)
                printf '  Package to remove: '
                read -r pkg || pkg=""
                if [[ -n "$pkg" ]]; then ( do_package remove "$pkg" ) || true; fi
                ;;
            5)
                printf '  Package to uninstall: '
                read -r pkg || pkg=""
                if [[ -n "$pkg" ]]; then ( do_package uninstall "$pkg" ) || true; fi
                ;;
            0|"") return 0 ;;
            *) abora_warn "Choose a menu number."; printf '\n'; continue ;;
        esac
        printf '\nPress Enter to return to packages.'
        read -r _ || true
    done
}

terminal_maintenance_menu() {
    local choice

    while true; do
        abora_banner "ANIX Maintenance" "Prepare, repair, and apply the ANIX layer."
        printf '  1  Quickstart\n'
        printf '  2  Doctor\n'
        printf '  3  Doctor repair\n'
        printf '  4  Apply\n'
        printf '  5  Docs\n'
        printf '  0  Back\n\n'
        printf '  Select: '
        read -r choice || choice="0"
        # Subshell + `|| true`-guarded: do_doctor/do_apply exit on failure
        # -- exactly the outcome a user reaching for "Doctor" or "Apply" on
        # an already-troubled system is likely to hit -- which would
        # otherwise kill this whole interactive menu on `set -e`. See the
        # identical do_set fix in terminal_settings_menu above.
        case "$choice" in
            1) ( do_quickstart ) || true ;;
            2) ( do_doctor ) || true ;;
            3) ( do_doctor --fix ) || true ;;
            4) ( do_apply ) || true ;;
            5) ( do_docs ) || true ;;
            0|"") return 0 ;;
            *) abora_warn "Choose a menu number."; printf '\n'; continue ;;
        esac
        printf '\nPress Enter to return to maintenance.'
        read -r _ || true
    done
}

terminal_docs_menu() {
    local choice

    while true; do
        abora_banner "ANIX Docs" "Open local documentation in terminal mode."
        printf '  1  ANIX guide\n'
        printf '  2  Packages guide\n'
        printf '  3  Abora tools guide\n'
        printf '  4  Recovery guide\n'
        printf '  0  Back\n\n'
        printf '  Select: '
        read -r choice || choice="0"
        case "$choice" in
            1) terminal_show_doc "$anix_doc_file" ;;
            2) terminal_show_doc "$packages_doc_file" ;;
            3) terminal_show_doc "$abora_tools_doc_file" ;;
            4) terminal_show_doc "$recovery_doc_file" ;;
            0|"") return 0 ;;
            *) abora_warn "Choose a menu number."; printf '\n'; continue ;;
        esac
        printf '\nPress Enter to return to docs.'
        read -r _ || true
    done
}

do_gui_terminal() {
    local choice

    while true; do
        abora_banner "ANIX Control Center" "Settings, features, profiles, snapshots, packages and maintenance."
        printf '  1  Overview\n'
        printf '  2  Settings\n'
        printf '  3  Features\n'
        printf '  4  Profiles\n'
        printf '  5  Snapshots\n'
        printf '  6  Packages\n'
        printf '  7  Maintenance\n'
        printf '  8  Docs\n'
        printf '  0  Exit\n\n'
        printf '  Select: '
        read -r choice || choice="0"
        case "$choice" in
            1) do_status; printf '\nPress Enter to return to overview.'; read -r _ || true ;;
            2) terminal_settings_menu ;;
            3) terminal_features_menu ;;
            4) terminal_profiles_menu ;;
            5) terminal_snapshots_menu ;;
            6) terminal_packages_menu ;;
            7) terminal_maintenance_menu ;;
            8) terminal_docs_menu ;;
            0|"") return 0 ;;
            *) abora_warn "Choose a menu number." ;;
        esac
    done
}

do_gui() {
    do_gui_terminal
}

do_quickstart() {
    abora_banner "ANIX Quickstart" "Prepare the friendly NixOS layer."

    ensure_anix_file
    abora_success "ANIX config is present: ${anix_file}"

    if config_is_git_repo; then
        abora_success "Snapshot repo is ready: ${config_dir}"
    else
        abora_warn "Snapshot repo is not initialized."
        if confirm "Initialize local snapshot history now?" "yes"; then
            ensure_config_git_repo
            abora_success "Snapshot repo is ready."
        fi
    fi

    printf '\n'
    do_status
    abora_dim_line "Next: run 'anix diff nix ${flake_config_name}' or 'anix switch nix ${flake_config_name}'."
    printf '\n'
}

do_profiles() {
    local profiles=""

    profiles="$(flake_profile_candidates)"
    abora_banner "ANIX Profiles" "${config_dir}/flake.nix"

    if [[ -z "$profiles" ]]; then
        abora_warn "No flake profiles were discovered."
        abora_dim_line "Expected outputs under nixosConfigurations."
        printf '\n'
        return 0
    fi

    abora_card_start "Available Profiles"
    printf '%s\n' "$profiles" | while IFS= read -r profile; do
        [[ -n "$profile" ]] || continue
        printf '  %b│%b  %b%s%b\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "$profile" "$ABORA_NC"
    done
    abora_card_end
    printf '\n'
}

do_generations() {
    local lines=""

    lines="$(generation_lines)"
    abora_banner "ANIX Generations" "$system_profile_link"
    if [[ -z "$lines" ]]; then
        abora_warn "No system generations were found."
        printf '\n'
        return 0
    fi

    abora_card_start "System Generations"
    printf '%s\n' "$lines" | tail -n "${ANIX_GENERATION_LIMIT:-12}" | while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        printf '  %b│%b  %b%s%b\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "$line" "$ABORA_NC"
    done
    abora_card_end
    printf '\n'
}

# ── ANIX v2: pluggable configuration languages ──────────────────────────────
#
# One engine, several frontends (docs/wiki/ANIX-V2-Languages.md). A frontend
# is either the built-in ANIX Native file form (plain `set`/`enable`/
# `package add` lines, extension .anix) or an installed language adapter — a
# small JSON manifest naming an argv command that turns a source file into
# an ANIX Plan (JSON) on stdout. Only this engine ever mutates anix.nix or
# calls nixos-rebuild; adapters run unprivileged and produce data, not
# actions.

list_language_adapters() {
    local dir=""
    for dir in "$anix_user_language_dir" "$anix_system_language_dir"; do
        [[ -d "$dir" ]] || continue
        local manifest=""
        for manifest in "$dir"/*.json; do
            [[ -f "$manifest" ]] || continue
            printf '%s\n' "$manifest"
        done
    done
}

# Prints the adapter manifest matching a language id, or the extension of a
# source file (last dot-segment, including the dot). Native `.anix` files
# never need a manifest — they're handled directly by run_native_plan_file.
find_language_adapter() {
    local selector="$1"
    local manifest=""
    while IFS= read -r manifest; do
        [[ -n "$manifest" ]] || continue
        local id="" extensions=""
        id="$(jq -r '.id // empty' "$manifest" 2>/dev/null)"
        if [[ "$id" == "$selector" ]]; then
            printf '%s\n' "$manifest"
            return 0
        fi
        extensions="$(jq -r '.extensions // [] | .[]' "$manifest" 2>/dev/null)"
        local ext=""
        while IFS= read -r ext; do
            [[ "$ext" == "$selector" ]] && { printf '%s\n' "$manifest"; return 0; }
        done <<<"$extensions"
    done < <(list_language_adapters)
    return 1
}

adapter_ready() {
    local manifest="$1"
    local first_arg=""
    first_arg="$(jq -r '.command[0] // empty' "$manifest" 2>/dev/null)"
    [[ -n "$first_arg" ]] && command -v "$first_arg" >/dev/null 2>&1
}

# Explains *why* an adapter isn't ready — "anix language list" reports
# readiness honestly per the design doc, which means more than a bare
# ready/not-installed flag once something can fail in more than one way.
adapter_status_reason() {
    local manifest="$1"
    if ! jq -e . >/dev/null 2>&1 < "$manifest"; then
        printf 'manifest is not valid JSON'
        return 0
    fi
    local version=""
    version="$(jq -r '.planVersion // empty' "$manifest" 2>/dev/null)"
    if [[ "$version" != "$anix_plan_version" ]]; then
        printf 'unsupported planVersion (%s)' "${version:-missing}"
        return 0
    fi
    local first_arg=""
    first_arg="$(jq -r '.command[0] // empty' "$manifest" 2>/dev/null)"
    if [[ -z "$first_arg" ]]; then
        printf 'manifest has no command'
        return 0
    fi
    if ! command -v "$first_arg" >/dev/null 2>&1; then
        printf "'%s' not found on PATH" "$first_arg"
        return 0
    fi
    printf 'ready'
}

do_language() {
    local action="${1:-list}"

    case "$action" in
        list)
            require_command jq
            local current=""
            current="$(anix_config_get "language" "anix")"
            abora_banner "ANIX Languages" "Frontends that can produce an ANIX Plan."

            local id_col=10 name_col=12 status_col=10 cmd_col=18
            printf '  %b%-*s  %-*s  %-*s  %-*s  %s%b\n' \
                "$ABORA_DIM" "$id_col" "ID" "$name_col" "NAME" "$status_col" "STATUS" "$cmd_col" "COMMAND" "DETAIL" "$ABORA_NC"

            local default_marker=""
            [[ "$current" == "anix" ]] && default_marker=" (default)"
            printf '  %b%-*s  %-*s  %-*s  %-*s  %s%b\n' \
                "$ABORA_GREEN" "$id_col" "anix" "$name_col" "ANIX Native" "$status_col" "ready" "$cmd_col" "built in" "no adapter needed${default_marker}" "$ABORA_NC"

            local -A seen_ids=()
            local manifest=""
            while IFS= read -r manifest; do
                [[ -n "$manifest" ]] || continue
                local id=""
                # Malformed manifests must be reported, not let a failing jq
                # call kill the whole `list` under set -e — every read below
                # tolerates a parse failure the same way.
                id="$(jq -r '.id // empty' "$manifest" 2>/dev/null || true)"
                [[ -n "$id" ]] || { printf '  %b%-*s  %-*s  %-*s  %-*s  %s%b\n' "$ABORA_RED" "$id_col" "?" "$name_col" "?" "$status_col" "invalid" "$cmd_col" "-" "malformed manifest: ${manifest}" "$ABORA_NC"; continue; }
                [[ -n "${seen_ids[$id]:-}" ]] && continue
                seen_ids[$id]=1

                local name="" command_first=""
                name="$(jq -r '.name // .id // "?"' "$manifest" 2>/dev/null || printf '?')"
                command_first="$(jq -r '.command[0] // "-"' "$manifest" 2>/dev/null || printf -- '-')"
                local reason=""
                reason="$(adapter_status_reason "$manifest")"
                local color="$ABORA_RED"
                local status_word="not ready"
                if [[ "$reason" == "ready" ]]; then
                    color="$ABORA_GREEN"
                    status_word="ready"
                    reason="$manifest"
                fi
                [[ "$id" == "$current" ]] && reason="${reason} (default)"
                printf '  %b%-*s  %-*s  %-*s  %-*s  %s%b\n' \
                    "$color" "$id_col" "$id" "$name_col" "$name" "$status_col" "$status_word" "$cmd_col" "$command_first" "$reason" "$ABORA_NC"
            done < <(list_language_adapters)

            printf '\n'
            [[ "${#seen_ids[@]}" -eq 0 ]] && abora_dim_line "No installed adapters in ${anix_user_language_dir} or ${anix_system_language_dir}."
            abora_dim_line "Run 'anix language use <id>' to change the default for 'anix run'."
            printf '\n'
            ;;
        use)
            local lang="${2:-}"
            [[ -n "$lang" ]] || { abora_error "Usage: anix language use <id>"; exit 1; }
            if [[ "$lang" != "anix" ]] && ! find_language_adapter "$lang" >/dev/null; then
                abora_error "Unknown language: ${lang}"
                abora_dim_line "Run 'anix language list' to see installed adapters."
                exit 1
            fi
            anix_config_set "language" "$lang"
            abora_success "Default language set to '${lang}'."
            printf '\n'
            ;;
        *)
            abora_error "Usage: anix language <list|use> [id]"
            exit 1
            ;;
    esac
}

# Turns a .anix Native file into Plan JSON without touching state — the file
# form of the same `set`/`enable`/`disable`/`package add`/`package remove`
# commands, grouped into one transaction instead of running immediately.
# Building the JSON itself is $plan_tool_bin's job (NativePlanBuilder.cs) --
# same reasoning as parse_and_validate_plan above.
native_plan_from_file() {
    local file="$1"
    require_command "$plan_tool_bin"

    local output="" rc=0
    output="$("$plan_tool_bin" build-native --expected-version "$anix_plan_version" < "$file" 2>&1)" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        abora_error "${file}:${output}"
        exit 1
    fi

    printf '%s\n' "$output"
}

# Resolves a source file to a Plan JSON string, either via the ANIX Native
# parser or by shelling out to an installed adapter's command. Adapters run
# as the invoking user (never run_as_root) and only their stdout is treated
# as the plan; stderr passes through for diagnostics.
plan_from_source_file() {
    local file="$1"
    local language_override="${2:-}"

    [[ -f "$file" ]] || { abora_error "File not found: ${file}"; exit 1; }

    local selector="$language_override"
    if [[ -z "$selector" ]]; then
        case "$file" in
            *.anix) native_plan_from_file "$file"; return 0 ;;
            *.*) selector=".${file##*.}" ;;
            *) abora_error "Cannot infer a language for '${file}' — pass --language."; exit 1 ;;
        esac
    fi
    if [[ "$selector" == "anix" ]]; then
        native_plan_from_file "$file"
        return 0
    fi

    local manifest=""
    if ! manifest="$(find_language_adapter "$selector")"; then
        abora_error "No language adapter found for '${selector}'."
        abora_dim_line "Run 'anix language list' to see installed adapters."
        exit 1
    fi
    if ! adapter_ready "$manifest"; then
        abora_error "Language adapter '${selector}' is installed but its command is not on PATH."
        exit 1
    fi

    local command_json=() plan=""
    mapfile -t command_json < <(jq -r '.command[]' "$manifest")
    [[ "${#command_json[@]}" -gt 0 ]] || { abora_error "Adapter manifest has no command: ${manifest}"; exit 1; }
    plan="$("${command_json[@]}" "$file")" || { abora_error "Language adapter failed: ${selector}"; exit 1; }
    printf '%s' "$plan"
}

# Validates a Plan JSON string against the same allowlists do_set/do_toggle/
# do_package already enforce, so a plan can never do anything an interactive
# ANIX command couldn't. Never writes state; returns non-zero on any
# violation and prints every problem found, not just the first.
# Parses+validates a Plan JSON string via $plan_tool_bin (JSON well-
# formedness, planVersion, operations array/op shapes, the "set" key
# allowlist, package-name syntax -- see PlanParser.cs), plus the one
# business rule that must stay a single source of truth with do_toggle/
# do_diff_plan: enable/disable feature names are resolved through
# feature_to_anix_key. On success, sets $plan_language and populates the
# $plan_ops array (one entry per operation, tab-separated
# "op<TAB>field1<TAB>field2") so callers can iterate the plan without
# re-parsing JSON themselves.
plan_language=""
plan_ops=()
parse_and_validate_plan() {
    local plan="$1"
    require_command "$plan_tool_bin"

    plan_language=""
    plan_ops=()

    local output="" rc=0
    output="$("$plan_tool_bin" parse --expected-version "$anix_plan_version" <<<"$plan" 2>&1)" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
        local line=""
        while IFS= read -r line; do
            [[ -n "$line" ]] && abora_error "$line"
        done <<<"$output"
        return 1
    fi

    local header="${output%%$'\n'*}"
    plan_language="${header#language$'\t'}"

    if [[ "$output" == *$'\n'* ]]; then
        local rest="${output#*$'\n'}"
        [[ -n "$rest" ]] && mapfile -t plan_ops <<<"$rest"
    fi

    local failures=0 i=0 entry op field1 field2
    for entry in "${plan_ops[@]}"; do
        IFS=$'\t' read -r op field1 field2 <<<"$entry"
        if [[ "$op" == "enable" || "$op" == "disable" ]] && ! feature_to_anix_key "$field1" >/dev/null; then
            abora_error "operation ${i}: unknown feature '${field1}'"
            failures=$((failures + 1))
        fi
        i=$((i + 1))
    done

    [[ "$failures" -eq 0 ]]
}

# Applies every operation in a validated plan as one transaction: each op
# reuses the existing do_set/do_toggle/do_package writers (so validation,
# desktop-change confirmation, and file formatting stay identical to running
# those commands by hand), then a single dry-build + confirm + switch closes
# the transaction instead of one apply per setting.
#
# parse_and_validate_plan only checks that each operation's key/op/shape is
# recognized -- it does not (and cannot, without duplicating do_set's own
# logic) check that a "set desktop" value is an actual supported profile, or
# that a hostname passes the hostname regex. Those checks only run inside
# do_set/do_toggle/do_package themselves, which can still fail (and call
# `exit`, not `return`) after earlier operations in the same plan have
# already been written directly to anix.nix. To make this genuinely one
# transaction rather than "apply operations in sequence and hope none of
# them fail": every write goes against a private staged copy (do_set/
# do_toggle/do_package all go through the shared $anix_file variable, so
# retargeting it for the duration of this loop is enough), and the staged
# copy only replaces the real anix.nix with one atomic `mv` if every single
# operation succeeded. Each operation call is wrapped in a subshell so that
# an `exit` inside it (do_set's normal way of reporting an invalid value)
# only ends that subshell, letting this loop see the failure and stop
# instead of the whole anix process dying mid-loop.
apply_plan_json() {
    local plan="$1"
    local skip_confirm="${2:-no}"

    parse_and_validate_plan "$plan" || { abora_error "Refusing to apply an invalid plan."; exit 1; }

    local count="${#plan_ops[@]}"
    if [[ "$count" -eq 0 ]]; then
        abora_warn "Plan has no operations."
        return 0
    fi

    abora_banner "ANIX Plan" "${count} operation(s) from ${plan_language:-unknown}"

    ensure_anix_file
    local real_anix_file="$anix_file"
    local staged_anix_file
    staged_anix_file="$(run_as_root mktemp "${real_anix_file}.plan.XXXXXX")"
    run_as_root cp -f "$real_anix_file" "$staged_anix_file"
    anix_file="$staged_anix_file"

    local i=0 op_rc=0 entry op field1 field2
    for entry in "${plan_ops[@]}"; do
        IFS=$'\t' read -r op field1 field2 <<<"$entry"
        case "$op" in
            set)
                ( do_set "$field1" "$field2" ) || op_rc=$?
                ;;
            enable)
                ( do_toggle true "$field1" ) || op_rc=$?
                ;;
            disable)
                ( do_toggle false "$field1" ) || op_rc=$?
                ;;
            package.add)
                ( do_package add "$field1" ) || op_rc=$?
                ;;
            package.remove)
                ( do_package remove "$field1" ) || op_rc=$?
                ;;
        esac
        [[ "$op_rc" -ne 0 ]] && break
        i=$((i + 1))
    done

    anix_file="$real_anix_file"

    if [[ "$op_rc" -ne 0 ]]; then
        run_as_root rm -f "$staged_anix_file"
        abora_error "Plan operation $((i + 1)) of ${count} failed; no changes were written to ${anix_file}."
        exit "$op_rc"
    fi

    run_as_root mv -f "$staged_anix_file" "$anix_file"

    if [[ "$skip_confirm" != "yes" ]] && ! confirm "Apply this plan with 'nixos-rebuild switch'?" "no"; then
        abora_warn "Plan written to ${anix_file} but not applied — run 'anix apply' when ready."
        printf '\n'
        return 0
    fi

    do_apply
}

do_run() {
    local file="${1:-}"
    local language=""
    local yes="no"
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --language)
                if [[ -z "${2:-}" ]]; then
                    abora_error "Usage: anix run <file> [--language <id>] [--yes]"
                    exit 1
                fi
                language="$2"
                shift 2
                ;;
            --yes|-y) yes="yes"; shift ;;
            *) abora_error "Unknown option: $1"; exit 1 ;;
        esac
    done
    [[ -n "$file" ]] || { abora_error "Usage: anix run <file> [--language <id>] [--yes]"; exit 1; }

    local plan=""
    plan="$(plan_from_source_file "$file" "$language")"
    apply_plan_json "$plan" "$yes"
}

do_validate_plan() {
    local file="${1:-}"
    [[ -n "$file" && -f "$file" ]] || { abora_error "Usage: anix validate-plan <plan.json>"; exit 1; }
    local plan=""
    plan="$(cat "$file")"
    if parse_and_validate_plan "$plan"; then
        abora_success "Plan is valid: ${#plan_ops[@]} operation(s)."
        printf '\n'
    else
        abora_error "Plan is invalid."
        exit 1
    fi
}

do_apply_plan() {
    local file="${1:-}"
    local yes="no"
    [[ "${2:-}" == "--yes" || "${2:-}" == "-y" ]] && yes="yes"
    [[ -n "$file" && -f "$file" ]] || { abora_error "Usage: anix apply-plan <plan.json> [--yes]"; exit 1; }
    apply_plan_json "$(cat "$file")" "$yes"
}

# Compares a plan (from a source file or a Plan JSON file) against the
# current anix.nix state and labels each operation ADD, CHANGE, REMOVE, or
# SAME — read-only, no writes, matching the doc's promised semantics.
do_diff_plan() {
    local file="${1:-}"
    [[ -n "$file" && -f "$file" ]] || { abora_error "Usage: anix diff-plan <file>"; exit 1; }
    require_command jq

    local plan=""
    if jq -e . >/dev/null 2>&1 < "$file"; then
        plan="$(cat "$file")"
    else
        plan="$(plan_from_source_file "$file" "")"
    fi
    parse_and_validate_plan "$plan" || { abora_error "Refusing to diff an invalid plan."; exit 1; }

    abora_banner "ANIX Plan Diff" "${plan_language:-unknown}"

    local entry op field1 field2 label=""
    for entry in "${plan_ops[@]}"; do
        IFS=$'\t' read -r op field1 field2 <<<"$entry"
        case "$op" in
            set)
                local current
                current="$( [[ -f "$anix_file" ]] && read_anix_option "$field1" || true )"
                if [[ -z "$current" ]]; then label="ADD"
                elif [[ "$current" == "$field2" ]]; then label="SAME"
                else label="CHANGE"; fi
                printf '  %-7s set %s = "%s"' "$label" "$field1" "$field2"
                [[ "$label" == "CHANGE" ]] && printf ' (was "%s")' "$current"
                printf '\n'
                ;;
            enable|disable)
                local wanted current_bool anix_key
                wanted="$([[ "$op" == "enable" ]] && printf 'true' || printf 'false')"
                current_bool=""
                if anix_key="$(feature_to_anix_key "$field1")"; then
                    current_bool="$(read_anix_bool_option "$anix_key")"
                fi
                if [[ -z "$current_bool" ]]; then
                    label="$([[ "$wanted" == "true" ]] && printf 'ADD' || printf 'REMOVE')"
                elif [[ "$current_bool" == "$wanted" ]]; then
                    label="SAME"
                else
                    label="CHANGE"
                fi
                printf '  %-7s %s %s\n' "$label" "$op" "$field1"
                local dep_key dep_current dep_label dep_op
                while IFS= read -r dep_key; do
                    [[ -n "$dep_key" ]] || continue
                    [[ "$dep_key" == "$anix_key" ]] && continue
                    dep_current="$(read_anix_bool_option "$dep_key")"
                    if [[ -z "$dep_current" ]]; then
                        dep_label="$([[ "$wanted" == "true" ]] && printf 'ADD' || printf 'REMOVE')"
                    elif [[ "$dep_current" == "$wanted" ]]; then
                        dep_label="SAME"
                    else
                        dep_label="CHANGE"
                    fi
                    [[ "$dep_label" == "SAME" ]] && continue
                    dep_op="$([[ "$wanted" == "true" ]] && printf 'enable' || printf 'disable')"
                    printf '          also %s %s %s\n' "$dep_label" "$dep_op" "$dep_key"
                done < <(anix_gaming_dependency_keys "$wanted" "$anix_key")
                ;;
            package.add)
                if [[ -f "$anix_file" ]] && grep -Eq "anix\\.packages = with pkgs; \\[[^]]*([[:space:][])${field1}([[:space:]]|\\])" "$anix_file"; then
                    label="SAME"
                else
                    label="ADD"
                fi
                printf '  %-7s package %s\n' "$label" "$field1"
                ;;
            package.remove)
                if [[ -f "$anix_file" ]] && grep -Eq "anix\\.packages = with pkgs; \\[[^]]*([[:space:][])${field1}([[:space:]]|\\])" "$anix_file"; then
                    label="REMOVE"
                else
                    label="SAME"
                fi
                printf '  %-7s package %s\n' "$label" "$field1"
                ;;
        esac
    done
    printf '\n'
}

do_diff() {
    local family="${1:-nix}"
    local profile="${2:-$flake_config_name}"
    local target=""

    target="$(profile_target "$family" "$profile")"
    abora_banner "ANIX Diff" "${family}/${profile}"
    run_rebuild dry-build "$target"
    printf '\n'
    show_package_changes "$target"
    printf '\n'
}

do_build_profile() {
    local family="${1:-nix}"
    local profile="${2:-$flake_config_name}"
    local target="${3:-}"

    [[ -n "$target" ]] || target="$(profile_target "$family" "$profile")"
    abora_banner "ANIX Build" "${family}/${profile}"
    run_rebuild build "$target"
    printf '\n'
    abora_success "Build finished for ${profile}."
    printf '\n'
}

do_test() {
    local family="${1:-nix}"
    local profile="${2:-$flake_config_name}"
    local target=""

    target="$(profile_target "$family" "$profile")"
    abora_banner "ANIX Test" "${family}/${profile}"
    maybe_snapshot_dirty_config "anix: snapshot before testing ${profile}"
    run_rebuild test "$target"
    printf '\n'
    abora_success "Test activation finished for ${profile}."
    printf '\n'
}

do_boot() {
    local family="${1:-nix}"
    local profile="${2:-$flake_config_name}"
    local target=""

    target="$(profile_target "$family" "$profile")"
    abora_banner "ANIX Boot" "${family}/${profile}"
    maybe_snapshot_dirty_config "anix: snapshot before boot profile ${profile}"
    run_rebuild boot "$target"
    printf '\n'
    abora_success "Boot profile prepared for ${profile}. Reboot when ready."
    printf '\n'
}

do_edit() {
    local editor="${EDITOR:-${VISUAL:-nano}}"

    ensure_anix_file
    if ! command -v "$editor" >/dev/null 2>&1; then
        abora_error "Editor not found: ${editor}"
        abora_dim_line "Set EDITOR or VISUAL, then run anix edit again."
        printf '\n'
        exit 1
    fi
    "$editor" "$anix_file"
}

do_gc() {
    local mode="${1:-old}"

    require_command nix-collect-garbage
    case "$mode" in
        old)
            if ! confirm "Delete old Nix generations and garbage collect?" "no"; then
                abora_warn "Garbage collection cancelled."
                printf '\n'
                return 0
            fi
            run_as_root nix-collect-garbage -d
            ;;
        user)
            nix-collect-garbage
            ;;
        *)
            abora_error "Usage: anix gc [old|user]"
            exit 1
            ;;
    esac

    printf '\n'
    abora_success "Garbage collection complete."
    printf '\n'
}

do_switch() {
    local family="${1:-}"
    local profile="${2:-}"
    local now="false"
    local target=""

    # Shift off only the positionals that were actually present (family,
    # then profile) rather than an unconditional `shift 2` — with a single
    # arg (e.g. `anix switch nix`), `shift 2` fails and shifts nothing,
    # leaving "nix" for the flag loop below to reject as an unknown option
    # instead of reaching the usage message. Mirrors do_rollback's pattern.
    shift 1 2>/dev/null || true
    if [[ -n "$profile" ]]; then
        shift 1 2>/dev/null || true
    fi
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --now) now="true" ;;
            *)
                abora_error "Unknown switch option: $1"
                exit 1
                ;;
        esac
        shift
    done

    if [[ -z "$family" || -z "$profile" ]]; then
        abora_error "Usage: anix switch nix <profile> [--now]"
        printf '\n'
        exit 1
    fi

    target="$(profile_target "$family" "$profile")"
    abora_banner "ANIX Switch" "${family}/${profile}"

    maybe_snapshot_dirty_config "anix: snapshot before switching to ${profile}"

    if [[ "$now" != "true" ]]; then
        abora_step "Checking ${target}"
        run_rebuild dry-build "$target"
        printf '\n'
        if ! confirm "Switch to ${profile} now?" "yes"; then
            abora_warn "Switch cancelled."
            printf '\n'
            return 0
        fi
    fi

    abora_step "Switching to ${target}"
    run_rebuild switch "$target"
    printf '\n'
    abora_success "Now running profile: ${profile}"
    printf '\n'
}

# Argument shape is intentionally forgiving: `anix rollback` (bare),
# `anix rollback --now`, `anix rollback nix myprofile`, and
# `anix rollback nix myprofile --now` must all work, so family/profile are
# read positionally only when they don't look like a `--flag` first.
do_rollback() {
    local family="${1:-nix}"
    local profile=""
    local now="false"
    local target=""

    if [[ "$family" == "--now" ]]; then
        family="nix"
        now="true"
        shift
    else
        shift 1 2>/dev/null || true
    fi

    if [[ "${1:-}" != --* ]]; then
        profile="${1:-}"
    fi

    if [[ -n "$profile" ]]; then
        shift 1 2>/dev/null || true
    fi

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --now) now="true" ;;
            *)
                abora_error "Unknown rollback option: $1"
                exit 1
                ;;
        esac
        shift
    done

    if [[ "$family" != "nix" ]]; then
        abora_error "Unknown rollback family: ${family}"
        abora_dim_line "Use: anix rollback nix [profile] [--now]"
        printf '\n'
        exit 1
    fi

    if [[ -z "$profile" ]]; then
        abora_banner "ANIX Rollback" "Using the previous NixOS generation"
        if [[ "$now" != "true" ]] && ! confirm "Rollback to the previous generation?" "yes"; then
            abora_warn "Rollback cancelled."
            printf '\n'
            return 0
        fi
        run_rebuild rollback
        printf '\n'
        abora_success "Rollback complete."
        printf '\n'
        return 0
    fi

    target="$(profile_target "$family" "$profile")"
    abora_banner "ANIX Rollback" "${family}/${profile}"
    maybe_snapshot_dirty_config "anix: snapshot before rollback to ${profile}"

    if [[ "$now" != "true" ]]; then
        abora_step "Dry-building ${target}"
        run_rebuild dry-build "$target"
        printf '\n'
        show_package_changes "$target"
        printf '\n'
        abora_dim_line "Review the package and activation changes above."
        if ! confirm "Rollback/switch to ${profile} now?" "yes"; then
            abora_warn "Rollback cancelled."
            printf '\n'
            return 0
        fi
    fi

    abora_step "Rebuilding ${target}"
    run_rebuild switch "$target"
    printf '\n'
    abora_success "Profile rollback complete: ${profile}"
    printf '\n'
}

do_tool_config() {
    local command="${1:-show}"
    local key="${2:-}"
    local value="${3:-}"

    case "$command" in
        show|"")
            abora_banner "ANIX Config" "${anix_tool_config}"
            abora_card_start "Tool Settings"
            abora_kv "snapshots.push" "$(anix_config_get "snapshots.push" "false")"
            abora_card_end
            printf '\n'
            ;;
        set)
            if [[ -z "$key" || -z "$value" ]]; then
                abora_error "Usage: anix config set <key> <value>"
                exit 1
            fi
            case "$key" in
                snapshots.push)
                    if ! is_yes "$value" && [[ "$value" != "false" && "$value" != "no" && "$value" != "off" && "$value" != "0" ]]; then
                        abora_error "snapshots.push must be true or false."
                        exit 1
                    fi
                    if is_yes "$value"; then
                        value="true"
                    else
                        value="false"
                    fi
                    ;;
                *)
                    abora_error "Unknown ANIX config key: ${key}"
                    abora_dim_line "Known keys: snapshots.push"
                    exit 1
                    ;;
            esac
            anix_config_set "$key" "$value"
            abora_success "'${key}' set to '${value}'"
            printf '\n'
            ;;
        *)
            abora_error "Unknown config command: ${command}"
            exit 1
            ;;
    esac
}

doctor_check() {
    local status="$1"
    local label="$2"
    case "$status" in
        ok) abora_success "$label" ;;
        warn) abora_warn "$label" ;;
        fail) abora_error "$label" ;;
    esac
}

# On Abora, `anix doctor` is the whole-system doctor (abora-doctor.py:
# bootloader, Nix, GPU, network, disk, services, --json, repair), which runs
# the ANIX config checks below as one of its parts. It asks for just those
# with ANIX_DOCTOR_LAYER_ONLY=1, which is also how `anix doctor --fix`
# reaches them. On plain NixOS there's only this part.
do_doctor_entry() {
    if is_yes "${ANIX_DOCTOR_LAYER_ONLY:-}" || [[ "${1:-}" == "--fix" || "${1:-}" == "--repair" ]] \
        || ! abora_backend >/dev/null; then
        do_doctor "$@"
        return
    fi
    run_abora_system_command doctor "$@"
}

do_doctor() {
    local fix="false"
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --fix|--repair)
                fix="true"
                ;;
            *)
                abora_error "Unknown doctor option: $1"
                exit 1
                ;;
        esac
        shift
    done

    local failures=0
    local warnings=0
    local desktop=""

    abora_banner "ANIX Doctor" "Checking the Nix/Abora management layer."

    if command -v nix >/dev/null 2>&1; then
        doctor_check ok "nix command is available"
    else
        doctor_check fail "nix command is missing"
        failures=$((failures + 1))
    fi

    if command -v nixos-rebuild >/dev/null 2>&1; then
        doctor_check ok "nixos-rebuild is available"
    else
        doctor_check fail "nixos-rebuild is missing"
        failures=$((failures + 1))
    fi

    if [[ -d "$config_dir" ]]; then
        doctor_check ok "config directory exists: ${config_dir}"
    else
        if [[ "$fix" == "true" ]]; then
            run_as_root mkdir -p "$config_dir"
            doctor_check ok "created config directory: ${config_dir}"
        else
            doctor_check fail "config directory is missing: ${config_dir}"
            failures=$((failures + 1))
        fi
    fi

    if [[ -f "$config_dir/flake.nix" ]]; then
        doctor_check ok "flake.nix exists"
        if command -v nix >/dev/null 2>&1 \
            && nix --extra-experimental-features "nix-command flakes" flake show --no-write-lock-file "$config_dir" >/dev/null 2>&1; then
            doctor_check ok "flake outputs evaluate"
        else
            doctor_check fail "flake outputs do not evaluate"
            failures=$((failures + 1))
        fi
    else
        doctor_check warn "no flake.nix found in ${config_dir}"
        warnings=$((warnings + 1))
    fi

    if config_is_git_repo; then
        doctor_check ok "config directory is a Git repo"
        if config_is_dirty; then
            doctor_check warn "config repo has unsaved changes"
            warnings=$((warnings + 1))
        else
            doctor_check ok "config repo is clean"
        fi
    else
        if [[ "$fix" == "true" ]]; then
            ensure_config_git_repo
            doctor_check ok "initialized config Git repo"
        else
            doctor_check warn "config directory is not a Git repo; snapshots will initialize one"
            warnings=$((warnings + 1))
        fi
    fi

    if [[ -f "$anix_file" ]]; then
        doctor_check ok "ANIX config exists: ${anix_file}"
        if preflight_anix_config no; then
            doctor_check ok "ANIX config preflight passed"
        else
            doctor_check fail "ANIX config preflight failed"
            failures=$((failures + 1))
        fi
        desktop="$(read_anix_option "desktop")"
        if [[ -n "$desktop" ]]; then
            local valid=""
            local known="false"
            for valid in "${valid_desktops[@]}"; do
                [[ "$desktop" == "$valid" ]] && known="true"
            done
            if [[ "$known" == "true" ]]; then
                doctor_check ok "ANIX desktop is valid: ${desktop}"
            else
                doctor_check fail "ANIX desktop is invalid: ${desktop}"
                failures=$((failures + 1))
            fi
        fi
    else
        if [[ "$fix" == "true" ]]; then
            ensure_anix_file
            doctor_check ok "created ANIX config: ${anix_file}"
        else
            doctor_check warn "ANIX config does not exist yet; run 'anix init'"
            warnings=$((warnings + 1))
        fi
    fi

    if [[ -e /nix/var/nix/profiles/system ]]; then
        doctor_check ok "system generation profile exists"
    else
        doctor_check warn "system generation profile was not found"
        warnings=$((warnings + 1))
    fi

    printf '\n'
    if [[ "$failures" -gt 0 ]]; then
        abora_error "Doctor found ${failures} problem(s) and ${warnings} warning(s)."
        exit 1
    fi
    if [[ "$warnings" -gt 0 ]]; then
        abora_warn "Doctor found ${warnings} warning(s)."
    else
        abora_success "Doctor found no problems."
    fi
    printf '\n'
}

usage() {
    abora_banner "ANIX v${anix_version}" "Nix without the homework."
    printf '  %bUsage%b\n\n' "$ABORA_WHITE" "$ABORA_NC"
    printf '  %banix learn%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show the short beginner command cheat sheet."
    printf '\n'
    printf '  %banix status%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show profile, generation, flake, Git, and snapshot state."
    printf '\n'
    printf '  %banix quickstart%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Create the ANIX config and prepare local snapshots."
    printf '\n'
    printf '  %banix docs%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show local docs paths for ANIX, packages, and Abora."
    printf '\n'
    printf '  %banix profiles%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  List flake profiles under nixosConfigurations."
    printf '\n'
    printf '  %banix generations%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show recent NixOS system generations."
    printf '\n'
    printf '  %banix switch nix <profile>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Safely switch to a named flake config."
    printf '\n'
    printf '  %banix test nix [profile]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Test-activate a profile without making it the boot default."
    printf '\n'
    printf '  %banix boot nix [profile]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Build a profile for the next boot without switching now."
    printf '\n'
    printf '  %banix diff nix [profile]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Dry-build and compare package closure changes."
    printf '\n'
    printf '  %banix rollback nix [profile] [--now]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Roll back to the previous generation or a named profile."
    printf '\n'
    printf '  %banix save%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Save a local Git snapshot of ${config_dir}."
    printf '\n'
    printf '  %banix doctor%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Check flakes, Git state, generations, and ANIX settings."
    printf '  %banix doctor --fix%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Create missing config and snapshot basics where safe."
    printf '\n'
    printf '  %banix init%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Create ${anix_file} with sensible defaults."
    printf '\n'
    printf '  %banix show%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show the current ANIX settings."
    printf '\n'
    printf '  %banix edit%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Open the ANIX config in your editor."
    printf '\n'
    printf '  %banix set hostname <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set timezone <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set keyboard <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set keyboard.xkb <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set desktop <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix set wallpaper <value>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Update a simple ANIX setting."
    printf '\n'
    printf '  %banix enable <feature>%b / %banix disable <feature>%b\n' "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Toggle bluetooth, flatpak, audio, openssh, allowUnfree, gc, power, and gaming helpers."
    abora_dim_line "  Gaming toggles add required parent options automatically."
    printf '\n'
    printf '  %banix package add <pkg>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    printf '  %banix package remove <pkg>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Add or remove Nix packages from the ANIX system package list."
    printf '\n'
    printf '  %banix service restart <unit>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Control a systemd service through ANIX."
    printf '\n'
    printf '  %banix wallpapers%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  List the wallpapers you can switch to."
    printf '\n'
    printf '  %banix config set snapshots.push true%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Opt in to pushing snapshots after local commits."
    printf '\n'
    printf '  %banix gc old%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Remove old generations after confirmation."
    printf '\n'
    printf '  %banix apply%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Rebuild the system using the ANIX layer."
    printf '\n'
    printf '  %banix language list%b / %banix language use <id>%b\n' "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  See or choose the default frontend for 'anix run' (anix, or a custom adapter)."
    printf '\n'
    printf '  %banix run <file> [--language <id>] [--yes]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Turn a .anix file into a Plan and apply it as one transaction."
    printf '\n'
    printf '  %banix validate-plan <plan.json>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Check a Plan JSON file without touching system state."
    printf '\n'
    printf '  %banix apply-plan <plan.json> [--yes]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Apply a pre-built Plan JSON file as one transaction."
    printf '\n'
    printf '  %banix diff-plan <file>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show ADD/CHANGE/REMOVE/SAME for a source or Plan JSON file, including implied gaming changes."
    printf '\n'
    printf '  %banix package install|uninstall|search|try <pkg>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Use any nixpkgs package right away, without editing the config or rebuilding."
    printf '\n'
    if abora_backend >/dev/null; then
        printf '  %bAbora OS%b\n\n' "$ABORA_WHITE" "$ABORA_NC"
        printf '  %banix update%b | %banix channel%b | %banix fallback%b | %banix install pre-alpha%b\n' "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
        abora_dim_line "  Update Abora, pick the update channel, or move to an older release. 'anix rollback' undoes an update."
        printf '  %banix welcome%b | %banix setup%b | %banix config%b | %banix desktop%b | %banix dotfiles%b\n' "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
        abora_dim_line "  First steps, the setup wizard, system settings, desktop profiles, and dotfile import."
        printf '  %banix apps%b | %banix gaming%b | %banix labs%b\n' "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
        abora_dim_line "  Flatpak app bundles and custom packages, the gaming layer, and opt-in Labs."
        printf '  %banix doctor%b | %banix recovery%b | %banix network%b | %banix repair%b | %banix hardware-test%b\n' "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
        abora_dim_line "  Health checks, recovery menu, network diagnostics, repairs, and hardware readiness."
        printf '  %banix history%b | %banix undo <id>%b | %banix undo --keep-edits <id>%b\n' "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
        abora_dim_line "  Every system change made as a safe transaction, undoing one, or getting back the edits a failed one rolled back."
        printf '  %banix logs%b | %banix check-full%b | %banix support-report%b | %banix bug-report%b\n' "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
        abora_dim_line "  Installer logs, full diagnostics, a redacted support archive, and bug reports."
        printf '  %banix build --from-source%b | %banix adopt-nixos%b | %banix welcome-gui%b | %banix config-gui%b\n' "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
        abora_dim_line "  Build Abora from source, add Abora to an existing NixOS install, and the graphical apps."
        printf '\n'
        abora_dim_line "'abora' is the same command under its old name: 'abora update' = 'anix update'."
        printf '\n'
    fi
}

do_learn() {
    abora_banner "ANIX quick start" "Small commands for changing Abora without wrestling Nix."
    abora_card_start "Read First"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix learn" "$ABORA_NC" "show this cheat sheet"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix status" "$ABORA_NC" "show profile, generation, Git, and snapshot state"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix show" "$ABORA_NC" "show the current ANIX settings"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix doctor" "$ABORA_NC" "check the ANIX/Nix config layer"
    abora_card_end
    printf '\n'

    abora_card_start "Change Settings"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix set hostname my-pc" "$ABORA_NC" "rename the computer"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix set desktop cosmic" "$ABORA_NC" "choose cosmic, gnome, plasma, hyprland, or other"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix set timezone America/New_York" "$ABORA_NC" "set timezone"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix set wallpaper titlis-alps.jpg" "$ABORA_NC" "set wallpaper"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix enable flatpak" "$ABORA_NC" "enable a feature"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix enable gaming.steam" "$ABORA_NC" "enable gaming, Steam, and controller support"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix enable gaming.big-picture" "$ABORA_NC" "enable the Steam Big Picture shortcut"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix disable openssh" "$ABORA_NC" "disable a feature"
    abora_card_end
    printf '\n'

    abora_card_start "Packages"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix package add fastfetch" "$ABORA_NC" "add a Nix package"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix pkg remove fastfetch" "$ABORA_NC" "remove a Nix package"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix package install htop" "$ABORA_NC" "install now, no rebuild"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix package try cowsay" "$ABORA_NC" "try one without installing"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix apply" "$ABORA_NC" "rebuild after ANIX changes"
    abora_card_end
    printf '\n'

    abora_card_start "Try, Apply, Undo"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix diff nix" "$ABORA_NC" "preview package closure changes"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix test nix" "$ABORA_NC" "try a rebuild without making it boot default"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix switch nix abora" "$ABORA_NC" "switch to a named profile"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix rollback nix --now" "$ABORA_NC" "roll back immediately"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix save \"message\"" "$ABORA_NC" "save a local /etc/nixos snapshot"
    abora_card_end
    printf '\n'

    abora_card_start "ANIX v2 Languages"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix language list" "$ABORA_NC" "show .anix and any custom adapters"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix run workstation.anix" "$ABORA_NC" "run a .anix file as one ANIX transaction"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix diff-plan plan.json" "$ABORA_NC" "preview a plan before applying it"
    abora_card_end
    printf '\n'
    if abora_backend >/dev/null; then
        abora_card_start "Abora OS"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix welcome" "$ABORA_NC" "first steps and quick actions"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix doctor" "$ABORA_NC" "check what is broken"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix network" "$ABORA_NC" "diagnose Wi-Fi, DNS, and update connectivity"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "sudo anix update" "$ABORA_NC" "update Abora"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix rollback nix --now" "$ABORA_NC" "undo the last update or rebuild"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix apps catalog" "$ABORA_NC" "Flatpak app bundles"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix gaming status" "$ABORA_NC" "Steam, launchers, Wine, and helpers"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix recovery" "$ABORA_NC" "rollback, repair, and support tools"
    printf '  %b│%b  %b%-40s%b %s\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "anix support-report" "$ABORA_NC" "make a redacted support archive"
        abora_card_end
        abora_dim_line "Every 'abora <command>' still works and does the same thing."
        printf '\n'
    fi
}

show_wallpapers() {
    abora_banner "ANIX Wallpapers" "These names work with 'anix set wallpaper <name>'."

    abora_card_start "Available Wallpapers"

    wallpaper_candidates | while IFS= read -r name; do
        printf '  %b│%b  %b%s%b\n' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "$name" "$ABORA_NC"
    done

    abora_card_end

    printf '\n'
}

# Abora OS system commands. Since 4.2, `anix` is the one command for Abora
# and `abora` is a compatibility name for it. These commands keep their own
# implementations (separate tools like abora-update and abora-apps on an
# installed system, plus abora.sh's logs/bug-report helpers), so anix only
# routes them. abora.sh sits next to anix.sh everywhere both ship: in
# /etc/abora on the live ISO and installed systems, and in scripts/ in a
# checkout. The standalone ANIX package for plain NixOS has no abora.sh,
# and there these commands say they're Abora-only.
abora_system_commands=(
    update channel fallback apps custom-packages desktop dotfiles gaming labs
    check-full logs log bug-report bug build adopt-nixos adopt recovery network
    repair setup welcome welcome-gui config-gui hardware-test support-report
)

is_abora_system_command() {
    local name="$1" known
    for known in "${abora_system_commands[@]}"; do
        [[ "$name" == "$known" ]] && return 0
    done
    return 1
}

abora_backend() {
    local candidate
    for candidate in "${ANIX_ABORA_BACKEND:-}" "$script_dir/abora.sh" /etc/abora/abora.sh; do
        if [[ -n "$candidate" && -f "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

run_abora_system_command() {
    local backend=""
    if ! backend="$(abora_backend)"; then
        abora_error "'anix $1' is part of Abora OS and isn't available on this system."
        abora_dim_line "Here, ANIX manages your NixOS config: see 'anix help'."
        exit 1
    fi
    # ABORA_FROM_ANIX stops abora.sh from handing a command it doesn't know
    # back to anix, so a typo can never bounce between the two.
    ABORA_FROM_ANIX=1 exec bash "$backend" "$@"
}

# `anix config` was ANIX's own tool settings (only snapshots.push) and
# `abora config` the installed system's settings (abora-local.nix). Now that
# both are `anix config`, the system settings win, and keys under
# snapshots. still go to the tool settings. Without Abora's config tool
# (plain NixOS), it's only the tool settings, as before.
do_config() {
    local sub="${1:-show}"
    if [[ "$sub" == "tool" ]]; then
        shift
        do_tool_config "$@"
        return
    fi
    if [[ "${2:-}" == snapshots.* ]] || ! abora_backend >/dev/null || ! command -v abora-config >/dev/null 2>&1; then
        do_tool_config "$@"
        return
    fi
    run_abora_system_command config "$@"
}

# ASA's transaction log: every switch anix, anix config/apps and anix update
# ran through ABT, and `anix undo <id>` to go back to before one of them.
do_abt() {
    local action="$1"
    shift
    if ! command -v abora-abt >/dev/null 2>&1; then
        abora_error "Abora's transaction engine (abora-abt) isn't installed here."
        abora_dim_line "Generations are still there: anix generations, anix rollback nix"
        exit 1
    fi
    if [[ "$action" == "undo" ]]; then
        # --keep-edits: a change that failed and was rolled back kept the
        # edits that broke it; this puts them back to fix, then apply again.
        if [[ "${1:-}" == "--keep-edits" && $# -eq 2 ]]; then
            run_as_root abora-abt restore-edits "$2"
            return
        fi
        [[ $# -eq 1 ]] || { abora_error "Usage: anix undo <id> | anix undo --keep-edits <id>   (ids from 'anix history')"; exit 1; }
        run_as_root abora-abt undo "$1"
        return
    fi
    run_as_root abora-abt "$action" "$@"
}

main() {
    local command="${1:-show}"

    case "$command" in
        version|--version|-v) shift || true; do_version "$@" ;;
        --gui|gui) shift || true; do_gui "$@" ;;
        learn|cheatsheet|commands) shift || true; do_learn "$@" ;;
        status) shift || true; do_status "$@" ;;
        quickstart|start) shift || true; do_quickstart "$@" ;;
        docs|doc) shift || true; do_docs "$@" ;;
        profiles|profile|ls) shift || true; do_profiles "$@" ;;
        generations|gens) shift || true; do_generations "$@" ;;
        init) shift || true; do_init "$@" ;;
        show|"") shift || true; show_config "$@" ;;
        edit) shift || true; do_edit "$@" ;;
        wallpapers) shift || true; show_wallpapers "$@" ;;
        set) shift || true; do_set "$@" ;;
        enable) shift || true; do_toggle true "$@" ;;
        disable) shift || true; do_toggle false "$@" ;;
        package|pkg) shift || true; do_package "$@" ;;
        service) shift || true; do_service "$@" ;;
        apply) shift || true; do_apply "$@" ;;
        test) shift || true; do_test "$@" ;;
        boot) shift || true; do_boot "$@" ;;
        diff) shift || true; do_diff "$@" ;;
        language|lang) shift || true; do_language "$@" ;;
        run) shift || true; do_run "$@" ;;
        validate-plan) shift || true; do_validate_plan "$@" ;;
        apply-plan) shift || true; do_apply_plan "$@" ;;
        diff-plan) shift || true; do_diff_plan "$@" ;;
        switch) shift || true; do_switch "$@" ;;
        rollback) shift || true; do_rollback "$@" ;;
        save) shift || true; do_save "$@" ;;
        config) shift || true; do_config "$@" ;;
        install)
            # `anix install pre-alpha` was `abora install pre-alpha`; any
            # other name is a package, like `anix package install`.
            if [[ "${2:-}" == "pre-alpha" ]]; then
                run_abora_system_command "$@"
            fi
            shift; do_package_install "$@" ;;
        uninstall) shift; do_package_uninstall "$@" ;;
        history|transactions) shift || true; do_abt list "$@" ;;
        undo) shift || true; do_abt undo "$@" ;;
        search) shift; do_package_search "$@" ;;
        gc|clean) shift || true; do_gc "$@" ;;
        doctor) shift || true; do_doctor_entry "$@" ;;
        tinypm|grab)
            abora_warn "TinyPM was removed in Abora OS 4.2. Packages now come from: anix package"
            printf '\n'
            package_usage
            exit 1
            ;;
        help|--help|-h) usage ;;
        *)
            if is_abora_system_command "$command"; then
                run_abora_system_command "$@"
            fi
            abora_error "Unknown ANIX command: ${command}"
            printf '\n'
            usage
            exit 1
            ;;
    esac
}

main "$@"
