#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
script_self="${BASH_SOURCE[0]}"
script_hash_before="$(sha256sum "$script_self" 2>/dev/null | awk '{print $1}' || true)"
ui_lib="${ABORA_UI_LIB:-$script_dir/abora-ui.sh}"

if [[ ! -f "$ui_lib" && -f /etc/abora/ui.sh ]]; then
    ui_lib="/etc/abora/ui.sh"
fi

# shellcheck source=/dev/null
source "$ui_lib"

config_dir="${ABORA_SYSTEM_CONFIG:-/etc/nixos}"
command_name="${ABORA_UPDATE_COMMAND:-$(basename "$0")}"
# The AboraProject org fallback is intentional (a registered organization
# the repo may move to), not a stray/untrusted URL — list_release_tags()
# below tries each of these in order and uses whichever answers first.
repo_git_url="${ABORA_REPO_GIT_URL:-https://github.com/AnimatedGTVR/abora-os.git}"
repo_git_fallbacks="${ABORA_REPO_GIT_URLS:-$repo_git_url https://github.com/AnimatedGTVR/Abora-OS.git https://github.com/AboraProject/Abora-OS.git}"
repo_ref="${ABORA_REPO_REF:-main}"
upstream_dir="${ABORA_UPSTREAM_DIR:-$config_dir/.abora-upstream}"
flake_config_name="${ABORA_FLAKE_CONFIG_NAME:-abora}"
fallback_ref="${ABORA_FALLBACK_REF:-}"
fallback_mode="${ABORA_FALLBACK_MODE:-0}"
allow_downgrade="${ABORA_ALLOW_DOWNGRADE:-0}"
pre_alpha_mode="${ABORA_PRE_ALPHA_MODE:-0}"
pre_alpha_ref="${ABORA_PRE_ALPHA_REF:-main}"
dry_run="${ABORA_DRY_RUN:-0}"
effective_ref=""
effective_ref_reason=""
update_tmp_files=()
update_tmp_dirs=()
suppress_update_failure_message=0

cleanup_update_tmp_files() {
    local file
    for file in "${update_tmp_files[@]:-}"; do
        [[ -n "$file" ]] && rm -f "$file" 2>/dev/null || true
    done

    local dir
    for dir in "${update_tmp_dirs[@]:-}"; do
        [[ -n "$dir" ]] && rm -rf "$dir" 2>/dev/null || true
    done
}

drop_upstream_git_metadata() {
    [[ -n "${upstream_dir:-}" && -d "$upstream_dir/.git" ]] || return 0
    rm -rf "$upstream_dir/.git"
}

# Runs on every exit path (success, error, or an early `exit` deep in the
# script) via the trap below, so temp files/dirs are never leaked and a
# failed update always ends with a clear statement of what state the system
# was left in. suppress_update_failure_message lets a caller that already
# printed its own specific error (e.g. mid-validation) opt out of this
# generic one.
on_update_exit() {
    local rc="$1"
    cleanup_update_tmp_files
    if [[ "$rc" -ne 0 && "$suppress_update_failure_message" -ne 1 ]]; then
        abora_error "Update failed before completion; existing flake.nix was left untouched unless an atomic replacement had already passed validation." >&2 || true
    fi
}

trap 'on_update_exit "$?"' EXIT

# ── Channel helpers ───────────────────────────────────────────────────────────

channel_file() {
    printf '%s/abora/channel' "$config_dir"
}

read_channel() {
    local cf
    if [[ -n "${ABORA_RELEASE_CHANNEL:-}" ]]; then
        printf '%s' "$ABORA_RELEASE_CHANNEL"
        return
    fi
    cf="$(channel_file)"
    if [[ -f "$cf" ]]; then
        tr -d '[:space:]' < "$cf"
    else
        printf 'stable'
    fi
}

write_channel() {
    local name="${1:-stable}" cf
    cf="$(channel_file)"
    mkdir -p "$(dirname "$cf")"
    printf '%s\n' "$name" > "$cf"
}

installed_version() {
    local candidate
    for candidate in \
        "${ABORA_INSTALLED_VERSION:-}" \
        "$config_dir/abora/VERSION" \
        /etc/abora/VERSION \
        "$script_dir/../VERSION"; do
        if [[ -n "$candidate" && -f "$candidate" ]]; then
            tr -d '[:space:]' < "$candidate"
            return
        elif [[ -n "$candidate" && ! -e "$candidate" ]]; then
            printf '%s' "$candidate"
            return
        fi
    done
    printf '0'
}

# Strips a leading "v" and any DEMO/dev/pre/RC suffix, leaving just the
# dotted numeric version — lets a demo tag like v4.1-DEMO2 be compared
# against the plain v4.1 final release by version number alone.
tag_base_version() {
    local tag="${1#v}"
    sed -E 's/^([0-9]+([.][0-9]+)*).*/\1/' <<<"$tag"
}

is_final_release_tag() {
    [[ "$1" =~ ^v[0-9]+([.][0-9]+)*$ ]]
}

is_demo_release_tag() {
    [[ "$1" =~ ^v[0-9]+([.][0-9]+)*.*(DEMO|[Dd]emo|[Dd]ev|[Pp]re|[Rr][Cc]).*$ ]]
}

# `sort -V` (version sort) rather than string comparison, so v4.9 correctly
# sorts before v4.10.
version_lt() {
    local a="$1" b="$2" first
    [[ "$a" == "$b" ]] && return 1
    first="$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -n1)"
    [[ "$first" == "$a" ]]
}

# Tries every URL in repo_git_fallbacks in order, returning the first one
# that answers — ABORA_RELEASE_TAGS lets tests inject a fixed tag list
# without any network access at all.
list_release_tags() {
    if [[ -n "${ABORA_RELEASE_TAGS:-}" ]]; then
        printf '%s\n' $ABORA_RELEASE_TAGS
        return
    fi
    local url
    for url in $repo_git_fallbacks; do
        if git ls-remote --tags "$url" 'refs/tags/v*' 2>/dev/null \
            | grep -v '\^{}' \
            | awk '{print $2}' \
            | sed 's|refs/tags/||'; then
            return 0
        fi
    done
    return 1
}

latest_tag_from_list() {
    sort -V | tail -n1
}

