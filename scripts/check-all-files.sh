#!/usr/bin/env bash
# check-all-files.sh — glob-based repo sweep, independent of check-scripts.sh's
# hardcoded file lists. Walks every .sh, .nix, .py, .md, .yml, .json, and
# .desktop file actually on disk (skipping out/, .git/, and vendor/) and
# validates each by type, plus every extensionless-but-shebanged script (e.g.
# tools/moducpp-anix) and every ANIX v2 source file (.anix/.mko/.moducpp) via
# `anix diff-plan`, so a new file that nobody registered anywhere still gets
# checked.
set -euo pipefail

repo_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$repo_dir"

# Color only when stdout is a real terminal and the user hasn't opted out
# (NO_COLOR is the de-facto standard env var for this, TERM=dumb is the
# traditional one). CI log viewers vary in ANSI support, so this keeps the
# same plain [ok]/[fail]/[warn] text output check-scripts.sh and
# check-desktops.sh already use whenever output isn't an interactive TTY.
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
    C_GREEN=$'\033[38;5;77m'
    C_RED=$'\033[38;5;203m'
    C_YELLOW=$'\033[38;5;222m'
    C_ORANGE=$'\033[38;5;208m'
    C_DIM=$'\033[38;5;242m'
    C_CYAN=$'\033[38;5;44m'
    C_BOLD=$'\033[1m'
    C_NC=$'\033[0m'
else
    C_GREEN="" C_RED="" C_YELLOW="" C_ORANGE="" C_DIM="" C_CYAN="" C_BOLD="" C_NC=""
fi

failed=0
warned=0
elevated=0
sh_count=0
nix_count=0
py_count=0
md_count=0
orphan_count=0
anix_count=0
yaml_count=0
json_count=0
desktop_count=0
conf_count=0
anix_skipped=0

pass() {
    printf '%b[ok]%b   %s\n' "$C_GREEN" "$C_NC" "$1"
}

fail() {
    printf '%b[fail]%b %s\n' "$C_RED" "$C_NC" "$1"
    failed=1
}

# Ordinary warning: printed, tallied, but never stops the run — used for
# style conventions and heuristics that have known, legitimate exceptions
# (missing set -euo pipefail on a source-only library, a possibly-orphaned
# Nix file that's actually reached through a chain the text search can't
# follow). Reviewed by a human at their own pace.
warn() {
    printf '%b[warn]%b %s\n' "$C_YELLOW" "$C_NC" "$1"
    warned=1
}

# Elevated warning: real static-analysis signal (shellcheck actually flagged
# something, not just "this is unconventional") that's serious enough to
# block the run exactly like a hard failure, but is visually and
# semantically distinct from `fail` — a fail means "this check itself is
# broken" (syntax error, invalid JSON); an elevated warning means "this file
# is syntactically fine but a real tool found something worth fixing before
# merging."
warn_elevated() {
    printf '%b[warn+]%b %s\n' "$C_ORANGE" "$C_NC" "$1"
    warned=1
    elevated=1
}

note() {
    printf '%b  note: %s%b\n' "$C_DIM" "$1" "$C_NC"
}

