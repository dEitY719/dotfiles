#!/usr/bin/env bash
# claude/skills/obsidian-session-clip/lib/verify-clip.sh
#
# Self-verification of a generated session-clip note. Mirrors the vault-side
# docs/webclipper/verify-article-clip.py pattern from dEitY719/obsidian-para#5:
# the design constraints of a clip are exactly the kind of thing that breaks
# silently, so they get an executable check that ships with the generator.
#
# Checks
#   1. the note exists and is a regular file
#   2. the filename carries none of  \ / : * ? " < > |  nor a control char (NF-1)
#   3. the frontmatter carries all 9 F-3 keys
#   4. status: unprocessed
#   5. the 3 memo subsections exist and are non-empty (F-5)
#
# Usage:
#   verify-clip.sh <note-path>
# Exit 0 when every check passes, 1 otherwise.

set -uo pipefail

FORBIDDEN_SET='\\/:*?"<>|'
REQUIRED_KEYS="title source repo branch session_type created status memo tags"
MEMO_SECTIONS="### 핵심 요약
### 왜 저장했나
### 액션 아이템"

FAILURES=0

usage() {
    cat <<'EOF'
verify-clip.sh — structural check of an obsidian:session-clip note

Usage:
  verify-clip.sh <note-path>

Prints one PASS/FAIL line per check. Exits 0 only when all checks PASS.
EOF
}

pass() {
    printf 'PASS: %s\n' "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1"
    FAILURES=$((FAILURES + 1))
}

# frontmatter <file> -> the lines between the opening and closing `---`
frontmatter() {
    awk 'NR == 1 && $0 == "---" { inside = 1; next }
         inside && $0 == "---" { exit }
         inside { print }' "$1"
}

# section_body <file> <heading-regex> -> the lines under that heading
section_body() {
    awk -v want="$2" '
        $0 ~ want { grab = 1; next }
        grab && /^#/ { exit }
        grab { print }
    ' "$1"
}

main() {
    case "${1:-}" in
        -h | --help | help)
            usage
            return 0
            ;;
    esac

    if [ "$#" -lt 1 ]; then
        usage >&2
        return 1
    fi

    note="$1"

    # --- 1. file exists ----------------------------------------------------
    if [ -f "$note" ]; then
        pass "노트 파일 존재: ${note}"
    else
        fail "노트 파일이 없다: ${note}"
        printf '\nVERDICT: FAIL (%d)\n' "$FAILURES"
        return 1
    fi

    # --- 2. Windows-safe filename (NF-1) -----------------------------------
    base="$(basename -- "$note")"
    stripped="$(printf '%s' "$base" | tr -d "$FORBIDDEN_SET" | tr -d '[:cntrl:]')"
    if [ "$stripped" = "$base" ]; then
        pass "파일명에 Windows 금지문자 없음 (NF-1)"
    else
        fail "파일명에 금지문자 또는 제어문자가 있다 (NF-1): ${base}"
    fi

    # --- 3. frontmatter keys (F-3) -----------------------------------------
    fm="$(frontmatter "$note")"
    if [ -z "$fm" ]; then
        fail "frontmatter 블록(--- ... ---)이 없다 (F-3)"
    else
        missing=""
        for key in $REQUIRED_KEYS; do
            if ! printf '%s\n' "$fm" | grep -q "^${key}:"; then
                missing="${missing} ${key}"
            fi
        done
        if [ -z "$missing" ]; then
            pass "frontmatter 9개 키 모두 존재 (F-3)"
        else
            fail "frontmatter 누락 키 (F-3):${missing}"
        fi
    fi

    # --- 4. status: unprocessed --------------------------------------------
    if printf '%s\n' "$fm" | grep -qE '^status:[[:space:]]*unprocessed[[:space:]]*$'; then
        pass "status: unprocessed"
    else
        fail "status 가 unprocessed 가 아니다 (/ingest 가 소비하지 못한다)"
    fi

    # --- 5. memo skeleton (F-5) --------------------------------------------
    # Process substitution (not a pipe) so FAILURES survives the loop.
    while IFS= read -r heading; do
        [ -n "$heading" ] || continue
        body="$(section_body "$note" "^${heading}[[:space:]]*\$")"
        if [ -z "$body" ] && ! grep -qF "$heading" "$note"; then
            fail "메모 하위 섹션이 없다 (F-5): ${heading}"
        elif printf '%s' "$body" | grep -q '[^[:space:]]'; then
            pass "메모 하위 섹션 채워짐 (F-5): ${heading}"
        else
            fail "메모 하위 섹션이 비어 있다 (F-5): ${heading}"
        fi
    done < <(printf '%s\n' "$MEMO_SECTIONS")

    printf '\n'
    if [ "$FAILURES" -eq 0 ]; then
        printf 'VERDICT: PASS\n'
        return 0
    fi
    printf 'VERDICT: FAIL (%d)\n' "$FAILURES"
    return 1
}

main "$@"