# Resolves a channel name + the currently installed version into a single
# concrete git ref to update to (a tag or "main"), setting effective_ref and
# a human-readable effective_ref_reason for later display. "stable" is the
# most involved: prefer the newest final tag that's not older than what's
# installed, then fall back to a matching demo/dev tag for the same release
# line, and only fall back to tracking main directly if neither exists yet.
resolve_update_ref() {
    local channel="$1" current_version="$2" tags final_tag demo_tag older_tag

    effective_ref=""
    effective_ref_reason=""

    if [[ "$fallback_mode" -eq 1 ]]; then
        effective_ref="$fallback_ref"
        effective_ref_reason="explicit fallback requested"
        allow_downgrade=1
        return 0
    fi

    case "$channel" in
        pre-alpha|prealpha)
            effective_ref="$pre_alpha_ref"
            effective_ref_reason="pre-alpha build requested explicitly"
            return 0
            ;;
        unstable)
            effective_ref="main"
            effective_ref_reason="unstable channel tracks main"
            return 0
            ;;
        demo|dev)
            tags="$(list_release_tags | grep -E '^v[0-9]+([.][0-9]+)*.*(DEMO|[Dd]emo|[Dd]ev|[Pp]re|[Rr][Cc]).*$' || true)"
            demo_tag="$(printf '%s\n' "$tags" | awk -v cur="$current_version" 'NF && $0 ~ ("^v" cur) { print }' | latest_tag_from_list)"
            if [[ -z "$demo_tag" ]]; then
                demo_tag="$(printf '%s\n' "$tags" | latest_tag_from_list)"
            fi
            if [[ -n "$demo_tag" ]]; then
                effective_ref="$demo_tag"
                effective_ref_reason="demo channel selected latest demo/dev tag"
                return 0
            fi
            ;;
        stable|"")
            tags="$(list_release_tags || true)"
            final_tag="$(
                printf '%s\n' "$tags" \
                    | grep -E '^v[0-9]+([.][0-9]+)*$' \
                    | while IFS= read -r tag; do
                        [[ -n "$tag" ]] || continue
                        if ! version_lt "$(tag_base_version "$tag")" "$current_version"; then
                            printf '%s\n' "$tag"
                        fi
                    done \
                    | latest_tag_from_list
            )"
            if [[ -n "$final_tag" ]]; then
                effective_ref="$final_tag"
                effective_ref_reason="stable channel selected latest final tag not older than installed version"
                return 0
            fi

            demo_tag="$(
                {
                    printf '%s\n' "$tags" \
                        | grep -E '^v[0-9]+([.][0-9]+)*.*(DEMO|[Dd]emo|[Dd]ev|[Pp]re|[Rr][Cc]).*$' \
                        | awk -v cur="$current_version" 'NF && $0 ~ ("^v" cur) { print }' \
                        | latest_tag_from_list
                } || true
            )"
            if [[ -n "$demo_tag" ]]; then
                effective_ref="$demo_tag"
                effective_ref_reason="stable channel found no final tag for this release line; using matching demo/dev tag"
                return 0
            fi

            older_tag="$(printf '%s\n' "$tags" | grep -E '^v[0-9]+([.][0-9]+)*$' | latest_tag_from_list)"
            if [[ -n "$older_tag" ]]; then
                effective_ref="main"
                effective_ref_reason="stable channel has no final tag newer than installed version; using main"
                return 0
            fi
            ;;
        *)
            abora_warn "Unknown channel '${channel}' — using unstable/main." >&2
            effective_ref="main"
            effective_ref_reason="unknown channel fallback to main"
            return 0
            ;;
    esac

    abora_error "Could not resolve an Abora update ref for channel '${channel}'."
    return 1
}

# A normal `abora update` should never silently move a system backwards
# (e.g. because a stable tag got deleted/retagged) — only an explicit
# `abora fallback --release <tag>` (which sets allow_downgrade=1) or
# tracking main directly is allowed to move to an older version.
guard_against_accidental_downgrade() {
    local current_version="$1" selected_ref="$2" selected_version

    [[ "$selected_ref" == "main" || "$allow_downgrade" -eq 1 ]] && return 0
    selected_version="$(tag_base_version "$selected_ref")"
    if version_lt "$selected_version" "$current_version"; then
        abora_error "Refusing accidental downgrade."
        abora_error "  installed version : ${current_version}"
        abora_error "  selected ref      : ${selected_ref}"
        abora_error "  selected version  : ${selected_version}"
        abora_error "Use an explicit fallback command to downgrade intentionally:"
        abora_error "  sudo abora fallback --release ${selected_ref}"
        return 1
    fi
}

# ── Usage ─────────────────────────────────────────────────────────────────────

usage() {
    abora_banner "System Update" "Keep your Abora installation up to date."
    printf '  %bCommands%b\n\n' "$ABORA_WHITE" "$ABORA_NC"
    printf '  %babora update%b  /  %bnixos update%b  /  %bupdate%b  /  %babora-update%b\n' \
        "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Sync the latest Abora files and rebuild the system."
    printf '\n'
    printf '  %babora update --check%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Check whether an update is available without installing it."
    printf '\n'
    printf '  %babora rollback%b  /  %bnixos rollback%b  /  %brollback%b\n' "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Roll back to the previous system generation."
    printf '\n'
    printf '  %babora channel%b  /  %bnixos channel%b\n' "$ABORA_CYAN" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Show the current update channel."
    printf '\n'
    printf '  %bnixos channel list%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  List all available channels."
    printf '\n'
    printf '  %bnixos channel set <stable|demo|unstable>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Switch to a different update channel."
    printf '\n'
    printf '  %babora fallback --release <tag>%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Intentionally downgrade or pin to an older release."
    printf '\n'
    printf '  %bsudo abora install pre-alpha [--dry-run] [--ref <git-ref>]%b\n' "$ABORA_CYAN" "$ABORA_NC"
    abora_dim_line "  Install unfinished pre-alpha development builds after an explicit risk prompt."
    printf '\n'
}

parse_fallback_args() {
    case "${1:-}" in
        --release)
            fallback_ref="${2:-}"
            ;;
        --force)
            fallback_ref="${2:-}"
            ;;
        help|--help|-h|"")
            printf 'Usage: abora fallback --release <tag>\n'
            exit 0
            ;;
        *)
            abora_error "Usage: abora fallback --release <tag>"
            exit 1
            ;;
    esac

    if [[ -z "$fallback_ref" ]]; then
        abora_error "Fallback release tag is required."
        exit 1
    fi
    [[ "$fallback_ref" == v* || "$fallback_ref" == "main" ]] || fallback_ref="v${fallback_ref}"
    fallback_mode=1
    allow_downgrade=1
}

show_pre_alpha_warning() {
    cat <<'EOF'
WARNING: ABORA PRE-ALPHA BUILD

Pre-alpha builds are unfinished development versions intended only for testing and gathering feedback.

Installing this build may:

- Prevent your system from booting
- Break existing applications or configurations
- Cause data loss
- Require manual recovery or a complete reinstall
- Include incomplete, unstable, or missing features

Do not install this build on your primary computer or any system containing important data.

Back up all important files before continuing.

Type `I ACCEPT THE RISK` to continue:
EOF
}

