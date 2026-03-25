#!/usr/bin/env bash
# shellcheck disable=SC2016

catalog_entries() {
    cat "$(tinypm_catalog_file)"
}

installed_apps() {
    backend_run sh -lc '
for app_dir in /usr/share/applications "$HOME/.local/share/applications"; do
    [ -d "$app_dir" ] || continue
    find "$app_dir" -maxdepth 1 -type f -name "*.desktop" | while IFS= read -r file; do
        nodisplay=$(awk -F= '\''$1=="NoDisplay" { print $2; exit }'\'' "$file")
        [ "$nodisplay" = "true" ] && continue
        name=$(awk -F= '\''$1=="Name" { print $2; exit }'\'' "$file")
        exec_line=$(awk -F= '\''$1=="Exec" { print $2; exit }'\'' "$file")
        [ -n "$name" ] && printf "%s\t%s\t%s\n" "$name" "${file##*/}" "$exec_line"
    done
done | sort -f -u'
}

installed_app_count() {
    { installed_apps 2>/dev/null || true; } | awk 'END { print NR+0 }'
}

catalog_count() {
    catalog_entries | awk 'END { print NR+0 }'
}

discover_apps() {
    local query="${1:-}"

    printf "%-22s %-14s %-8s %-32s %s\n" "NAME" "CATEGORY" "SOURCE" "PACKAGE" "DESCRIPTION"
    if [[ -z "$query" ]]; then
        catalog_entries | awk -F '\t' '{ printf "%-22s %-14s %-8s %-32s %s\n", $1, $2, $3, $4, $5 }'
        return
    fi

    catalog_entries | awk -F '\t' -v q="$query" '
        BEGIN { q=tolower(q) }
        {
            line=tolower($0)
            if (index(line, q) > 0) {
                printf "%-22s %-14s %-8s %-32s %s\n", $1, $2, $3, $4, $5
            }
        }'
}

launch_desktop_app() {
    local desktop_id="$1"

    if host_has_cmd gtk-launch; then
        host_run gtk-launch "$desktop_id"
        return
    fi

    die "gtk-launch is not installed"
}