section() {
    printf '\n%b%s%b\n' "${C_BOLD}${C_CYAN}" "$1" "$C_NC"
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
    local source_only=0
    sh_count=$((sh_count + 1))

    case "$file" in
        TinyPM/src/lib/*.sh|TinyPM/src/lib/*/*.sh)
            source_only=1
            ;;
    esac
    if grep -qF 'Source this file; do not execute it directly' "$file"; then
        source_only=1
    fi

    if bash -n "$file" 2>/dev/null; then
        pass "syntax (bash): $file"
    else
        fail "syntax (bash): $file"
        return
    fi

    if [[ "$source_only" -eq 0 && ! -x "$file" ]]; then
        fail "not executable: $file"
    fi

    if [[ "$source_only" -eq 0 ]]; then
        if ! head -n1 "$file" | grep -q '^#!'; then
            fail "missing shebang: $file"
        fi
    fi

    # set -euo pipefail (in one line or split across several) is this repo's
    # documented convention (CLAUDE.md) — missing it isn't a hard failure
    # since a few entry points intentionally opt out (e.g. abora-installer.sh,
    # which needs to keep running after a step fails so its own die()/
    # recovery-menu UI can show, rather than have -e yank control away), and
    # source-only libraries correctly never set it at all (sourcing a file
    # that does would impose -e on whatever sourced it). A file that marks
    # itself "Source this file; do not execute it directly." is trusted to
    # have made that choice on purpose.
    if [[ "$source_only" -eq 1 ]]; then
        :
    elif ! grep -qE 'set -[a-zA-Z]*e' "$file" \
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
            # The -f gcc output has three severities, worst to best: error,
            # warning, note. Only "error" is elevated here — this repo's
            # dedicated CI lint workflow step already runs with -S error,
            # and a live run against every script in the repo showed 20 of
            # 35 files carry pre-existing warning/note-level style nits
            # (SC1007 space-after-equals, SC2015 A&&B||C, etc.) that were
            # never treated as blocking anywhere else here. Elevating on
            # mere "warning" would make check-all fail on almost every
            # commit — not a useful signal. Both stay visible as ordinary
            # warnings.
            local errors warnings notes
            errors="$(printf '%s\n' "$sc_output" | grep -c ': error:' || true)"
            warnings="$(printf '%s\n' "$sc_output" | grep -c ': warning:' || true)"
            notes="$(printf '%s\n' "$sc_output" | grep -c ': note:' || true)"
            if [[ "$errors" -gt 0 ]]; then
                fail "shellcheck: $file (${errors} error(s), ${warnings} warning(s), ${notes} note(s))"
                printf '%s\n' "$sc_output" | grep ': error:' | sed 's/^/    /'
            elif [[ "$warnings" -gt 0 ]]; then
                warn "shellcheck: $file (${warnings} warning(s), ${notes} note(s), no errors)"
                printf '%s\n' "$sc_output" | grep ': warning:' | sed 's/^/    /'
            else
                warn "shellcheck: $file (${notes} note(s) only)"
                printf '%s\n' "$sc_output" | grep ': note:' | sed 's/^/    /'
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

# ── Wallpaper theme .conf files ──────────────────────────────────────────────
# assets/wallpaper-themes/*.conf are plain ABORA_THEME_*="value" shell
# assignments — abora-theme-sync.sh sources them directly with `. "$file"`
# despite the .conf extension, so a syntax error here breaks theme sync at
# runtime exactly like a broken .sh file would. Not part of find_files sh
# since they're never executed, only sourced, and mixing them into the
# general shell-script section would misleadingly suggest they need a
# shebang/executable bit, which sourced-only files correctly don't have.