confirm_pre_alpha_risk() {
    local expected="I ACCEPT THE RISK"
    local answer="${ABORA_PRE_ALPHA_ACCEPT:-}"

    show_pre_alpha_warning

    if [[ -z "$answer" ]]; then
        if [[ -r /dev/tty ]]; then
            read -r answer </dev/tty || answer=""
        elif [[ -t 0 ]]; then
            read -r answer || answer=""
        else
            suppress_update_failure_message=1
            abora_error "Pre-alpha install requires an interactive confirmation."
            abora_error "Type exactly: ${expected}"
            return 1
        fi
    fi

    if [[ "$answer" != "$expected" ]]; then
        suppress_update_failure_message=1
        abora_error "Confirmation did not match; pre-alpha install cancelled."
        return 1
    fi
}

parse_install_args() {
    local target="${1:-}"
    shift || true

    case "$target" in
        pre-alpha|prealpha)
            pre_alpha_mode=1
            ;;
        help|--help|-h|"")
            printf 'Usage: sudo abora install pre-alpha [--dry-run] [--ref <git-ref>]\n'
            exit 0
            ;;
        *)
            abora_error "Unknown install target: ${target}"
            abora_error "Usage: sudo abora install pre-alpha [--dry-run] [--ref <git-ref>]"
            exit 1
            ;;
    esac

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run=1
                shift
                ;;
            --ref)
                pre_alpha_ref="${2:-}"
                if [[ -z "$pre_alpha_ref" ]]; then
                    abora_error "Usage: sudo abora install pre-alpha [--dry-run] [--ref <git-ref>]"
                    exit 1
                fi
                shift 2
                ;;
            *)
                abora_error "Unknown install option: $1"
                abora_error "Usage: sudo abora install pre-alpha [--dry-run] [--ref <git-ref>]"
                exit 1
                ;;
        esac
    done
}

# ── Channel subcommand ────────────────────────────────────────────────────────

handle_channel_command() {
    local sub="${1:-}" channel

    case "$sub" in
        "" | show)
            channel="$(read_channel)"
            abora_banner "Update Channel" "Your system receives updates from this channel."
            printf '  %bChannel%b    %b%s%b\n' "$ABORA_DIM" "$ABORA_NC" "$ABORA_CYAN" "$channel" "$ABORA_NC"
            case "$channel" in
                stable)
                    abora_dim_line "  Tracks tagged Abora releases. Recommended for most users."
                    ;;
                unstable)
                    abora_dim_line "  Tracks the main development branch. May include breaking changes."
                    ;;
                demo|dev)
                    abora_dim_line "  Tracks tagged demo/dev builds for the installed release line."
                    ;;
            esac
            printf '\n'
            ;;
        list)
            abora_banner "Update Channels" "Choose how your system receives updates."
            channel="$(read_channel)"

            abora_card_start "Available Channels"

            local marker_stable="" marker_demo="" marker_unstable=""
            [[ "$channel" == "stable" ]]   && marker_stable=" %b◀ current%b"
            [[ "$channel" == "demo" || "$channel" == "dev" ]] && marker_demo=" %b◀ current%b"
            [[ "$channel" == "unstable" ]] && marker_unstable=" %b◀ current%b"

            printf '  %b│%b  %bstable%b' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
            # shellcheck disable=SC2059
            [[ -n "$marker_stable" ]]   && printf "  $marker_stable" "$ABORA_GREEN" "$ABORA_NC"
            printf '\n'
            printf '  %b│%b  %bLatest tagged Abora releases. Recommended for most users.%b\n' \
                "$ABORA_BLUE" "$ABORA_NC" "$ABORA_DIM" "$ABORA_NC"
            printf '\n'

            printf '  %b│%b  %bdemo%b' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
            # shellcheck disable=SC2059
            [[ -n "$marker_demo" ]] && printf "  $marker_demo" "$ABORA_GREEN" "$ABORA_NC"
            printf '\n'
            printf '  %b│%b  %bTagged demo/dev builds for the installed release line.%b\n' \
                "$ABORA_BLUE" "$ABORA_NC" "$ABORA_DIM" "$ABORA_NC"
            printf '\n'

            printf '  %b│%b  %bunstable%b' "$ABORA_BLUE" "$ABORA_NC" "$ABORA_CYAN" "$ABORA_NC"
            # shellcheck disable=SC2059
            [[ -n "$marker_unstable" ]] && printf "  $marker_unstable" "$ABORA_GREEN" "$ABORA_NC"
            printf '\n'
            printf '  %b│%b  %bDevelopment builds from the main branch. May include breaking changes.%b\n' \
                "$ABORA_BLUE" "$ABORA_NC" "$ABORA_DIM" "$ABORA_NC"
            printf '  %b│%b\n' "$ABORA_BLUE" "$ABORA_NC"

            abora_card_end

            printf '\n'
            ;;
        set)
            local new_channel="${2:-}"
            case "$new_channel" in
                stable | demo | dev | unstable)
                    run_as_root env \
                        ABORA_SYSTEM_CONFIG="$config_dir" \
                        bash -c '
                            channel_file="'"$config_dir"'/abora/channel"
                            mkdir -p "$(dirname "$channel_file")"
                            printf "%s\n" "'"$new_channel"'" > "$channel_file"
                        '
                    abora_success "Channel set to '${new_channel}'."
                    abora_dim_line "Run 'update' to apply the new channel."
                    printf '\n'
                    ;;
                "")
                    abora_error "Specify a channel: stable, demo, or unstable"
                    exit 1
                    ;;
                *)
                    abora_error "Unknown channel: ${new_channel}. Use 'stable', 'demo', or 'unstable'."
                    exit 1
                    ;;
            esac
            ;;
        *)
            abora_error "Unknown channel subcommand: ${sub}"
            exit 1
            ;;
    esac
}

# ── Check (read-only, no root, no rebuild) ───────────────────────────────────

# Resolves whether an update is available without touching the system --
# runs as the calling user, no re-exec to root, no file writes. Meant for
# both `abora update --check` on the CLI and the Welcome GUI's status card.
#
# Prints one machine-parseable line to stdout:
#   ABORA_UPDATE_AVAILABLE\t<current_version>\t<available_ref>\t<channel>
#   ABORA_UPDATE_CURRENT\t<current_version>\t<channel>
# Exit codes: 0 = up to date, 10 = update available, 1 = could not check.
handle_check_command() {
    local current_version channel

    # Exit code 10 (update available) isn't a failure -- don't let the
    # generic "update failed" trap message fire for it.
    suppress_update_failure_message=1

    current_version="$(installed_version)"
    channel="$(read_channel)"

    if ! resolve_update_ref "$channel" "$current_version"; then
        abora_error "Could not resolve an update for channel '${channel}' — check your internet connection."
        return 1
    fi

    local available_version
    available_version="$(tag_base_version "$effective_ref")"

    abora_banner "Update Check" "Channel: ${channel}"
    printf '  %bInstalled version%b   %s\n' "$ABORA_DIM" "$ABORA_NC" "$current_version"
    printf '  %bLatest on channel%b   %s\n' "$ABORA_DIM" "$ABORA_NC" "$effective_ref"

    if [[ "$effective_ref" != "main" ]] && ! version_lt "$current_version" "$available_version"; then
        printf '\n'
        abora_success "You're up to date."
        printf '\n'
        printf 'ABORA_UPDATE_CURRENT\t%s\t%s\n' "$current_version" "$channel"
        return 0
    fi

    printf '\n'
    abora_success "Update available: ${effective_ref}"
    abora_dim_line "Run 'sudo abora update' to install it."
    printf '\n'
    printf 'ABORA_UPDATE_AVAILABLE\t%s\t%s\t%s\n' "$current_version" "$effective_ref" "$channel"
    return 10
}

