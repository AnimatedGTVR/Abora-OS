# TinyPM command completion for Bash.
_tinypm_complete() {
    local current previous commands providers options
    current="${COMP_WORDS[COMP_CWORD]}"
    previous="${COMP_WORDS[COMP_CWORD-1]:-}"
    commands="install search remove update upgrade list info check explain run managed apps discover pin unpin pinned bundle sync history undo doctor selftest export-state import-state add-repo de help version"
    providers="--native --flatpak --snap --apk --apt --dnf --pacman --xbps --zypper --emerge --eopkg --swupd --slackpkg --opkg --urpmi --guix --brew --nix"
    options="--dry-run --help --version"

    case "$previous" in
        bundle) COMPREPLY=( $(compgen -W "list Gaming Internet Multimedia Office Development System" -- "$current") ); return ;;
        de) COMPREPLY=( $(compgen -W "cosmic gnome plasma xfce" -- "$current") ); return ;;
        doctor) COMPREPLY=( $(compgen -W "--fix" -- "$current") ); return ;;
        undo) COMPREPLY=( $(compgen -W "--dry-run --yes" -- "$current") ); return ;;
    esac

    if [[ "$current" == -* ]]; then
        COMPREPLY=( $(compgen -W "$providers $options" -- "$current") )
    elif [[ "$COMP_CWORD" -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$commands $providers $options" -- "$current") )
    else
        COMPREPLY=()
    fi
}

complete -F _tinypm_complete tinypm tiny grab grab-add-repo grab-de syspm
