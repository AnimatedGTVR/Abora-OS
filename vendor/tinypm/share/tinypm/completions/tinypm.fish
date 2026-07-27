set -l tinypm_commands install search remove update upgrade list info check explain run managed apps discover pin unpin pinned bundle sync history undo doctor selftest export-state import-state add-repo de help version
set -l tinypm_providers native flatpak snap apk apt dnf pacman xbps zypper emerge eopkg swupd slackpkg opkg urpmi guix brew nix

for command in tinypm tiny grab grab-add-repo grab-de syspm
    complete -c $command -f
    complete -c $command -n '__fish_use_subcommand' -a "$tinypm_commands"
    complete -c $command -s d -l dry-run -d 'Preview without changing the system'
    complete -c $command -s h -l help -d 'Show help'
    complete -c $command -l version -d 'Show version'
    for provider in $tinypm_providers
        complete -c $command -l $provider -d "Use the $provider provider"
    end
    complete -c $command -n '__fish_seen_subcommand_from de' -a 'cosmic gnome plasma xfce'
    complete -c $command -n '__fish_seen_subcommand_from doctor' -l fix -d 'Repair detected issues'
    complete -c $command -n '__fish_seen_subcommand_from undo' -s y -l yes -d 'Execute the previewed reversal'
end