# ── System helpers ────────────────────────────────────────────────────────────

run_as_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
        return
    fi

    if command -v sudo >/dev/null 2>&1; then
        sudo "$@"
        return
    fi

    abora_error "This command needs root privileges. Run it as root or install sudo."
    exit 1
}

confirm() {
    local prompt="$1"
    local answer=""
    if [[ ! -t 0 ]]; then
        return 0
    fi
    printf '  %b%s [Y/n]%b ' "$ABORA_YELLOW" "$prompt" "$ABORA_NC"
    read -r answer
    case "$answer" in
        ""|y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

copy_upstream_file() {
    local source="$1"
    local destination="$2"

    if [[ ! -f "$source" ]]; then
        abora_error "Required upstream file is missing."
        abora_error "  selected ref: ${effective_ref:-${repo_ref:-unknown}}"
        abora_error "  upstream dir : ${upstream_dir}"
        abora_error "  missing file : ${source#"$upstream_dir"/}"
        abora_error "Retry with: sudo abora update"
        return 1
    fi

    mkdir -p "$(dirname "$destination")"
    cp "$source" "$destination"
}

copy_first_existing_upstream_file() {
    local destination="$1"
    shift

    local source=""
    for source in "$@"; do
        if [[ -f "$source" ]]; then
            mkdir -p "$(dirname "$destination")"
            cp "$source" "$destination"
            return 0
        fi
    done

    abora_error "None of the expected upstream files were found for ${destination##*/}."
    abora_error "  selected ref: ${effective_ref:-${repo_ref:-unknown}}"
    abora_error "  upstream dir : ${upstream_dir}"
    abora_error "Retry with: sudo abora update"
    return 1
}

# The update process itself just synced a possibly-newer scripts/abora-update.sh
# from upstream into $config_dir/abora/update.sh. If that copy now differs
# from the running script (script_hash_before, captured at the very top of
# this file), the rest of the update should run under the NEW updater's
# logic, not the old one still executing in memory — so this re-execs into
# it exactly once (ABORA_UPDATE_REEXECED guards against a loop) before
# continuing.
maybe_reexec_synced_updater() {
    local synced_script="$config_dir/abora/update.sh"
    local script_hash_after=""

    [[ "${ABORA_UPDATE_REEXECED:-0}" != 1 ]] || return 0
    [[ -n "$script_hash_before" && -f "$synced_script" ]] || return 0

    script_hash_after="$(sha256sum "$synced_script" 2>/dev/null | awk '{print $1}' || true)"
    [[ -n "$script_hash_after" && "$script_hash_after" != "$script_hash_before" ]] || return 0

    abora_info "Restarting with the synced updater."
    exec env \
        ABORA_UPDATE_REEXECED=1 \
        ABORA_UPDATE_COMMAND="$command_name" \
        ABORA_SYSTEM_CONFIG="$config_dir" \
        ABORA_REPO_GIT_URL="$repo_git_url" \
        ABORA_REPO_GIT_URLS="$repo_git_fallbacks" \
        ABORA_REPO_REF="$repo_ref" \
        ABORA_UPSTREAM_DIR="$upstream_dir" \
        ABORA_FLAKE_CONFIG_NAME="$flake_config_name" \
        ABORA_UI_LIB="$ui_lib" \
        bash "$synced_script"
}

# ── Upstream checkout validation ──────────────────────────────────────────────

release_uses_modern_layout() {
    local selected_ref="$1"
    [[ "$selected_ref" == "main" ]] && return 0
    is_demo_release_tag "$selected_ref" && return 1
    is_final_release_tag "$selected_ref" || return 1
    ! version_lt "$(tag_base_version "$selected_ref")" "3.14"
}

release_has_anix_languages() {
    local selected_ref="$1"
    [[ "$selected_ref" == "main" ]] && return 0
    is_final_release_tag "$selected_ref" || return 1
    ! version_lt "$(tag_base_version "$selected_ref")" "4.0"
}

# These release_has_*/release_uses_* checks gate which upstream paths get
# synced (required_upstream_paths below) based on which repo layout the
# selected tag actually shipped with — older tags predate directories like
# nix/modules/desktops or files like anix-languages, so unconditionally
# requiring them would break updates/fallbacks to anything before the
# version each feature landed in.
# The uncredited wallpaper set (oceandusk.png/bluehorizon.png/
# astronautwallpaper.png/glacierreflection.png) was replaced with credited
# PickPik photos partway through the 4.0 line, after v3.14 was already
# tagged — so this can't reuse release_has_anix_languages's ">= 4.0" cutoff
# without also requiring a file older 4.0-line checkouts never had.
release_has_alpine_wallpapers() {
    local selected_ref="$1"
    [[ "$selected_ref" == "main" ]] && return 0
    is_final_release_tag "$selected_ref" || return 1
    ! version_lt "$(tag_base_version "$selected_ref")" "4.1"
}

release_has_welcome_config_gui() {
    local selected_ref="$1"
    [[ "$selected_ref" == "main" ]] && return 0
    is_final_release_tag "$selected_ref" || return 1
    ! version_lt "$(tag_base_version "$selected_ref")" "4.1"
}

required_upstream_paths() {
    local selected_ref="${1:-main}"
    cat <<'EOF'
VERSION
nix/modules/abora-options.nix
nix/modules/installed-base.nix
nix/modules/anix.nix
scripts/abora-update.sh
scripts/abora-installer.sh
scripts/abora-ui.sh
scripts/abora-config.sh
scripts/abora.sh
scripts/abora-desktop.sh
scripts/abora-doctor.sh
scripts/abora-recovery.sh
scripts/abora-welcome.sh
scripts/anix.sh
scripts/abora-app-catalog.sh
scripts/abora-apps.sh
scripts/abora-support-report.sh
scripts/abora-hardware-test.sh
scripts/abora-desktop-profiles.sh
scripts/abora-session-setup.sh
scripts/abora-theme-sync.sh
assets/abora-title.txt
assets/fastfetch-logo.txt
assets/fastfetch-config.jsonc
assets/bootloader/background.png
assets/bootloader/theme.txt
assets/plymouth/abora.plymouth
assets/plymouth/abora.script
assets/Effects/LaunchingAbora.mp3
assets/wallpapers/collection
assets/wallpaper-themes
EOF

    if release_uses_modern_layout "$selected_ref"; then
        cat <<'EOF'
nix/modules/desktops
nix/pkgs/mango.nix
nix/pkgs/modularity.nix
scripts/abora-repair-flake-purity.sh
assets/mango/config.conf
EOF
    fi

    if release_has_anix_languages "$selected_ref"; then
        cat <<'EOF'
assets/anix-languages
nix/pkgs/moducpp-anix.nix
tools/moducpp-anix
EOF
    fi

    if release_has_alpine_wallpapers "$selected_ref"; then
        cat <<'EOF'
assets/wallpapers/collection/aurora-lofoten.jpg
EOF
    fi

    if release_has_welcome_config_gui "$selected_ref"; then
        cat <<'EOF'
scripts/abora-welcome-gui.py
scripts/abora-config-gui.py
EOF
    fi
}

# Checks that every path required_upstream_paths() expects for this ref
# actually exists in the freshly cloned checkout. This guards against a
# truncated/corrupt clone or a ref whose layout this script doesn't know
# about yet — it is NOT a cryptographic integrity check (no GPG/checksum
# verification of the clone happens anywhere in this file); it only proves
# the expected files are present, not that their contents are untampered.
validate_upstream_checkout() {
    local checkout_dir="$1"
    local selected_ref="$2"
    local rel missing=0

    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        if [[ ! -e "$checkout_dir/$rel" ]]; then
            if [[ "$missing" -eq 0 ]]; then
                abora_error "Fetched Abora checkout is incomplete; refusing to update installed files."
                abora_error "  selected ref: ${selected_ref}"
                abora_error "  checkout    : ${checkout_dir}"
                abora_error "  missing:"
            fi
            printf '    - %s\n' "$rel" >&2
            missing=1
        fi
    done < <(required_upstream_paths "$selected_ref")

    if [[ "$missing" -ne 0 ]]; then
        abora_error "Retry with: sudo abora update"
        return 1
    fi
}

# Shallow-clones $selected_ref into a sibling temp directory (never directly
# into $upstream_dir, so a failed/partial clone can't corrupt a previously
# good checkout), tries every URL in repo_git_fallbacks in turn, validates
# the result, then atomically replaces $upstream_dir only once validation
# passes.
prepare_verified_upstream() {
    local selected_ref="$1"
    local parent tmp_checkout timestamp url cloned_url=""

    parent="$(dirname "$upstream_dir")"
    timestamp="$(date +%Y%m%d-%H%M%S)"
    tmp_checkout="${upstream_dir}.tmp-$$-${timestamp}"
    update_tmp_dirs+=("$tmp_checkout")

    mkdir -p "$parent"
    rm -rf "$tmp_checkout"

    abora_info "Fetching Abora files (${selected_ref}) into a temporary checkout."
    for url in $repo_git_fallbacks; do
        rm -rf "$tmp_checkout"
        if git clone --depth=1 --branch "$selected_ref" "$url" "$tmp_checkout"; then
            cloned_url="$url"
            break
        fi
        abora_warn "Could not clone ${url} at ${selected_ref}; trying the next Abora remote."
    done
    if [[ -z "$cloned_url" ]]; then
        abora_error "Failed to clone Abora OS at ${selected_ref} from every known remote."
        abora_error "Tried: ${repo_git_fallbacks}"
        abora_error "Check your internet connection, then run: sudo ${command_name:-nixos} update"
        return 1
    fi
    repo_git_url="$cloned_url"

    validate_upstream_checkout "$tmp_checkout" "$selected_ref" || return 1

    rm -rf "$tmp_checkout/.git"
    rm -rf "$upstream_dir"
    mv "$tmp_checkout" "$upstream_dir"

    local i
    for i in "${!update_tmp_dirs[@]}"; do
        if [[ "${update_tmp_dirs[$i]}" == "$tmp_checkout" ]]; then
            unset 'update_tmp_dirs[i]'
            break
        fi
    done
}

# ── File sync ─────────────────────────────────────────────────────────────────

# Update-time counterpart to abora-installer.sh's install_mango_config_asset:
# keeps mango's config.conf as a real file under $config_dir/abora rather
# than a reference to an ephemeral /nix/store path, so the installed flake
# doesn't break when that store path gets garbage-collected.
install_mango_config_asset() {
    local abora_dir="$config_dir/abora"
    local dest="$abora_dir/mango/config.conf"
    local candidate

    mkdir -p "$(dirname "$dest")"
    for candidate in \
        "$upstream_dir/assets/mango/config.conf" \
        "$config_dir/.abora-upstream/assets/mango/config.conf" \
        /etc/abora/mango/config.conf \
        "$config_dir/assets/mango/config.conf"; do
        if [[ -f "$candidate" ]]; then
            cp "$candidate" "$dest"
            return 0
        fi
    done

    : > "$dest"
}

rewrite_installed_mango_config_paths() {
    local abora_dir="$config_dir/abora"
    local bad_store='/nix/store'
    bad_store="${bad_store}/assets/mango/config.conf"
    local file

    for file in "$abora_dir/abora-options.nix" "$abora_dir/installed-base.nix"; do
        [[ -f "$file" ]] || continue
        sed -i \
            -e "s|\"${bad_store}\"|./mango/config.conf|g" \
            -e "s|${bad_store}|./mango/config.conf|g" \
            -e 's|../../assets/mango/config\.conf|./mango/config.conf|g' \
            -e 's|../../../assets/mango/config\.conf|./mango/config.conf|g' \
            "$file"
    done

    if [[ -d "$abora_dir/desktops" ]]; then
        while IFS= read -r -d '' file; do
            sed -i \
                -e "s|\"${bad_store}\"|../mango/config.conf|g" \
                -e "s|${bad_store}|../mango/config.conf|g" \
                -e 's|../../assets/mango/config\.conf|../mango/config.conf|g' \
                -e 's|../../../assets/mango/config\.conf|../mango/config.conf|g' \
                "$file"
        done < <(
            grep -RIlZ \
                -e "$bad_store" \
                -e '../../assets/mango/config.conf' \
                -e '../../../assets/mango/config.conf' \
                "$abora_dir/desktops" 2>/dev/null || true
        )
    fi
}

sync_abora_files() {
    local effective_ref="$1"
    local abora_dir="$config_dir/abora"
    local upstream_background="$upstream_dir/assets/bootloader/background.png"
    local upstream_limine_background="$upstream_dir/assets/bootloader/limine-background.png"
    local upstream_theme="$upstream_dir/assets/bootloader/theme.txt"
    local limine_source=""

    if ! command -v git >/dev/null 2>&1; then
        abora_error "The git command is required to fetch the latest Abora files."
        return 1
    fi

    prepare_verified_upstream "$effective_ref" || return 1

    mkdir -p "$abora_dir/plymouth" "$abora_dir/bootloader" "$abora_dir/effects" "$abora_dir/mango"
    copy_upstream_file "$upstream_dir/VERSION" "$abora_dir/VERSION"
    copy_upstream_file "$upstream_dir/nix/modules/abora-options.nix" "$abora_dir/abora-options.nix"
    if [[ -d "$upstream_dir/nix/modules/desktops" ]]; then
        rm -rf "$abora_dir/desktops"
        cp -R "$upstream_dir/nix/modules/desktops" "$abora_dir/desktops"
    fi
    copy_upstream_file "$upstream_dir/nix/modules/anix.nix" "$abora_dir/anix-module.nix"
    copy_upstream_file "$upstream_dir/scripts/abora-ui.sh" "$abora_dir/ui.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-config.sh" "$abora_dir/config.sh"
    copy_upstream_file "$upstream_dir/scripts/abora.sh" "$abora_dir/abora.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-desktop.sh" "$abora_dir/desktop.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-doctor.sh" "$abora_dir/doctor.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-recovery.sh" "$abora_dir/recovery.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-welcome.sh" "$abora_dir/welcome.sh"
    if [[ -f "$upstream_dir/scripts/abora-welcome-gui.py" ]]; then
        copy_upstream_file "$upstream_dir/scripts/abora-welcome-gui.py" "$abora_dir/welcome-gui.py"
    fi
    if [[ -f "$upstream_dir/scripts/abora-config-gui.py" ]]; then
        copy_upstream_file "$upstream_dir/scripts/abora-config-gui.py" "$abora_dir/config-gui.py"
    fi
    copy_upstream_file "$upstream_dir/scripts/anix.sh" "$abora_dir/anix.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-app-catalog.sh" "$abora_dir/app-catalog.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-apps.sh" "$abora_dir/apps.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-support-report.sh" "$abora_dir/support-report.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-hardware-test.sh" "$abora_dir/hardware-test.sh"
    if [[ -f "$upstream_dir/scripts/abora-repair-flake-purity.sh" ]]; then
        copy_upstream_file "$upstream_dir/scripts/abora-repair-flake-purity.sh" "$abora_dir/repair-flake-purity.sh"
    fi
    copy_first_existing_upstream_file \
        "$abora_dir/default-wallpaper.png" \
        "$upstream_dir/assets/wallpapers/collection/titlis-alps.jpg" \
        "$upstream_dir/assets/wallpapers/collection/tannheimer-mountains.jpg" \
        "$upstream_dir/assets/wallpapers/collection/alpine-glacier.jpg"
    copy_upstream_file "$upstream_dir/scripts/abora-desktop-profiles.sh" "$abora_dir/desktop-profiles.sh"
    copy_upstream_file "$upstream_dir/nix/modules/installed-base.nix" "$abora_dir/installed-base.nix"
    if [[ -d "$upstream_dir/assets/anix-languages" ]]; then
        rm -rf "$abora_dir/anix-languages"
        cp -R "$upstream_dir/assets/anix-languages" "$abora_dir/anix-languages"
    fi
    copy_upstream_file "$upstream_dir/scripts/abora-session-setup.sh" "$abora_dir/session-setup.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-theme-sync.sh" "$abora_dir/theme-sync.sh"
    copy_upstream_file "$upstream_dir/scripts/abora-update.sh" "$abora_dir/update.sh"
    copy_upstream_file "$upstream_dir/assets/abora-title.txt" "$abora_dir/title.txt"
    copy_upstream_file "$upstream_dir/assets/fastfetch-logo.txt" "$abora_dir/fastfetch-logo.txt"
    copy_upstream_file "$upstream_dir/assets/fastfetch-config.jsonc" "$abora_dir/fastfetch-config.jsonc"
    copy_first_existing_upstream_file \
        "$abora_dir/effects/v3StartingAbora.mp3" \
        "$upstream_dir/assets/Effects/v3StartingAbora.mp3" \
        "$upstream_dir/assets/Effects/LaunchingAbora.mp3"
    copy_upstream_file "$upstream_dir/assets/plymouth/abora.plymouth" "$abora_dir/plymouth/abora.plymouth"
    copy_upstream_file "$upstream_dir/assets/plymouth/abora.script" "$abora_dir/plymouth/abora.script"
    install_mango_config_asset
    if [[ -f "$abora_dir/mango/config.conf" ]]; then
        rewrite_installed_mango_config_paths
    fi

    if [[ ! -f "$upstream_background" || ! -f "$upstream_theme" ]]; then
        abora_error "The latest Abora bootloader assets are incomplete."
        return 1
    fi

    limine_source="$upstream_background"
    if [[ -f "$upstream_limine_background" ]]; then
        limine_source="$upstream_limine_background"
    fi

    install -Dm0644 "$upstream_background" "$abora_dir/bootloader/background.png"
    install -Dm0644 "$limine_source" "$abora_dir/bootloader/limine-background.png"
    install -Dm0644 "$upstream_theme" "$abora_dir/bootloader/theme.txt"
    mkdir -p "$abora_dir/wallpapers" "$abora_dir/themes" "$abora_dir/pkgs" "$abora_dir/tools"
    cp "$upstream_dir/assets/wallpapers/collection/"* "$abora_dir/wallpapers/"
    cp "$upstream_dir/assets/wallpaper-themes/"* "$abora_dir/themes/"
    if [[ -f "$upstream_dir/nix/pkgs/mango.nix" ]]; then
        copy_upstream_file "$upstream_dir/nix/pkgs/mango.nix" "$abora_dir/pkgs/mango.nix"
    fi
    if [[ -f "$upstream_dir/nix/pkgs/modularity.nix" ]]; then
        copy_upstream_file "$upstream_dir/nix/pkgs/modularity.nix" "$abora_dir/pkgs/modularity.nix"
    fi
    if [[ -f "$upstream_dir/nix/pkgs/moducpp-anix.nix" ]]; then
        copy_upstream_file "$upstream_dir/nix/pkgs/moducpp-anix.nix" "$abora_dir/pkgs/moducpp-anix.nix"
    fi
    if [[ -f "$upstream_dir/tools/moducpp-anix" ]]; then
        copy_upstream_file "$upstream_dir/tools/moducpp-anix" "$abora_dir/tools/moducpp-anix"
        chmod 0755 "$abora_dir/tools/moducpp-anix" 2>/dev/null || true
    fi

    if [[ ! -f "$abora_dir/apps.list" ]]; then
        : > "$abora_dir/apps.list"
    fi

    if [[ ! -f "$abora_dir/apps.nix" ]]; then
        cat > "$abora_dir/apps.nix" <<'EOF'
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
  ];
}
EOF
    fi

    drop_upstream_git_metadata
}

