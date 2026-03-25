#!/usr/bin/env bash
set -euo pipefail

export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

requested_app="${1:-abora-welcome}"
shift || true
return_vt="${ABORA_RETURN_VT:-1}"

resolve_app() {
    case "$requested_app" in
        abora-center|center)
            printf '%s' "abora-center"
            ;;
        abora-welcome|welcome)
            printf '%s' "abora-welcome"
            ;;
        *)
            return 1
            ;;
    esac
}

require_command() {
    local cmd="$1"

    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    fi

    printf '%s is not available in this build.\n' "$cmd" >&2
    exit 1
}

main() {
    local app_cmd=""
    local session_script=""

    app_cmd="$(resolve_app)" || {
        printf 'Unknown Abora app target: %s\n' "$requested_app" >&2
        exit 1
    }

    if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
        exec "$app_cmd" "$@"
    fi

    require_command xinit
    require_command Xorg
    require_command openbox
    require_command xsetroot
    require_command "$app_cmd"

    session_script="$(mktemp)"
    trap 'rm -f "$session_script"' EXIT

    cat >"$session_script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\${PATH:-}"
xsetroot -solid "#0a1426" || true
openbox >/tmp/abora-openbox.log 2>&1 &
wm_pid=\$!
cleanup() {
    kill "\$wm_pid" 2>/dev/null || true
}
trap cleanup EXIT
exec ${app_cmd}
EOF

    chmod +x "$session_script"
    xinit "$session_script" -- "$(command -v Xorg)" -nolisten tcp -background none

    if command -v chvt >/dev/null 2>&1; then
        chvt "$return_vt" || true
    fi
}

main "$@"
