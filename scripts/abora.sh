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
    help|--help|-h|"")
        cat <<'EOF'
Abora commands:
  abora welcome          first-boot welcome and quick actions
  abora doctor           check Abora system health
  abora check-full       collect full ANIX, TinyPM, desktop, driver, and Nix logs
  abora recovery         rollback, repair, and diagnostics menu
  abora repair --mango   repair MangoWM flake-pure config paths
  abora desktop          view or switch desktop profiles
  abora apps             install curated apps
  abora config           view or edit installed-system settings
  abora update           update Abora
  abora hardware-test    run hardware readiness checks
  abora support-report   collect support diagnostics
EOF
        ;;
    *)
        printf 'Unknown Abora command: %s\n' "$1" >&2
        exit 1
        ;;
esac