# ── Flake layout check ────────────────────────────────────────────────────────

# Checking syntax before ever installing a generated flake.nix over the real
# one (write_installed_flake below) is what makes that replacement safe to
# do without a human reviewing it first. The big-lock "Permission denied"
# case handles running this check as a non-root user during `abora update
# --check` (read-only path): nix-instantiate/nix eval both need to touch the
# Nix DB lock even just to parse, so a permission failure there isn't a
# real syntax problem — fall back to a plain grep for the two attributes
# every generated flake must have.
validate_flake_syntax() {
    local file="$1"
    local output=""

    if command -v nix-instantiate >/dev/null 2>&1; then
        if output="$(nix-instantiate --parse "$file" 2>&1)"; then
            return 0
        fi
        if grep -q '/nix/var/nix/db/big-lock.*Permission denied' <<<"$output"; then
            grep -q 'nixosConfigurations' "$file" && grep -q 'nixosSystem' "$file"
            return
        fi
        printf '%s\n' "$output" >&2
        return 1
    elif command -v nix >/dev/null 2>&1; then
        if output="$(nix --extra-experimental-features "nix-command" eval \
            --expr "builtins.seq (import ${file}) true" 2>&1)"; then
            return 0
        fi
        if grep -q '/nix/var/nix/db/big-lock.*Permission denied' <<<"$output"; then
            grep -q 'nixosConfigurations' "$file" && grep -q 'nixosSystem' "$file"
            return
        fi
        printf '%s\n' "$output" >&2
        return 1
    else
        grep -q 'nixosConfigurations' "$file" && grep -q 'nixosSystem' "$file"
    fi
}

