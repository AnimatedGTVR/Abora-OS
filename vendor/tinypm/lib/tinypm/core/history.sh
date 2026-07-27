#!/usr/bin/env bash

history_log_file="${XDG_STATE_HOME:-$HOME/.local/state}/tinypm/history.log"

ensure_history_dir() {
    mkdir -p "$(dirname "$history_log_file")"
}

record_history() {
    local action="$1"
    local package="$2"
    local provider="$3"
    local timestamp

    ensure_history_dir
    timestamp="$(date -Iseconds)"
    printf '%s\t%s\t%s\t%s\n' "$timestamp" "$action" "$package" "$provider" >> "$history_log_file"
}

print_history() {
    local limit="${1:-50}"

    if [[ ! -f "$history_log_file" ]]; then
        printf 'No install history found.\n'
        return
    fi

    printf '%-26s %-10s %-32s %s\n' "WHEN" "ACTION" "PACKAGE" "PROVIDER"
    tail -n "$limit" "$history_log_file" \
        | awk -F '\t' '{ printf "%-26s %-10s %-32s %s\n", $1, $2, $3, $4 }'
}

last_reversible_history_entry() {
    [[ -f "$history_log_file" ]] || return 1
    awk -F '\t' '
        $2 == "install" || $2 == "remove" { entry=$0 }
        END { if (entry != "") print entry; else exit 1 }
    ' "$history_log_file"
}
