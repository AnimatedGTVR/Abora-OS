#!/usr/bin/env bash

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
tinypm_config_dir="$config_home/tinypm"
tinypm_config_file="$tinypm_config_dir/config"

ensure_config_dir() {
    mkdir -p "$tinypm_config_dir"
}

tinypm_config_get() {
    local key="$1"

    [[ -r "$tinypm_config_file" ]] || return 1
    awk -F '=' -v key="$key" '$1 == key { print $2; found=1; exit } END { exit(found ? 0 : 1) }' "$tinypm_config_file"
}

tinypm_config_set() {
    local key="$1"
    local value="$2"
    local tmp_file

    ensure_config_dir
    tmp_file="$(mktemp)"

    if [[ -r "$tinypm_config_file" ]]; then
        awk -F '=' -v key="$key" '$1 != key { print $0 }' "$tinypm_config_file" >"$tmp_file"
    fi

    printf '%s=%s\n' "$key" "$value" >>"$tmp_file"
    mv "$tmp_file" "$tinypm_config_file"
}
