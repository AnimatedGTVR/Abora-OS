#!/usr/bin/env bash
# check-all-files.sh — glob-based repo sweep, independent of check-scripts.sh's
# hardcoded file lists. Walks every .sh, .nix, .py, and .md file actually on
# disk (skipping out/, .git/, and vendor/) and validates each by type, so a
# new file that nobody registered anywhere still gets checked.
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_dir"

failed=0
sh_count=0
nix_count=0
py_count=0
md_count=0

pass() {
    printf '[ok]   %s\n' "$1"
}

fail() {
    printf '[fail] %s\n' "$1"
    failed=1
}

# Find files by extension, excluding generated output, git internals, and
# vendored third-party code (vendor/ has its own upstream conventions).
find_files() {
    local ext="$1"
    find . \
        \( -path './out' -o -path './.git' -o -path './vendor' \) -prune -o \
        -type f -name "*.${ext}" -print \
        | sed 's|^\./||' | sort
}

# ── Shell scripts ────────────────────────────────────────────────────────────

check_shell() {
    local file="$1"
    sh_count=$((sh_count + 1))

    if bash -n "$file" 2>/dev/null; then
        pass "syntax (bash): $file"
    else
        fail "syntax (bash): $file"
        return
    fi

    if command -v shellcheck >/dev/null 2>&1; then
        if shellcheck -e SC1091 "$file" >/dev/null 2>&1; then
            pass "shellcheck: $file"
        else
            fail "shellcheck: $file"
        fi
    fi
}

# ── Nix files ─────────────────────────────────────────────────────────────────

check_nix() {
    local file="$1"
    nix_count=$((nix_count + 1))

    if ! command -v nix-instantiate >/dev/null 2>&1; then
        return
    fi

    if nix-instantiate --parse "$file" >/dev/null 2>&1; then
        pass "parse (nix): $file"
    else
        fail "parse (nix): $file"
    fi
}

# ── Python files ──────────────────────────────────────────────────────────────

check_python() {
    local file="$1"
    py_count=$((py_count + 1))

    local python_bin=""
    if command -v python3 >/dev/null 2>&1; then
        python_bin="python3"
    elif command -v python >/dev/null 2>&1; then
        python_bin="python"
    else
        return
    fi

    if "$python_bin" -m py_compile "$file" 2>/dev/null; then
        pass "compile (python): $file"
    else
        fail "compile (python): $file"
    fi
}

# ── Markdown files ────────────────────────────────────────────────────────────
# Only checks relative links to other files in this repo (e.g. [x](Foo.md) or
# [x](../docs/Foo.md)). External URLs, anchors (#section), and mailto: links
# are intentionally skipped — this is a repo-file-existence check, not a full
# link validator.

check_markdown_links() {
    local file="$1"
    md_count=$((md_count + 1))

    local dir broken=0
    dir="$(dirname -- "$file")"

    local link
    while IFS= read -r link; do
        [[ -n "$link" ]] || continue
        # Strip a trailing #anchor, if any.
        local target="${link%%#*}"
        [[ -n "$target" ]] || continue
        case "$target" in
            http://*|https://*|mailto:*) continue ;;
        esac
        local resolved="$dir/$target"
        if [[ ! -e "$resolved" ]]; then
            printf '  broken link: %s -> %s\n' "$file" "$link"
            broken=1
        fi
    done < <(grep -oE '\]\([^)]+\)' "$file" 2>/dev/null | sed -E 's/^\]\((.*)\)$/\1/')

    if [[ "$broken" -eq 0 ]]; then
        pass "links: $file"
    else
        fail "links: $file"
    fi
}

# ── Run ───────────────────────────────────────────────────────────────────────

printf 'Shell scripts\n'
if ! command -v shellcheck >/dev/null 2>&1; then
    printf '[ok]   shellcheck unavailable (lint checks skipped, syntax checks still run)\n'
fi
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    check_shell "$f"
done < <(find_files sh)

printf '\nNix files\n'
if ! command -v nix-instantiate >/dev/null 2>&1; then
    printf '[ok]   nix-instantiate unavailable (nix parse checks skipped)\n'
fi
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    check_nix "$f"
done < <(find_files nix)

printf '\nPython files\n'
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    check_python "$f"
done < <(find_files py)

printf '\nMarkdown files (relative link check)\n'
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    check_markdown_links "$f"
done < <(find_files md)

printf '\n%d shell, %d nix, %d python, %d markdown files checked.\n' \
    "$sh_count" "$nix_count" "$py_count" "$md_count"

if [[ "$failed" -ne 0 ]]; then
    printf '\nOne or more checks failed.\n' >&2
    exit 1
fi

printf '\nAll files passed.\n'