# Regenerates flake.nix from scratch into a temp file, validates it, backs
# up whatever was there before, and only then does the atomic `mv` — an
# update must never leave the real flake.nix half-written or syntactically
# broken, since that would brick the very next `nixos-rebuild`/`abora update`.
write_installed_flake() {
    local flake_file="$config_dir/flake.nix"
    local flake_tmp backup timestamp
    local removed=0

    mkdir -p "$config_dir"
    flake_tmp="$(mktemp "${flake_file}.tmp.XXXXXX")"
    update_tmp_files+=("$flake_tmp")

    cat > "$flake_tmp" <<EOF
{
  description = "Abora installed system";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { nixpkgs, ... }: {
    nixosConfigurations = {
      "${flake_config_name}" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
        ];
      };
    };
  };
}
EOF

    if ! validate_flake_syntax "$flake_tmp"; then
        abora_error "Generated flake.nix failed syntax validation; keeping existing flake.nix unchanged."
        return 1
    fi

    if [[ -f "$flake_file" ]]; then
        timestamp="$(date +%Y%m%d-%H%M%S)"
        backup="${flake_file}.backup-${timestamp}"
        cp -f "$flake_file" "$backup"
        abora_info "Backed up existing flake.nix to ${backup}"
    fi

    mv -f "$flake_tmp" "$flake_file"
    for i in "${!update_tmp_files[@]}"; do
        if [[ "${update_tmp_files[$i]}" == "$flake_tmp" ]]; then
            unset 'update_tmp_files[i]'
            removed=1
            break
        fi
    done
    [[ "$removed" -eq 1 ]] || true
}

