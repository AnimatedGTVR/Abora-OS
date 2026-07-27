#!/usr/bin/env bash
set -euo pipefail

case "${1:-help}" in
    apps)
        shift
        exec abora-apps "$@"
        ;;
    config)
        shift
        exec abora-config "$@"
        ;;
    desktop)
        shift
        exec abora-desktop "$@"
        ;;
    doctor)
        shift
        exec abora-doctor "$@"
        ;;
    check-full)
        shift
        exec abora-check-full "$@"
        ;;
    recovery)
        shift
        exec abora-recovery "$@"
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
        exec env ABORA_UPDATE_COMMAND=nixos abora-update channel "$@"
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
        cat <<'EOF'
Abora commands:
  abora welcome          first-boot welcome and quick actions
  abora welcome-gui      graphical first-steps and update-check app
  abora doctor           check Abora system health
  abora check-full       collect full ANIX, TinyPM, desktop, driver, and Nix logs
  abora recovery         rollback, repair, and diagnostics menu
  abora repair --mango   repair MangoWM flake-pure config paths
  abora desktop          view or switch desktop profiles
  abora apps             install curated apps
  abora config           view or edit installed-system settings
  abora config-gui       graphical settings editor
  abora update           update Abora
  abora channel          view or change the update channel
  abora rollback         roll back to the previous system generation
  abora install pre-alpha
                         install unfinished pre-alpha development builds
  abora fallback         intentionally switch to an older release
  abora hardware-test    run hardware readiness checks
  abora support-report   collect support diagnostics
EOF
        ;;
    *)
        printf 'Unknown Abora command: %s\n' "$1" >&2
        exit 1
        ;;
esac
