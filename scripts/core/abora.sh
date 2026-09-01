#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

show_learn() {
    cat <<'EOF'
Abora quick start

Most-used commands:
  abora learn                         show this cheat sheet
  abora welcome                       open the first-steps menu
  abora doctor                        check what is broken
  abora network                       diagnose Wi-Fi, DNS, and update connectivity
  abora logs --lines 200              show recent installer/config logs
  abora bug-report                    print the bug report template
  abora bug-report --github --web     open a GitHub issue draft
  abora recovery                      rollback, repair, and support tools
  sudo abora update                   update Abora
  sudo abora rollback                 go back to the previous generation

Change the system:
  sudo abora setup                    interactive reconfiguration wizard
  abora desktop list                  show desktop choices
  sudo abora desktop set gnome        switch desktop profile
  sudo abora config set timezone America/New_York
  sudo abora config set wallpaper titlis-alps.jpg
  sudo abora config apply             rebuild after config changes

Apps and extras:
  abora apps catalog                  see app bundles
  sudo abora apps bundle gaming       install a curated app bundle
  abora apps custom list              list standalone custom packages
  sudo abora apps custom update modularity-stable --zip ~/Downloads/Modularity.zip

Gaming:
  abora gaming status                 show Steam, launchers, Wine, and helpers
  abora gaming welcome                open the Gaming first-steps app
  abora gaming doctor                 check Gaming config, GPU, Vulkan, disk space
  abora gaming repair-cache           fix local Nix fetch-cache SQLite errors
  abora gaming big-picture            open Steam Big Picture

Install, build, or repair:
  abora adopt-nixos                   add Abora to existing NixOS without wiping
  abora build --from-source           build Abora from a checkout
  abora network                       debug Wi-Fi/DNS/update connection issues
  abora logs --lines 200              show recent live install logs if present
  abora bug-report                    print the bug report template
  abora bug-report --github           create a GitHub issue with gh
  abora repair --mango                fix MangoWM config path issues
  abora support-report                make a redacted support archive

ANIX config layer:
  anix learn                          learn ANIX commands
  anix status                         show Nix/ANIX state
  anix set desktop cosmic             edit the desktop value
  anix package add fastfetch          add a package
  anix apply                          rebuild with ANIX
EOF
}

show_help() {
    cat <<'EOF'
Abora commands:
  abora learn           short cheat sheet for the commands people actually use
  abora setup           installed reconfiguration launcher
  abora welcome         first-boot welcome and quick actions
  abora welcome-gui     graphical first-steps and update-check app
  abora doctor          check Abora system health
  abora check-full      collect full ANIX, TinyPM, desktop, driver, and Nix logs
  abora build --from-source
                        clone/use source and build Abora with Nix
  abora adopt-nixos     add Abora to an existing NixOS install without wiping
  abora recovery        rollback, repair, and diagnostics menu
  abora network         diagnose Wi-Fi, DNS, and update connectivity
  abora logs [--lines N]
                        show recent live installer/config logs if present
  abora bug-report      print a copy-pasteable bug report template
  abora bug-report --github
                        create a GitHub issue using gh
  abora repair --mango  repair MangoWM flake-pure config paths
  abora desktop         view or switch desktop profiles
  abora dotfiles        import Hyprland, Sway, i3, shell, and app dotfiles
  abora gaming          gaming layer status and Steam Big Picture helper
  abora apps            install curated apps
  abora apps custom     update standalone custom packages
  abora config          view or edit installed-system settings
  abora config-gui      graphical settings editor
  abora update          update Abora
  abora channel         view or change the update channel
  abora rollback        roll back to the previous system generation
  abora install pre-alpha
                        install unfinished pre-alpha development builds
  abora fallback        intentionally switch to an older release
  abora hardware-test   run hardware readiness checks
  abora support-report  collect support diagnostics

Common recovery shortcuts:
  abora network                       same as: abora recovery network
  abora logs --lines 200              quick view of /tmp/abora-install.log
  abora bug-report                    copy-pasteable Discord/GitHub template
  abora bug-report --github --web     open a GitHub issue draft
  abora support-report                redacted archive for Discord/GitHub help
  abora build --from-source --ref edge
                                      compile Abora from the current source line
EOF
}

show_logs() {
    local shown=0
    local file
    local lines="${ABORA_LOG_LINES:-120}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lines|-n)
                [[ -n "${2:-}" && "$2" =~ ^[0-9]+$ && "$2" -gt 0 ]] || {
                    printf 'abora logs: --lines needs a positive number\n' >&2
                    return 2
                }
                lines="$2"
                shift 2
                ;;
            --help|-h)
                cat <<'EOF'
Usage:
  abora logs [--lines N]

Show recent live installer logs when present:
  /tmp/abora-install.log
  /tmp/abora-config.log
EOF
                return 0
                ;;
            *)
                printf 'abora logs: unknown argument: %s\n' "$1" >&2
                return 2
                ;;
        esac
    done

    for file in /tmp/abora-install.log /tmp/abora-config.log; do
        if [[ -r "$file" ]]; then
            printf '\n==> %s <==\n' "$file"
            tail -n "$lines" "$file"
            shown=1
        fi
    done

    if [[ "$shown" -eq 0 ]]; then
        cat <<'EOF'