# Detects two symptoms of an older/broken installed layout: leftover
# references to a live-ISO /nix/store path or a too-deep relative path
# (both signs of the old mango-config-path bug fixed by
# rewrite_installed_mango_config_paths), or a flake that no longer evaluates
# at all. Either one triggers a rewrite of the affected files below so a
# system installed under an old installer/update version self-heals instead
# of staying permanently broken.
repair_flake_layout_if_needed() {
    local flake_file="$config_dir/flake.nix"
    local abora_dir="$config_dir/abora"
    local needs_repair=0

    if [[ ! -f "$flake_file" ]]; then
        return 0
    fi

    if grep -Eq '(/nix/store|../../nix|../../../nix|nix/pkgs/mango\.nix|nix/pkgs/modularity\.nix)' "$flake_file"; then
        needs_repair=1
    elif [[ -d "$abora_dir" ]] && grep -RIEq '(/nix/store|(\.\./){2,}assets/mango/config\.conf|(\.\./){2,}nix/|nix/(pkgs|modules)/(mango|modularity)\.nix)' "$abora_dir"; then
        needs_repair=1
    elif ! nix --extra-experimental-features "nix-command flakes" \
        eval --no-write-lock-file "$config_dir#nixosConfigurations.${flake_config_name}.config.system.name" \
        >/dev/null 2>&1; then
        needs_repair=1
    fi

    if [[ "$needs_repair" -eq 1 ]]; then
        abora_warn "Repairing the installed flake/module layout for pure evaluation."
        write_installed_flake
    fi
}

ensure_flake_layout() {
    local flake_file="$config_dir/flake.nix"
    local repair_script="$config_dir/abora/repair-flake-purity.sh"

    if [[ ! -f "$flake_file" ]]; then
        abora_warn "No flake.nix found in $config_dir — creating a flake-native Abora layout."
        write_installed_flake
    fi

    if [[ ! -f "$config_dir/abora-local.nix" ]]; then
        abora_error "Missing $config_dir/abora-local.nix."
        abora_error "Reinstall from the current Abora ISO or restore the flake-native local module."
        return 1
    fi

    if [[ -f "$repair_script" ]]; then
        bash "$repair_script" || {
            abora_error "Abora could not repair known flake-purity issues."
            return 1
        }
    fi

    repair_flake_layout_if_needed
}

# Hidden __test-* entry points let check-scripts.sh exercise these internal
# functions directly (flake writing, upstream validation, channel/ref
# resolution, pre-alpha confirmation) without going through the real
# argument-parsing/re-exec-as-root/network-fetch path below.
if [[ "${1:-}" == "__test-write-flake" ]]; then
    write_installed_flake
    validate_flake_syntax "$config_dir/flake.nix"
    exit 0
fi

if [[ "${1:-}" == "__test-validate-upstream" ]]; then
    validate_upstream_checkout "${2:?missing checkout dir}" "${3:-test-ref}"
    exit 0
fi

if [[ "${1:-}" == "__test-resolve-ref" ]]; then
    current_version="${2:-4.0}"
    channel="${3:-stable}"
    resolve_update_ref "$channel" "$current_version"
    guard_against_accidental_downgrade "$current_version" "$effective_ref"
    printf '%s\t%s\n' "$effective_ref" "$effective_ref_reason"
    exit 0
fi

