#!/usr/bin/env bash
# check-all-files.sh — glob-based repo sweep, independent of check-scripts.sh's
# hardcoded file lists. Walks every .sh, .nix, .py, and .md file actually on
# disk (skipping out/, .git/, and vendor/) and validates each by type, plus
# every extensionless-but-shebanged script (e.g. tools/moducpp-anix) and
# every ANIX v2 source file (.anix/.mko/.moducpp) via `anix diff-plan`, so a
# new file that nobody registered anywhere still gets checked.
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_dir"

failed=0
warned=0
sh_count=0
nix_count=0
py_count=0
md_count=0
orphan_count=0
anix_count=0
anix_skipped=0

pass() {
    printf '[ok]   %s\n' "$1"
}

fail() {
    printf '[fail] %s\n' "$1"
    failed=1
}

warn() {
    printf '[warn] %s\n' "$1"
    warned=1
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

# Find executable files with no extension but a #!/.../bash or #!/.../sh
# shebang — e.g. tools/moducpp-anix. These are real shell scripts that
# `find_files sh` can't see by name alone.
find_shebang_scripts() {
    find . \
        \( -path './out' -o -path './.git' -o -path './vendor' \) -prune -o \
        -type f -executable ! -name '*.*' -print 2>/dev/null \
        | sed 's|^\./||' | sort \
        | while IFS= read -r f; do
            head -c 64 "$f" 2>/dev/null | grep -qE '^#! ?/.*\b(bash|sh)$' && printf '%s\n' "$f"
        done
}

# ── Shell scripts ────────────────────────────────────────────────────────────
# SC1091 (can't follow non-constant/external source) is excluded everywhere:
# this repo's scripts source abora-ui.sh via a runtime-resolved path
# ($ABORA_UI_LIB or /etc/abora/ui.sh) that shellcheck cannot statically
# follow, and that pattern is intentional (see abora-ui.sh's own docs).

check_shell() {
    local file="$1"
    sh_count=$((sh_count + 1))

    if bash -n "$file" 2>/dev/null; then
        pass "syntax (bash): $file"
    else
        fail "syntax (bash): $file"
        return
    fi

    if [[ ! -x "$file" ]]; then
        fail "not executable: $file"
    fi

    if ! head -n1 "$file" | grep -q '^#!'; then
        fail "missing shebang: $file"
    fi

    # set -euo pipefail (in one line or split across several) is this repo's
    # documented convention (CLAUDE.md) — missing it isn't a hard failure
    # since a few entry points intentionally opt out (e.g. installers that
    # need to keep running after a step fails to show their own error UI),
    # but it's worth flagging so that's a deliberate choice, not an oversight.
    if ! grep -qE 'set -[a-zA-Z]*e' "$file" \
        || ! grep -qE 'set -[a-zA-Z]*u|set -o nounset' "$file" \
        || ! grep -qE 'pipefail' "$file"; then
        warn "no 'set -euo pipefail' (or equivalent split form): $file"
    fi

    if command -v shellcheck >/dev/null 2>&1; then
        local sc_output sc_status
        sc_output="$(shellcheck -e SC1091 -f gcc "$file" 2>&1)" && sc_status=0 || sc_status=$?
        if [[ "$sc_status" -eq 0 ]]; then
            pass "shellcheck: $file"
        else
            local errors warnings
            errors="$(printf '%s\n' "$sc_output" | grep -c ': error:' || true)"
            warnings="$(printf '%s\n' "$sc_output" | grep -c ': warning:' || true)"
            if [[ "$errors" -gt 0 ]]; then
                fail "shellcheck: $file (${errors} error(s), ${warnings} warning(s))"
                printf '%s\n' "$sc_output" | grep ': error:' | sed 's/^/    /'
            else
                warn "shellcheck: $file (${warnings} warning(s), no errors)"
                printf '%s\n' "$sc_output" | grep ': warning:' | sed 's/^/    /'
            fi
        fi
    fi
}

# ── Nix files ─────────────────────────────────────────────────────────────────

check_nix() {
    local file="$1"
    nix_count=$((nix_count + 1))

    if command -v nix-instantiate >/dev/null 2>&1; then
        if nix-instantiate --parse "$file" >/dev/null 2>&1; then
            pass "parse (nix): $file"
        else
            fail "parse (nix): $file"
            return
        fi
    fi

    check_nix_referenced "$file"
}

# Flag .nix files under nix/ that nothing else in the repo appears to import
# or callPackage. Heuristic (basename text search, not a real dependency
# graph) — flake.nix, default.nix files (implicit directory imports), and
# anything the flake references by relative path all count as referenced.
# A false positive here just means "double check this by hand," not "delete
# it" — some files are legitimately reached only through a chain this
# text search can't follow (e.g. a module imported by another module that
# is itself only reached via `imports = import ./default.nix`).
check_nix_referenced() {
    local file="$1"
    case "$file" in
        nix/*) : ;;
        *) return ;;  # only nix/ is where "orphaned module" is a meaningful risk
    esac

    local base
    base="$(basename -- "$file")"
    [[ "$base" == "default.nix" ]] && return

    local hits
    hits="$(grep -rl --include='*.nix' -F "$base" . \
        --exclude-dir=out --exclude-dir=.git --exclude-dir=vendor \
        2>/dev/null | grep -vF "./$file" | wc -l)"

    if [[ "$hits" -eq 0 ]]; then
        orphan_count=$((orphan_count + 1))
        warn "possibly orphaned (not imported anywhere): $file"
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
# Three things, all best-effort text analysis rather than a real Markdown
# parser: relative file links resolve, #anchor links resolve to a real
# heading in the target file, and fenced ```sh / ```bash / ```nix code
# blocks are individually syntax-checked the same way a real file of that
# type would be.

# Convert a heading line's text to the anchor slug GitHub/most renderers
# would generate: lowercase, spaces to hyphens, strip anything that isn't
# alphanumeric/hyphen/underscore.
slugify_heading() {
    local text="$1"
    text="${text,,}"
    text="$(printf '%s' "$text" | sed -E 's/[^a-z0-9 _-]//g; s/ +/-/g')"
    printf '%s' "$text"
}

check_markdown_links() {
    local file="$1"
    md_count=$((md_count + 1))

    local dir broken=0
    dir="$(dirname -- "$file")"

    local link
    while IFS= read -r link; do
        [[ -n "$link" ]] || continue
        local target="${link%%#*}"
        local anchor=""
        [[ "$link" == *"#"* ]] && anchor="${link#*#}"

        case "$target" in
            http://*|https://*|mailto:*) continue ;;
        esac

        if [[ -n "$target" ]]; then
            local resolved="$dir/$target"
            if [[ ! -e "$resolved" ]]; then
                printf '  broken link: %s -> %s\n' "$file" "$link"
                broken=1
                continue
            fi
        fi

        if [[ -n "$anchor" ]]; then
            # An in-page anchor (target == "") checks headings in this file;
            # a file+anchor link checks headings in the target file.
            local heading_file="$file"
            [[ -n "$target" ]] && heading_file="$dir/$target"
            [[ -f "$heading_file" ]] || continue  # already reported above if missing

            local found=0 heading_line slug
            while IFS= read -r heading_line; do
                heading_line="$(printf '%s' "$heading_line" | sed -E 's/^#+[[:space:]]*//')"
                slug="$(slugify_heading "$heading_line")"
                if [[ "$slug" == "$anchor" ]]; then
                    found=1
                    break
                fi
            done < <(grep -E '^#+[[:space:]]' "$heading_file" 2>/dev/null)

            if [[ "$found" -eq 0 ]]; then
                printf '  broken anchor: %s -> %s (no heading slugs to "%s" in %s)\n' \
                    "$file" "$link" "$anchor" "$heading_file"
                broken=1
            fi
        fi
    done < <(grep -oE '\]\([^)]+\)' "$file" 2>/dev/null | sed -E 's/^\]\((.*)\)$/\1/')

    if [[ "$broken" -eq 0 ]]; then
        pass "links: $file"
    else
        fail "links: $file"
    fi
}

# Extract every ```sh/```bash/```nix fenced block and syntax-check it the
# same way the corresponding real file type would be. Skips blocks that
# look like partial snippets (start with a shell prompt, or a lone
# fragment with no statement terminator) since those are illustrative, not
# meant to be complete standalone programs.
check_markdown_code_blocks() {
    local file="$1"
    local tmpdir block_count=0 block_failed=0
    tmpdir="$(mktemp -d)"

    local lang="" in_block=0 block=""
    while IFS= read -r line; do
        if [[ "$in_block" -eq 0 && "$line" =~ ^\`\`\`(sh|bash|nix)[[:space:]]*$ ]]; then
            in_block=1
            lang="${BASH_REMATCH[1]}"
            block=""
            continue
        fi
        if [[ "$in_block" -eq 1 && "$line" == '```' ]]; then
            in_block=0
            block_count=$((block_count + 1))

            # Skip snippets that are clearly illustrative fragments, not
            # complete programs: a leading '$ ' prompt, or content that's
            # obviously a bare command example rather than a script.
            if [[ "$block" == '$ '* || "$block" =~ ^[[:space:]]*\$\  ]]; then
                continue
            fi

            local block_file
            if [[ "$lang" == "nix" ]]; then
                block_file="$tmpdir/block_${block_count}.nix"
                printf '%s\n' "$block" > "$block_file"
                if command -v nix-instantiate >/dev/null 2>&1; then
                    if ! nix-instantiate --parse "$block_file" >/dev/null 2>&1; then
                        # A fenced nix block is very often a fragment (an
                        # attrset body, an option snippet) rather than a
                        # complete expression, so this is advisory only.
                        printf '  note: ```nix block #%d in %s does not parse standalone (may be a fragment)\n' \
                            "$block_count" "$file"
                    fi
                fi
            else
                block_file="$tmpdir/block_${block_count}.sh"
                printf '%s\n' "$block" > "$block_file"
                if ! bash -n "$block_file" 2>/dev/null; then
                    printf '  broken code block: ```%s block #%d in %s does not parse\n' \
                        "$lang" "$block_count" "$file"
                    block_failed=1
                fi
            fi
            continue
        fi
        [[ "$in_block" -eq 1 ]] && block="${block}${line}"$'\n'
    done < "$file"

    rm -rf "$tmpdir"

    if [[ "$block_count" -eq 0 ]]; then
        return
    fi

    if [[ "$block_failed" -eq 0 ]]; then
        pass "code blocks ($block_count): $file"
    else
        fail "code blocks: $file"
    fi
}

# ── ANIX v2 plan sources ──────────────────────────────────────────────────────
# .anix/.mko/.moducpp files are ANIX's own configuration languages, not
# scripts in the usual sense — but they're still executable specifications
# with their own syntax to get wrong. `anix diff-plan <file>` resolves the
# right language adapter, parses/compiles the source into Plan JSON, and
# validates that JSON, all without applying anything (no nixos-rebuild, no
# state written) — exactly the non-destructive check this sweep needs.
#
# If the adapter for a given language isn't installed on this machine (MKO
# or ModuCPP toolchains are a separate install from Abora itself), that's an
# environment gap, not a broken plan file, so it's counted as skipped rather
# than failed.

check_anix_plan() {
    local file="$1"
    anix_count=$((anix_count + 1))

    if ! command -v jq >/dev/null 2>&1 || [[ ! -f scripts/anix.sh ]]; then
        anix_skipped=$((anix_skipped + 1))
        return
    fi

    local output status
    output="$(bash scripts/anix.sh diff-plan "$file" 2>&1)" && status=0 || status=$?

    if [[ "$status" -eq 0 ]]; then
        pass "anix diff-plan: $file"
        return
    fi

    if printf '%s\n' "$output" | grep -q 'No language adapter found'; then
        anix_skipped=$((anix_skipped + 1))
        printf '[ok]   anix diff-plan: %s (adapter not installed, skipped)\n' "$file"
        return
    fi

    fail "anix diff-plan: $file"
    printf '%s\n' "$output" | grep -E '✗|error' | sed 's/^/    /' || true
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
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    check_shell "$f"
done < <(find_shebang_scripts)

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

printf '\nMarkdown files (links, anchors, fenced code blocks)\n'
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    check_markdown_links "$f"
    check_markdown_code_blocks "$f"
done < <(find_files md)

printf '\nANIX v2 plan sources (anix diff-plan, non-destructive)\n'
if ! command -v jq >/dev/null 2>&1; then
    printf '[ok]   jq unavailable (anix plan checks skipped)\n'
fi
for ext in anix mko moducpp; do
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        check_anix_plan "$f"
    done < <(find_files "$ext")
done

printf '\n%d shell, %d nix (%d possibly orphaned), %d python, %d markdown, %d anix plan(s, %d skipped) checked.\n' \
    "$sh_count" "$nix_count" "$orphan_count" "$py_count" "$md_count" "$anix_count" "$anix_skipped"

if [[ "$warned" -ne 0 && "$failed" -eq 0 ]]; then
    printf '\nNo hard failures, but warnings were printed above — review them.\n'
fi

if [[ "$failed" -ne 0 ]]; then
    printf '\nOne or more checks failed.\n' >&2
    exit 1
fi

printf '\nAll files passed.\n'