No live installer logs were found at:
  /tmp/abora-install.log
  /tmp/abora-config.log

Useful next commands:
  abora network
  abora check-full
  abora support-report
EOF
    fi
}

show_bug_report_template() {
    local template="${script_dir}/../docs/bug-report-template.md"
    if [[ -r "$template" ]]; then
        cat "$template"
        return 0
    fi

    cat <<'EOF'
# Abora Bug Report Template

## Summary

What broke?

## Where It Happened

- Live ISO installer / installed system / update / first boot:
- Edition: Cosmic / Hyprland / GNOME / KDE / Other:
- Real hardware or VM:
- Wired, Wi-Fi, or offline:

## Commands To Run

```sh
abora logs --lines 200
abora network
abora support-report
```

For installed-system update or rebuild failures:

```sh
abora check-full
sudo journalctl -b --no-pager
```

Paste the exact error and attach the generated abora-support archive when possible.
Review the archive before posting publicly.
EOF
}

create_github_issue() {
    local repo="${ABORA_ISSUE_REPO:-AnimatedGTVR/Abora-OS}"
    local title=""
    local body_file=""
    local tmp_body=""
    local with_report=0
    local dry_run=0
    local web=0
    local support_archive=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)
                [[ -n "${2:-}" ]] || { printf 'abora bug-report --github: --repo needs OWNER/REPO\n' >&2; return 2; }
                repo="$2"
                shift 2
                ;;
            --title|-t)
                [[ -n "${2:-}" ]] || { printf 'abora bug-report --github: --title needs text\n' >&2; return 2; }
                title="$2"
                shift 2
                ;;
            --body-file|-F)
                [[ -n "${2:-}" && -r "$2" ]] || { printf 'abora bug-report --github: --body-file needs a readable file\n' >&2; return 2; }
                body_file="$2"
                shift 2
                ;;
            --with-support-report)
                with_report=1
                shift
                ;;
            --web)
                web=1
                shift
                ;;
            --dry-run)
                dry_run=1
                shift
                ;;
            --help|-h)
                cat <<'EOF'
Usage:
  abora bug-report --github [--title TEXT] [--repo OWNER/REPO] [--with-support-report] [--web]

Create a GitHub issue with the Abora bug report template using the GitHub CLI.

Options:
  --title TEXT            Issue title. If omitted, Abora prompts for one.
  --repo OWNER/REPO       Target repository. Default: AnimatedGTVR/Abora-OS
  --body-file FILE        Use an existing issue body file.
  --with-support-report   Create a support archive and mention its path.
  --web                   Open the issue in the browser before submitting.
  --dry-run               Print the generated issue body and stop.
EOF
                return 0
                ;;
            *)
                printf 'abora bug-report --github: unknown argument: %s\n' "$1" >&2
                return 2
                ;;
        esac
    done

    if [[ -z "$title" ]]; then
        printf 'Issue title: '
        read -r title || title=""
    fi
    [[ -n "$title" ]] || title="Abora OS bug report"

    if [[ -n "$body_file" ]]; then
        tmp_body="$body_file"
    else
        tmp_body="$(mktemp)"
        {
            show_bug_report_template
            printf '\n## Auto-Collected Pointers\n\n'
            # bash's builtin printf treats a format string starting with
            # '-' as an option flag ("printf: - : invalid option"), not
            # literal text -- confirmed directly: every one of these six
            # calls crashed the very first time it ran, under this
            # function's own `set -e`, meaning `abora bug-report --github`
            # (without --body-file) failed on every single invocation,
            # before gh was ever even reached, also leaking $tmp_body since
            # the crash happened before its cleanup below. `--` tells
            # printf "no more options follow" so the leading '-' is read as
            # ordinary text again.
            printf -- '- Command: `abora bug-report --github`\n'
            printf -- '- Logs: run `abora logs --lines 200`\n'
            printf -- '- Network diagnostics: run `abora network`\n'
            if [[ "$with_report" -eq 1 ]]; then
                support_archive="$(abora support-report 2>/dev/null || true)"
                if [[ -n "$support_archive" ]]; then
                    printf -- '- Support archive created locally: `%s`\n' "$support_archive"
                    printf '\nGitHub CLI cannot attach arbitrary files directly from this command. Drag the archive into the issue after it opens, or attach it in a follow-up comment.\n'
                else
                    printf -- '- Support archive: creation failed or was cancelled\n'
                fi
            else
                printf -- '- Support archive: run `abora support-report --output-dir ~/Desktop`\n'
            fi
        } >"$tmp_body"
    fi

    if [[ "$dry_run" -eq 1 ]]; then
        printf 'Repository: %s\n' "$repo"
        printf 'Title: %s\n\n' "$title"
        cat "$tmp_body"
        [[ "$tmp_body" == "$body_file" ]] || rm -f "$tmp_body"
        return 0
    fi

    if ! command -v gh >/dev/null 2>&1; then
        printf 'GitHub CLI (gh) is not installed.\n' >&2
        printf 'Open this URL instead: https://github.com/%s/issues/new\n\n' "$repo" >&2
        cat "$tmp_body"
        [[ "$tmp_body" == "$body_file" ]] || rm -f "$tmp_body"
        return 1
    fi

    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
        printf 'GitHub CLI is not logged in. Run: gh auth login\n' >&2
        printf 'Open this URL instead: https://github.com/%s/issues/new\n\n' "$repo" >&2
        cat "$tmp_body"
        [[ "$tmp_body" == "$body_file" ]] || rm -f "$tmp_body"
        return 1
    fi

    if [[ "$web" -eq 1 ]]; then
        gh issue create --repo "$repo" --title "$title" --body-file "$tmp_body" --web
    else
        gh issue create --repo "$repo" --title "$title" --body-file "$tmp_body"
    fi
    local rc=$?
    [[ "$tmp_body" == "$body_file" ]] || rm -f "$tmp_body"
    return "$rc"
}

