#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2154

doctor_fix=0
repo_name=""
packages=()
package=""
sync_generate=0
sync_output=""
history_limit=50
dry_run=0
undo_yes=0
self_update_yes=0
update_notify=0
update_quiet=0

dispatch_multicall() {
    case "$prog_name" in
        grab)          echo "install auto" ;;
        grab-add-repo) echo "add-repo auto" ;;
        grab-de)       echo "de auto" ;;
        search)        echo "search auto" ;;
        term)          echo "remove auto" ;;
        start)         echo "run auto" ;;
        supdate) echo "update auto" ;;
        syspm)         echo "help native" ;;
        *)       echo "help auto" ;;
    esac
}

grab_command_correction() {
    case "${1,,}" in
        instal|intsall|isntall) printf 'install\n' ;;
        serach|seach|saerch) printf 'search\n' ;;
        udpate|upadte|ugprade|udpgrade) printf 'update\n' ;;
        remvoe|romove|uninstal) printf 'remove\n' ;;
        explian|exlain) printf 'explain\n' ;;
        chekc|cehck) printf 'check\n' ;;
        lsit|lits) printf 'list\n' ;;
        inof) printf 'info\n' ;;
        docter|docotr) printf 'doctor\n' ;;
        hsitory|histroy) printf 'history\n' ;;
        sycn) printf 'sync\n' ;;
        dsicover|dicover) printf 'discover\n' ;;
        addrepoo|reop) printf 'add-repo\n' ;;
        *) return 1 ;;
    esac
}

