#!/usr/bin/env bash
set -euo pipefail

action="$(mint abora welcome)"
if [[ "$action" == "live" ]]; then
  mint log --level info "staying in Abora OS live media"
  exit 0
fi

edition="$(mint abora edition)"

if [[ "${1:-}" == "pre-alpha" ]]; then
  mint abora risk
fi

mint abora summary --edition "$edition" --desktop "$edition" --hostname abora-live --disk "${ABORA_INSTALL_DISK:-not selected}"

mint spin \
  --spinner dot \
  --title "Preparing Abora OS ${edition} install..." \
  -- sleep 1

mint log --level info "selected Abora OS edition" edition "$edition"
