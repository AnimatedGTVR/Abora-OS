#!/usr/bin/env bash
# Tests hash_password from abora-installer.sh: it must give a SHA-512 crypt hash ($6$...) that really matches the
# password, for ordinary and awkward passwords, and keep working when openssl is missing (fallbacks).
# Run: bash scripts/install/tests/password-hash.test.sh
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fn="$(sed -n '/^hash_password() {/,/^}/p' "$root/scripts/install/abora-installer.sh")"
[[ -n "$fn" ]] || { echo "[fail] hash_password not found"; exit 1; }
eval "$fn"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
pass() { printf 'ok:   %s\n' "$*"; }

# Checks the hash with openssl using the hash's own salt (skipped if openssl is absent).
matches() {
    local pw="$1" hash="$2" salt
    command -v openssl >/dev/null 2>&1 || return 0
    salt="${hash#\$6\$}"; salt="${salt%%\$*}"
    [[ "$(openssl passwd -6 -salt "$salt" -stdin <<<"$pw")" == "$hash" ]]
}

check() {
    local name="$1" pw="$2" h
    h="$(hash_password "$pw")" || { fail "$name: hash_password failed"; return; }
    [[ "$h" == '$6$'* ]] || { fail "$name: not a \$6\$ hash: $h"; return; }
    matches "$pw" "$h" && pass "$name" || fail "$name: hash does not match the password"
}

check "simple" "hunter2"
check "spaces" "pass word with spaces"
check "dollar and quotes" "pa\$\$w0rd'\"\`x"
check "starts with dash" "-abc"
check "unicode" "pässwörd-日本語"
check "long" "$(printf 'x%.0s' $(seq 1 200))"

# Empty password gives no hash (callers treat that as an error).
if hash_password "" >/dev/null 2>&1; then fail "empty password should not hash"; else pass "empty password is refused"; fi

# Without openssl on PATH the fallbacks must still produce a valid hash (needs mkpasswd or python3 with crypt).
if command -v mkpasswd >/dev/null 2>&1 || python3 -c 'import crypt' >/dev/null 2>&1; then
    h="$(PATH="$(dirname "$(command -v python3)"):$(dirname "$(command -v mkpasswd 2>/dev/null || echo /bin/true)")" bash -c "$fn; hash_password 'fallback pw'")"
    [[ "$h" == '$6$'* ]] && pass "works without openssl on PATH" || fail "no hash without openssl: '$h'"
else
    echo "skip: no fallback tool here"
fi

[[ "$failures" -eq 0 ]] && printf '\nAll password hash checks passed.\n' || { printf '\n%d failed.\n' "$failures"; exit 1; }
