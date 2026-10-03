#!/usr/bin/env bash
# bash-testlib.sh — shared setup for the Bash behaviour-test suites.
# Source this file; do not execute it directly.
#
# Every scripts/<category>/tests/*.test.sh sources this. The suites test Bash
# tools, so they are Bash too; each one moves to its tool's new language when
# that tool is ported, and this file goes when the last suite does.
#
# scripts/check-scripts.py runs the suites. It builds the C# tools first and
# passes them in ABORA_TEST_RESOLVER_BIN and ABORA_TEST_PLAN_TOOL_BIN (empty
# when dotnet is unavailable, which the suites treat as "skip").
#
# Provides: repo_dir (and cd's there), release_tag, resolver_bin,
# plan_tool_bin, pass/fail, tmp_ok/tmp_empty scratch directories removed on
# exit (append more to testlib_cleanup_paths), and testlib_finish.

repo_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_dir"

version_value="$(tr -d '\n' < VERSION | tr -cd '[:alnum:]._-')"
case "$version_value" in
  [Vv]*) release_tag="$version_value" ;;
  *) release_tag="v$version_value" ;;
esac

resolver_bin="${ABORA_TEST_RESOLVER_BIN:-}"
plan_tool_bin="${ABORA_TEST_PLAN_TOOL_BIN:-}"

failed=0

pass() {
  printf '[ok]   %s\n' "$1"
}

fail() {
  printf '[fail] %s\n' "$1"
  failed=1
}

tmp_ok="$(mktemp -d)"
tmp_empty="$(mktemp -d)"
testlib_cleanup_paths=("$tmp_ok" "$tmp_empty")
trap 'rm -rf "${testlib_cleanup_paths[@]}"' EXIT

# Ends the suite: exit status 1 if any check failed.
testlib_finish() {
  if [[ "$failed" -ne 0 ]]; then
    exit 1
  fi
  exit 0
}
