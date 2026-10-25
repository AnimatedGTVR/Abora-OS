#!/usr/bin/env bash
# Tests the installer's timezone question (ask_timezone and its helpers in
# abora-installer.sh): UTC and Region/City names work in any case, and a name
# that isn't a zone gets matching suggestions instead of a bare "invalid".
# DistroWatch's 4.0 review hit this: it wasn't clear what the prompt accepted.
set -euo pipefail
# shellcheck source=../../release/bash-testlib.sh
source "$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../release" && pwd)/bash-testlib.sh"

installer="$repo_dir/scripts/install/abora-installer.sh"
for fn in safe_timezone normalize_timezone timezone_exists list_timezones canonical_timezone timezone_suggestions ask_timezone; do
  body="$(sed -n "/^${fn}()[[:space:]]*{/,/^}/p" "$installer")"
  [[ "$fn" == safe_timezone ]] && body="$(grep -m1 '^safe_timezone()' "$installer")"
  if [[ -z "$body" ]]; then
    fail "runtime: installer defines ${fn}"
    testlib_finish
  fi
  eval "$body"
done

zoneinfo="$tmp_ok/zoneinfo"
mkdir -p "$zoneinfo/Europe" "$zoneinfo/America" "$zoneinfo/America/Argentina" "$zoneinfo/posix/Europe"
touch "$zoneinfo/UTC" "$zoneinfo/Europe/Berlin" "$zoneinfo/Europe/London" "$zoneinfo/America/New_York" \
  "$zoneinfo/America/Argentina/Buenos_Aires" "$zoneinfo/posix/Europe/Berlin" "$zoneinfo/zone1970.tab"
export ABORA_ZONEINFO_PATH="$zoneinfo"
# Force the zoneinfo path even where the host has timedatectl.
timedatectl() { return 1; }

if [[ "$(canonical_timezone europe/berlin)" == "Europe/Berlin" && "$(canonical_timezone 'AMERICA/NEW_YORK')" == "America/New_York" \
  && "$(canonical_timezone Europe/London)" == "Europe/London" && "$(canonical_timezone 'not/a zone')" == "not/a zone" ]]; then
  pass "runtime: installer fixes the capitalization of a real timezone name"
else
  fail "runtime: installer fixes the capitalization of a real timezone name"
fi

_berlin="$(timezone_suggestions Berlin)"
_ny="$(timezone_suggestions 'new york')"
_aires="$(timezone_suggestions aires)"
if [[ "$_berlin" == "Europe/Berlin" && "$_ny" == "America/New_York" && "$_aires" == "America/Argentina/Buenos_Aires" ]] \
  && ! list_timezones | grep -q -e '^posix/' -e '\.tab$'; then
  pass "runtime: installer suggests zone names for a city typed on its own"
else
  fail "runtime: installer suggests zone names for a city typed on its own"
  printf '              got: [%s] [%s] [%s]\n' "$_berlin" "$_ny" "$_aires"
fi

# ask_timezone, driven by a scripted prompt: a city alone, then a wrong-case
# full name. It must suggest, then accept the second answer.
_answers=("Berlin" "europe/berlin")
msg() { printf 'MSG %s\n' "$1"; }
warn() { printf 'WARN %s\n' "$1"; }
timezone_value="UTC"
_ask_out="$(
  # prompt_field runs in a subshell, so count answers through a file.
  prompt_field() { local n; n="$(cat "$tmp_ok/asked" 2>/dev/null || echo 0)"; echo $((n + 1)) > "$tmp_ok/asked"; printf '%s\n' "${_answers[$n]}"; }
  ask_timezone
  printf 'RESULT %s\n' "$timezone_value"
)"
if grep -q 'MSG Timezone: type UTC, or a Region/City name' <<<"$_ask_out" \
  && grep -q "WARN \"Berlin\" isn't a timezone name on its own. Did you mean" <<<"$_ask_out" \
  && grep -q '^      Europe/Berlin$' <<<"$_ask_out" \
  && grep -q '^RESULT Europe/Berlin$' <<<"$_ask_out"; then
  pass "runtime: installer timezone prompt explains what it accepts and suggests matches"
else
  fail "runtime: installer timezone prompt explains what it accepts and suggests matches"
  printf '%s\n' "$_ask_out" | sed 's/^/              /'
fi

testlib_finish