case "${1:-help}" in
    learn|cheatsheet|commands)
        show_learn
        ;;
    apps)
        shift
        if command -v abora-apps >/dev/null 2>&1; then
            exec abora-apps "$@"
        fi
        exec "$script_dir/abora-apps.sh" "$@"
        ;;
    custom-packages)
        shift
        if command -v abora-custom-packages >/dev/null 2>&1; then
            exec abora-custom-packages "$@"
        fi
        exec "$script_dir/abora-custom-packages.sh" "$@"
        ;;
    config)
        shift
        exec abora-config "$@"
        ;;
    desktop)
        shift
        exec abora-desktop "$@"
        ;;
    dotfiles)
        shift
        exec abora-dotfiles-import "$@"
        ;;
    gaming)
        shift
        if command -v abora-gaming >/dev/null 2>&1; then
            exec abora-gaming "$@"
        fi
        exec "$script_dir/abora-gaming.sh" "$@"
        ;;
    doctor)
        shift
        exec abora-doctor "$@"
        ;;
    check-full)
        shift
        exec abora-check-full "$@"
        ;;
    logs|log)
        shift
        show_logs "$@"
        ;;
    bug-report|bug)
        shift
        case "${1:-}" in
            --github|github|issue)
                shift
                create_github_issue "$@"
                ;;
            --help|-h)
                cat <<'EOF'
Usage:
  abora bug-report
  abora bug-report --github [--title TEXT] [--with-support-report] [--web]

Print a copy-pasteable bug report template, or create a GitHub issue using gh.
EOF
                ;;
            "")
                show_bug_report_template
                ;;
            *)
                printf 'abora bug-report: unknown argument: %s\n' "$1" >&2
                exit 2
                ;;
        esac
        ;;
    build)
        shift
        if command -v abora-build >/dev/null 2>&1; then
            exec abora-build "$@"
        fi
        exec "$script_dir/abora-build.sh" "$@"
        ;;
    adopt-nixos|adopt)
        shift
        if command -v abora-adopt-nixos >/dev/null 2>&1; then
            exec abora-adopt-nixos "$@"
        fi
        exec "$script_dir/abora-adopt-nixos.sh" "$@"
        ;;
    recovery)
        shift
        if command -v abora-recovery >/dev/null 2>&1; then
            exec abora-recovery "$@"
        fi
        exec "$script_dir/abora-recovery.sh" "$@"
        ;;
    network)
        shift
        if command -v abora-recovery >/dev/null 2>&1; then
            exec abora-recovery network "$@"
        fi
        exec "$script_dir/abora-recovery.sh" network "$@"
        ;;
    repair)
        shift
        case "${1:-}" in
            --mango|mango)
                exec abora-repair-flake-purity --mango
                ;;
            help|--help|-h|"")
                cat <<'EOF'
Abora repair commands:
  abora repair --mango    repair MangoWM flake-pure config paths
EOF
                ;;
            *)
                printf 'Unknown Abora repair command: %s\n' "$1" >&2
                exit 1
                ;;
        esac
        ;;
    setup)
        shift
        exec abora-setup "$@"
        ;;
    welcome)
        shift
        exec abora-welcome "$@"
        ;;
    welcome-gui)
        shift
        exec abora-welcome-gui "$@"
        ;;
    config-gui)
        shift
        exec abora-config-gui "$@"
        ;;
    hardware-test)
        shift
        exec abora-hardware-test "$@"
        ;;
    support-report)
        shift
        exec abora-support-report "$@"
        ;;
    update)
        shift
        exec abora-update "$@"
        ;;
    channel)
        shift
        exec abora-update channel "$@"
        ;;
    rollback)
        shift
        exec abora-update rollback "$@"
        ;;
    fallback)
        shift
        exec abora-update fallback "$@"
        ;;
    install)
        shift
        exec abora-update install "$@"
        ;;
    help|--help|-h|"")
        show_help
        ;;
    *)
        printf 'Unknown Abora command: %s\n' "$1" >&2
        exit 1
        ;;
esac