check_theme_conf() {
    local file="$1"
    conf_count=$((conf_count + 1))

    if bash -n "$file" 2>/dev/null; then
        pass "syntax (conf, sourced as shell): $file"
    else
        fail "syntax (conf, sourced as shell): $file"
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
                printf '%b  broken link: %s -> %s%b\n' "$C_DIM" "$file" "$link" "$C_NC"
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
                printf '%b  broken anchor: %s -> %s (no heading slugs to "%s" in %s)%b\n' \
                    "$C_DIM" "$file" "$link" "$anchor" "$heading_file" "$C_NC"
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
                        note "\`\`\`nix block #${block_count} in ${file} does not parse standalone (may be a fragment)"
                    fi
                fi
            else
                block_file="$tmpdir/block_${block_count}.sh"
                printf '%s\n' "$block" > "$block_file"
                if ! bash -n "$block_file" 2>/dev/null; then
                    printf '%b  broken code block: ```%s block #%d in %s does not parse%b\n' \
                        "$C_DIM" "$lang" "$block_count" "$file" "$C_NC"
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

# ── YAML files ────────────────────────────────────────────────────────────────
# GitHub Actions workflows are the main thing here — a YAML syntax error is
# invisible locally and only surfaces when CI itself fails to parse the
# workflow. Prefers PyYAML if the system python3 already has it. Without a
# real parser, the only fallback check kept is tab-indentation (YAML forbids
# tabs unconditionally, so this can never false-positive) — a naive
# duplicate-key scan was tried and dropped: GitHub Actions workflows
# legitimately repeat keys like `run:`/`uses:`/`with:` once per step, so a
# same-indentation text match flags normal, valid workflows as broken.

yaml_python_bin=""
resolve_yaml_python() {
    [[ -n "$yaml_python_bin" ]] && return 0
    for candidate in python3 python; do
        if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import yaml' 2>/dev/null; then
            yaml_python_bin="$candidate"
            return 0
        fi
    done
    return 1
}

check_yaml() {
    local file="$1"
    yaml_count=$((yaml_count + 1))

    if resolve_yaml_python; then
        if "$yaml_python_bin" -c "import yaml,sys; yaml.safe_load(open('$file'))" 2>/tmp/check-all-yaml-err; then
            pass "yaml: $file"
        else
            fail "yaml: $file"
            sed 's/^/    /' /tmp/check-all-yaml-err
        fi
        rm -f /tmp/check-all-yaml-err
        return
    fi

    if grep -qP '^\t' "$file" 2>/dev/null; then
        fail "yaml (basic): $file (tab-indentation — YAML forbids tabs)"
    else
        pass "yaml (basic, no parser available): $file"
    fi
}

# ── JSON files ────────────────────────────────────────────────────────────────

check_json() {
    local file="$1"
    json_count=$((json_count + 1))

    if ! command -v jq >/dev/null 2>&1; then
        return
    fi

    if jq -e . "$file" >/dev/null 2>&1; then
        pass "json: $file"
    else
        fail "json: $file"
        jq . "$file" 2>&1 | sed 's/^/    /' || true
    fi
}

# ── JSONC files (JSON with optional // comments) ─────────────────────────────
# jq has no native JSONC support, but tries plain JSON first — most JSONC
# files (including the one currently in this repo) have zero actual
# comments and parse as-is. Only if that fails does it fall back to
# stripping *whole-line* `//` comments (a line whose first non-whitespace
# characters are `//`) before retrying. Deliberately does NOT attempt to
# strip trailing/inline `//` comments: this repo's config has a `$schema`
# URL containing `https://`, and reliably telling "// starts a comment"
# apart from "// is inside a string value" needs a real JSON tokenizer,
# not a regex — safer to only handle the unambiguous whole-line case.

check_jsonc() {
    local file="$1"
    json_count=$((json_count + 1))

    if ! command -v jq >/dev/null 2>&1; then
        return
    fi

    if jq -e . "$file" >/dev/null 2>&1; then
        pass "jsonc: $file"
        return
    fi

    local stripped
    stripped="$(grep -vE '^[[:space:]]*//' "$file")"
    if printf '%s' "$stripped" | jq -e . >/dev/null 2>&1; then
        pass "jsonc: $file (parsed after stripping whole-line // comments)"
    else
        fail "jsonc: $file"
        jq . "$file" 2>&1 | sed 's/^/    /' || true
    fi
}

# ── .desktop files ────────────────────────────────────────────────────────────
# Minimal freedesktop Desktop Entry Specification check: a [Desktop Entry]
# group header, and the keys every entry needs (Type, Name, Exec for
# Application-type entries) — not full spec validation, just the mistakes
# that would actually break a launcher.

check_desktop_file() {
    local file="$1"
    desktop_count=$((desktop_count + 1))
    local bad=0

    if ! grep -q '^\[Desktop Entry\]' "$file"; then
        printf '%b  missing [Desktop Entry] group header: %s%b\n' "$C_DIM" "$file" "$C_NC"
        bad=1
    fi

    local key
    for key in Type Name; do
        if ! grep -qE "^${key}=" "$file"; then
            printf '%b  missing required key %s=: %s%b\n' "$C_DIM" "$key" "$file" "$C_NC"
            bad=1
        fi
    done

    local entry_type
    entry_type="$(sed -nE 's/^Type=(.*)$/\1/p' "$file" | head -n1)"
    if [[ "$entry_type" == "Application" ]] && ! grep -qE '^Exec=' "$file"; then
        printf '%b  Type=Application but no Exec=: %s%b\n' "$C_DIM" "$file" "$C_NC"
        bad=1
    fi

    if [[ "$bad" -eq 0 ]]; then
        pass "desktop entry: $file"
    else
        fail "desktop entry: $file"
    fi
}

# ── Run ───────────────────────────────────────────────────────────────────────

section "Shell scripts"
if ! command -v shellcheck >/dev/null 2>&1; then
    pass "shellcheck unavailable (lint checks skipped, syntax checks still run)"
fi
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    check_shell "$f"
done < <(find_files sh)
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    check_shell "$f"
done < <(find_shebang_scripts)

section "Nix files"
if ! command -v nix-instantiate >/dev/null 2>&1; then
    pass "nix-instantiate unavailable (nix parse checks skipped)"
fi
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    check_nix "$f"
done < <(find_files nix)

section "Python files"
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    check_python "$f"
done < <(find_files py)

section "Wallpaper theme .conf files (sourced as shell)"
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    check_theme_conf "$f"
done < <(find_files conf | grep -F 'wallpaper-themes/' || true)

section "Markdown files (links, anchors, fenced code blocks)"
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    check_markdown_links "$f"
    check_markdown_code_blocks "$f"
done < <(find_files md)

section "ANIX v2 plan sources (anix diff-plan, non-destructive)"
if ! command -v jq >/dev/null 2>&1; then
    pass "jq unavailable (anix plan checks skipped)"
fi
for ext in anix mko moducpp; do
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        check_anix_plan "$f"
    done < <(find_files "$ext")
done

section "YAML files (GitHub Actions workflows, etc.)"
if ! resolve_yaml_python; then
    pass 'no YAML parser available (python3 -c "import yaml" failed); falling back to basic checks'
fi
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    check_yaml "$f"
done < <(find_files yml; find_files yaml)

section "JSON files"
if ! command -v jq >/dev/null 2>&1; then
    pass "jq unavailable (json checks skipped)"
fi
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    check_json "$f"
done < <(find_files json)
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    check_jsonc "$f"
done < <(find_files jsonc)

section ".desktop files"
while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    check_desktop_file "$f"
done < <(find_files desktop)

printf '\n%b%d shell, %d nix (%d possibly orphaned), %d python, %d theme conf, %d markdown, %d anix plan(s, %d skipped), %d yaml, %d json/jsonc, %d desktop file(s) checked.%b\n' \
    "$C_DIM" "$sh_count" "$nix_count" "$orphan_count" "$py_count" "$conf_count" "$md_count" "$anix_count" "$anix_skipped" \
    "$yaml_count" "$json_count" "$desktop_count" "$C_NC"

if [[ "$warned" -ne 0 && "$elevated" -eq 0 && "$failed" -eq 0 ]]; then
    printf '\n%bNo hard failures, but warnings were printed above — review them.%b\n' "$C_YELLOW" "$C_NC"
fi

if [[ "$failed" -ne 0 ]]; then
    printf '\n%bOne or more checks failed.%b\n' "$C_RED" "$C_NC" >&2
    exit 1
fi

if [[ "$elevated" -ne 0 ]]; then
    printf '\n%b[warn+] elevated warnings were found above — these are real findings (e.g. shellcheck), not style nits. Stopping.%b\n' \
        "${C_BOLD}${C_ORANGE}" "$C_NC" >&2
    exit 1
fi

printf '\n%bAll files passed.%b\n' "${C_BOLD}${C_GREEN}" "$C_NC"