if [[ "${1:-}" == "__test-resolve-fallback" ]]; then
    current_version="${2:-4.0}"
    fallback_ref="${3:-v2.5.0}"
    fallback_mode=1
    allow_downgrade=1
    resolve_update_ref "fallback" "$current_version"
    guard_against_accidental_downgrade "$current_version" "$effective_ref"
    printf '%s\t%s\n' "$effective_ref" "$effective_ref_reason"
    exit 0
fi

if [[ "${1:-}" == "__test-pre-alpha-confirm" ]]; then
    confirm_pre_alpha_risk
    exit 0
fi

# ── Command routing ───────────────────────────────────────────────────────────

case "$command_name" in
    nixos)
        case "${1:-}" in
            update | upgrade)
                command_name="update"
                shift
                ;;
            rollback)
                command_name="rollback"
                shift
                ;;
            channel)
                shift
                handle_channel_command "$@"
                exit 0
                ;;
            "" | help | -h | --help)
                usage
                exit 0
                ;;
            *)
                abora_error "Unknown nixos command: $1"
                usage >&2
                exit 1
                ;;
        esac
        ;;
esac

case "${1:-}" in
    --check|check)
        handle_check_command
        exit "$?"
        ;;
    channel)
        shift
        handle_channel_command "$@"
        exit 0
        ;;
    fallback)
        command_name="fallback"
        shift
        parse_fallback_args "$@"
        set --
        ;;
    install)
        command_name="install"
        shift
        parse_install_args "$@"
        set --
        ;;
esac

if [[ "$#" -gt 0 ]]; then
    abora_error "This command does not take extra arguments yet."
    usage >&2
    exit 1
fi

if [[ ! -d "$config_dir" && "$dry_run" -ne 1 ]]; then
    abora_error "NixOS config directory not found: $config_dir"
    exit 1
fi

# Re-exec as root, forwarding channel env vars too.
if [[ "$(id -u)" -ne 0 && "$dry_run" -ne 1 ]]; then
    run_as_root env \
        ABORA_UPDATE_COMMAND="$command_name" \
        ABORA_SYSTEM_CONFIG="$config_dir" \
        ABORA_REPO_GIT_URL="$repo_git_url" \
        ABORA_REPO_GIT_URLS="$repo_git_fallbacks" \
        ABORA_REPO_REF="$repo_ref" \
        ABORA_UPSTREAM_DIR="$upstream_dir" \
        ABORA_FLAKE_CONFIG_NAME="$flake_config_name" \
        ABORA_FALLBACK_REF="$fallback_ref" \
        ABORA_FALLBACK_MODE="$fallback_mode" \
        ABORA_ALLOW_DOWNGRADE="$allow_downgrade" \
        ABORA_PRE_ALPHA_MODE="$pre_alpha_mode" \
        ABORA_PRE_ALPHA_REF="$pre_alpha_ref" \
        ABORA_DRY_RUN="$dry_run" \
        ABORA_UI_LIB="$ui_lib" \
        bash "$script_self" "$@"
    exit 0
fi

# ── Rollback ──────────────────────────────────────────────────────────────────

if [[ "$command_name" == "rollback" ]]; then
    if ! command -v nixos-rebuild >/dev/null 2>&1; then
        abora_error "The nixos-rebuild command is not available on this system."
        exit 1
    fi

    abora_banner "System Rollback" "Reverting to the previous system generation."
    abora_step "Rolling back to the previous generation"
    printf '\n'
    nixos-rebuild switch --rollback
    printf '\n'
    abora_success "Rollback complete."
    printf '\n'
    exit 0
fi

# ── Update ────────────────────────────────────────────────────────────────────

current_version="$(installed_version)"
channel="$(read_channel)"
if [[ "$fallback_mode" -eq 1 ]]; then
    channel="fallback"
elif [[ "$pre_alpha_mode" -eq 1 || "$command_name" == "install" ]]; then
    confirm_pre_alpha_risk || exit 1
    channel="pre-alpha"
fi

resolve_update_ref "$channel" "$current_version" || exit 1
guard_against_accidental_downgrade "$current_version" "$effective_ref" || exit 1

if [[ "$channel" == "pre-alpha" ]]; then
    abora_banner "Pre-Alpha Install" "One-shot development build · Ref: ${effective_ref}"
else
    abora_banner "System Update" "Channel: ${channel}  ·  Ref: ${effective_ref}"
fi
printf '  %bCurrent installed version%b  %s\n' "$ABORA_DIM" "$ABORA_NC" "$current_version"
printf '  %bSelected channel%b           %s\n' "$ABORA_DIM" "$ABORA_NC" "$channel"
printf '  %bSelected update ref%b        %s\n' "$ABORA_DIM" "$ABORA_NC" "$effective_ref"
printf '  %bReason%b                     %s\n\n' "$ABORA_DIM" "$ABORA_NC" "$effective_ref_reason"

if [[ "$dry_run" -eq 1 ]]; then
    abora_success "Dry run complete. No files were changed and no rebuild was started."
    printf '\n'
    exit 0
fi

if ! command -v nix >/dev/null 2>&1; then
    abora_error "The nix command is not available on this system."
    exit 1
fi

if ! command -v nixos-rebuild >/dev/null 2>&1; then
    abora_error "The nixos-rebuild command is not available on this system."
    exit 1
fi

if [[ ! -d "$config_dir" ]]; then
    abora_error "NixOS config directory not found: $config_dir"
    exit 1
fi

if [[ -x "$config_dir/abora/anix.sh" ]]; then
    if confirm "Save a local ANIX snapshot before updating?"; then
        env ANIX_SYSTEM_CONFIG="$config_dir" ANIX_FLAKE_CONFIG_NAME="$flake_config_name" bash "$config_dir/abora/anix.sh" save "anix: snapshot before Abora update" || {
            abora_warn "Snapshot failed or was cancelled; continuing with update."
            printf '\n'
        }
    fi
fi

abora_wu_banner "Working on updates" "Don't turn off your computer"

abora_wu_run "Getting things ready" "/tmp/abora-update-sync.log" -- \
    sync_abora_files "$effective_ref" || {
    abora_error "Abora could not fetch the latest project files."
    exit 1
}

maybe_reexec_synced_updater

ensure_flake_layout || {
    abora_error "Abora could not prepare a flake-native system update."
    exit 1
}

abora_wu_run "Updating flake inputs" "/tmp/abora-update-flake.log" -- \
    nix --extra-experimental-features "nix-command flakes" flake update --flake "$config_dir" || exit 1

if git -C "$config_dir" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$config_dir" add -A 2>/dev/null || true
fi

abora_wu_run "Rebuilding Abora from $config_dir" "/tmp/abora-update-rebuild.log" -- \
    nixos-rebuild switch --flake "$config_dir#${flake_config_name}" || exit 1

printf '\n'
abora_success "Abora is up to date."
printf '\n'
