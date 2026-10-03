#!/usr/bin/env bash
# Tests console_keymap_to_xkb, the mapping from a console keymap name (jp106, uk, trq...) to the graphical
# keyboard layout name (jp, gb, tr...). Passing the console name through unchanged leaves the desktop with an
# invalid layout (for example "jp106"), which is the Japanese-keyboard bug from issue #33.
#
# Run: bash scripts/install/tests/keyboard-layout.test.sh
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
installer="$root/scripts/install/abora-installer.sh"
config="$root/scripts/config/abora-config.sh"
gui="$root/scripts/install/abora-installer-gui.py"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
pass() { printf 'ok:   %s\n' "$*"; }

# Pull just the function out of a script (running a whole installer in a test would be a bad idea).
extract() { sed -n '/^console_keymap_to_xkb() {/,/^}/p' "$1"; }

installer_fn="$(extract "$installer")"
config_fn="$(extract "$config")"

[[ -n "$installer_fn" ]] || { fail "console_keymap_to_xkb not found in abora-installer.sh"; exit 1; }
[[ -n "$config_fn" ]] || { fail "console_keymap_to_xkb not found in abora-config.sh"; exit 1; }

# The two copies must be identical, so they can't drift apart.
if [[ "$installer_fn" == "$config_fn" ]]; then
    pass "installer and config tool use the same mapping"
else
    fail "the copies of console_keymap_to_xkb in abora-installer.sh and abora-config.sh differ"
fi

eval "$installer_fn"

expect() {
    local keymap="$1" want="$2" got
    got="$(console_keymap_to_xkb "$keymap")"
    if [[ "$got" == "$want" ]]; then pass "$keymap -> $want"; else fail "$keymap -> '$got' (wanted '$want')"; fi
}

# The reported bug: Japanese.
expect jp106 jp
# The other keyboards whose console name differs from the layout name.
expect uk gb
expect br-abnt2 br
expect sv-latin1 se
expect trq tr
expect pt-latin1 pt
# A -latin1 / -lat2 suffix is an encoding, not part of the layout.
expect de-latin1 de
expect fr-latin1 fr
expect cz-lat2 cz
# Names that are already layouts stay as they are.
for same in us de fr es it ru pl nl kr; do expect "$same" "$same"; done

# The GUI installer keeps its own table of (console keymap, layout, label). Every pair in it where the console
# keymap really is the layout's keymap must agree with this function. (Entries that use the "us" console map
# for a language with no console keymap, like Chinese and Korean, are skipped.)
checked=0
while IFS="'" read -r _ console _ layout _; do
    [[ -n "$console" && -n "$layout" && "$console" != "us" ]] || continue
    checked=$((checked + 1))
    got="$(console_keymap_to_xkb "$console")"
    if [[ "$got" == "$layout" ]]; then pass "GUI table: $console -> $layout"; else fail "GUI table says $console -> $layout but the shell mapping gives '$got'"; fi
done < <(sed -n '/^KEYBOARDS = \[/,/^\]/p' "$gui" | grep "^    ('")
[[ "$checked" -ge 8 ]] || fail "expected to check at least 8 entries from the GUI installer's KEYBOARDS table, checked $checked"

if [[ "$failures" -eq 0 ]]; then
    printf '\nAll keyboard layout checks passed.\n'
else
    printf '\n%d check(s) failed.\n' "$failures"
    exit 1
fi
