#!/usr/bin/env bash

state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
state_root="$state_home/tinypm"
state_db="$state_root/packages.tsv"

ensure_state_dir() {
    mkdir -p "$state_root"
}

state_db_exists() {
    [[ -f "$state_db" ]]
}

active_state_db() {
    printf '%s\n' "$state_db"
}

tracked_provider_for() {
    local package="$1"

    state_db_exists || return 1
    awk -F '\t' -v pkg="$package" '$1 == pkg { print $2; found=1 } END { exit(found ? 0 : 1) }' "$state_db"
}

tracked_timestamp_for() {
    local package="$1"

    state_db_exists || return 1
    awk -F '\t' -v pkg="$package" '$1 == pkg { print $3; found=1 } END { exit(found ? 0 : 1) }' "$state_db"
}

record_tracked_package() {
    local package="$1"
    local provider="$2"
    local added_at
    local tmp_file

    ensure_state_dir
    added_at="$(date -Iseconds)"
    tmp_file="$(mktemp)"

    if [[ -f "$state_db" ]]; then
        awk -F '\t' -v pkg="$package" '$1 != pkg' "$state_db" >"$tmp_file"
    fi

    printf '%s\t%s\t%s\n' "$package" "$provider" "$added_at" >>"$tmp_file"
    mv "$tmp_file" "$state_db"
}

forget_tracked_package() {
    local package="$1"
    local tmp_file

    state_db_exists || return 0
    tmp_file="$(mktemp)"
    awk -F '\t' -v pkg="$package" '$1 != pkg' "$state_db" >"$tmp_file"
    mv "$tmp_file" "$state_db"
}

print_tracked_packages() {
    if ! state_db_exists; then
        echo "No packages are currently tracked by Parcel."
        return
    fi

    awk -F '\t' 'BEGIN { printf "%-40s %-10s %s\n", "PACKAGE", "PROVIDER", "ADDED" } { printf "%-40s %-10s %s\n", $1, $2, $3 }' "$state_db"
}

tracked_package_count() {
    state_db_exists || {
        printf '%s\n' "0"
        return
    }

    awk 'END { print NR+0 }' "$state_db"
}

state_export() {
    local destination="${1:-$PWD/tinypm-state-$(date +%Y%m%d-%H%M%S).tsv}"

    ensure_state_dir

    if [[ -f "$state_db" ]]; then
        cp -f "$state_db" "$destination"
    else
        : > "$destination"
    fi

    printf 'Exported Parcel state to %s\n' "$destination"
}

state_import() {
    local source="$1"
    local tmp_file

    [[ -f "$source" ]] || die "state import file not found: $source"

    tmp_file="$(mktemp)"
    if ! awk -F '\t' 'NF==0 || NF==3' "$source" >"$tmp_file"; then
        rm -f "$tmp_file"
        die "invalid state file format: expected tab-separated PACKAGE\tPROVIDER\tADDED"
    fi

    ensure_state_dir
    mv "$tmp_file" "$state_db"
    printf 'Imported Parcel state from %s\n' "$source"
}