parse_action_args() {
    local default_provider="$1"
    local provider_candidate=""
    shift

    provider="$default_provider"
    package=""
    repo_name=""
    packages=()
    sync_generate=0
    sync_output=""
    history_limit=50
    dry_run=0
    undo_yes=0
    self_update_yes=0
    update_notify=0
    update_quiet=0

    case "$action" in
        check-update)
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --notify) update_notify=1 ;;
                    -q|--quiet) update_quiet=1 ;;
                    *) die "unknown check-update option: $1" ;;
                esac
                shift
            done
            ;;
        self-update|selfupdate)
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    -y|--yes) self_update_yes=1 ;;
                    *) die "unknown self-update option: $1" ;;
                esac
                shift
            done
            ;;
        add-repo)
            if [[ $# -gt 0 ]] && provider="$(provider_from_flag "$1")"; then
                shift
            fi
            [[ $# -gt 0 ]] || die "add-repo requires a repository spec"
            package="$1"
            shift
            if [[ $# -gt 0 ]] && ! provider_from_flag "$1" >/dev/null 2>&1; then
                repo_name="$1"
                shift
            fi
            if [[ $# -gt 0 ]] && provider="$(provider_from_flag "$1")"; then
                shift
            fi
            [[ $# -eq 0 ]] || die "too many arguments"
            ;;
        de)
            if [[ $# -gt 0 ]] && provider="$(provider_from_flag "$1")"; then
                shift
            fi
            [[ $# -gt 0 ]] || die "de requires a desktop environment name"
            package="$1"
            shift
            if [[ $# -gt 0 ]] && provider="$(provider_from_flag "$1")"; then
                shift
            fi
            [[ $# -eq 0 ]] || die "too many arguments"
            ;;
        doctor)
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --fix|--repair)
                        doctor_fix=1
                        shift
                        ;;
                    *)
                        die "unknown doctor option: $1"
                        ;;
                esac
            done
            ;;
        selftest|managed|apps|help|version|-v|--version|pinned)
            [[ $# -eq 0 ]] || die "too many arguments"
            ;;
        check)
            if [[ $# -gt 0 ]]; then
                package="$1"
                packages=("$1")
                shift
            fi
            [[ -n "$package" ]] || die "check requires a package name"
            [[ $# -eq 0 ]] || die "too many arguments"
            ;;
        list|update|upgrade)
            if [[ $# -gt 0 ]] && provider="$(provider_from_flag "$1")"; then
                shift
            fi
            [[ $# -eq 0 ]] || die "too many arguments"
            ;;
        export-state)
            if [[ $# -gt 0 ]]; then
                package="$1"
                shift
            fi
            [[ $# -eq 0 ]] || die "too many arguments"
            ;;
        import-state)
            if [[ $# -gt 0 ]]; then
                package="$1"
                shift
            fi
            [[ -n "$package" ]] || die "import-state requires a file path"
            [[ $# -eq 0 ]] || die "too many arguments"
            ;;
        install|remove|uninstall)
            # Strip --dry-run / -d before other flag processing
            local _filtered=()
            for _a in "$@"; do
                case "$_a" in
                    --dry-run|-d) dry_run=1 ;;
                    *) _filtered+=("$_a") ;;
                esac
            done
            set -- "${_filtered[@]+"${_filtered[@]}"}"
            unset _filtered _a

            while [[ $# -gt 0 ]]; do
                if provider_candidate="$(provider_from_flag "$1" 2>/dev/null)"; then
                    provider="$provider_candidate"
                else
                    packages+=("$1")
                fi
                shift
            done
            package="${packages[0]:-}"
            ;;
        pin|unpin|info|explain|run|start)
            if [[ $# -gt 0 ]] && provider="$(provider_from_flag "$1")"; then
                shift
            fi
            if [[ $# -gt 0 ]]; then
                package="$1"
                packages=("$1")
                shift
            fi
            if [[ $# -gt 0 ]] && provider="$(provider_from_flag "$1")"; then
                shift
            fi
            [[ $# -eq 0 ]] || die "too many arguments"
            ;;
        bundle)
            if [[ $# -gt 0 ]] && provider="$(provider_from_flag "$1")"; then
                shift
            fi
            if [[ $# -gt 0 ]]; then
                package="$1"
                shift
            fi
            if [[ $# -gt 0 ]] && provider="$(provider_from_flag "$1")"; then
                shift
            fi
            [[ $# -eq 0 ]] || die "too many arguments"
            ;;
        sync)
            if [[ $# -gt 0 && "$1" == "--generate" ]]; then
                sync_generate=1
                shift
                if [[ $# -gt 0 && "$1" != -* ]]; then
                    sync_output="$1"
                    shift
                fi
            elif [[ $# -gt 0 ]]; then
                package="$1"
                shift
            fi
            [[ $# -eq 0 ]] || die "too many arguments"
            ;;
        history)
            if [[ $# -gt 0 ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
                history_limit="$1"
                shift
            fi
            [[ $# -eq 0 ]] || die "too many arguments"
            ;;
        undo)
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    -y|--yes) undo_yes=1 ;;
                    -d|--dry-run) ;;
                    *) die "unknown undo option: $1" ;;
                esac
                shift
            done
            ;;
        discover)
            if [[ $# -gt 0 ]]; then
                package="$1"
                shift
            fi
            [[ $# -eq 0 ]] || die "too many arguments"
            ;;
        *)
            if [[ $# -gt 0 ]] && provider="$(provider_from_flag "$1")"; then
                shift
            fi

            if [[ $# -gt 0 ]]; then
                package="$1"
                packages=("$1")
                shift
            fi

            if [[ $# -gt 0 ]] && provider="$(provider_from_flag "$1")"; then
                shift
            fi

            [[ $# -eq 0 ]] || die "too many arguments"
            ;;
    esac
}

init_cli_context() {
    if [[ "$prog_name" == "grab" ]]; then
        local correction=""
        if [[ "${1:-}" == "--" ]]; then
            shift
            action="install"
            parse_action_args "auto" "$@"
            return
        fi
        correction="$(grab_command_correction "${1:-}" 2>/dev/null || true)"
        if [[ -n "$correction" ]]; then
            ui_error "unknown command: $1"
            printf '  Did you mean: grab %s' "$correction" >&2
            [[ $# -le 1 ]] || printf ' %s' "${@:2}" >&2
            printf '\n  To install a package literally named %s: grab -- %s\n' "$1" "$1" >&2
            exit 2
        fi
        case "${1:-}" in
            ""|help|-h|--help) action="help" ;;
            version|-v|--version) action="version" ;;
            install|add|get|i) action="install" ;;
            search|find|s) action="search" ;;
            remove|rm|uninstall|r) action="remove" ;;
            update|upgrade|up|u) action="update" ;;
            list|ls|l) action="list" ;;
            info|explain|check|run|start|managed|apps|discover|pin|unpin|pinned|bundle|sync|history|undo|doctor|selftest|check-update|self-update|selfupdate|export-state|import-state)
                action="$1"
                ;;
            repo|add-repo|addrepo) action="add-repo" ;;
            de) action="de" ;;
            *) action="install" ;;
        esac
        # Installation remains the default (`grab firefox`), but an explicit
        # `grab install firefox` consumes the command word like other actions.
        if [[ "$action" != "install" || "${1:-}" == "install" || "${1:-}" == "add" || "${1:-}" == "get" || "${1:-}" == "i" ]]; then
            shift || true
        fi
        parse_action_args "auto" "$@"
        return
    fi

    if [[ "$prog_name" == "grab-add-repo" ]]; then
        case "${1:-}" in
            ""|help|-h|--help) action="help" ;;
            version|-v|--version) action="version" ;;
            *) action="add-repo" ;;
        esac
        if [[ "$action" != "add-repo" ]]; then
            shift || true
        fi
        parse_action_args "auto" "$@"
        return
    fi

    if [[ "$prog_name" == "grab-de" ]]; then
        case "${1:-}" in
            ""|help|-h|--help) action="help" ;;
            version|-v|--version) action="version" ;;
            *) action="de" ;;
        esac
        if [[ "$action" != "de" ]]; then
            shift || true
        fi
        parse_action_args "auto" "$@"
        return
    fi

    if [[ "$prog_name" == "tiny" || "$prog_name" == "tinypm" ]]; then
        action="${1:-help}"
        case "$action" in
            i)              action="install" ;;
            s)              action="search" ;;
            r|rm|del)       action="remove" ;;
            u|up|upgrade)   action="update" ;;
            l|ls)           action="list" ;;
            v)              action="version" ;;
            st)             action="start" ;;
            addrepo|add-repo) action="add-repo" ;;
            de)             action="de" ;;
            h|hist)         action="history" ;;
            p)              action="pin" ;;
            b)              action="bundle" ;;
            c|chk)          action="check" ;;
            cu)             action="check-update" ;;
            su)             action="self-update" ;;
        esac
        shift || true
        parse_action_args "auto" "$@"
        return
    fi

    if [[ "$prog_name" == "syspm" ]]; then
        action="${1:-help}"
        case "$action" in
            ""|help|-h|--help) action="help" ;;
            version|-v|--version) action="version" ;;
            i|install|add|get) action="install" ;;
            s|search|find) action="search" ;;
            r|rm|remove|uninstall) action="remove" ;;
            u|up|update|upgrade) action="update" ;;
            l|ls|list) action="list" ;;
            info|explain|check|managed|apps|discover|pin|unpin|pinned|bundle|sync|history|undo|doctor|selftest|export-state|import-state) ;;
            *) action="install" ;;
        esac
        if [[ "$action" != "install" \
              || "${1:-}" == "install" \
              || "${1:-}" == "add" \
              || "${1:-}" == "get" \
              || "${1:-}" == "i" ]]; then
            shift || true
        fi
        parse_action_args "native" "$@"
        return
    fi

    read -r action provider < <(dispatch_multicall)
    parse_action_args "$provider" "$@"
}
