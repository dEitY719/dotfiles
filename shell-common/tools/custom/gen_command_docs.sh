#!/bin/bash
# shell-common/tools/custom/gen_command_docs.sh
#
# Generate one markdown reference doc per user-facing command from the
# `_<topic>_help_rows_<section>()` row functions that
# docs/.ssot/command-guidelines.md defines as the help SSOT (issue #1262).
#
# Why execute the row functions instead of parsing rendered help output:
# the row functions ARE the data layer. Overriding the ux_lib renderers with
# markdown-emitting stubs intercepts that data before it is styled for a
# terminal, so the docs never drift from what `<topic>-help <section>` prints.
#
# Hand-written edge cases (the "Esc quietly exits" kind that only lives in
# source comments) are NOT auto-extractable. They live in
# docs/guide/commands/.notes/<name>.md and are spliced into the generated
# doc verbatim. The notes dir is dot-prefixed so `rg` (which skips hidden
# paths by default) returns exactly one hit per command, not two.
#
# Usage:
#   shell-common/tools/custom/gen_command_docs.sh                # generate missing docs
#   shell-common/tools/custom/gen_command_docs.sh --force        # regenerate all
#   shell-common/tools/custom/gen_command_docs.sh --topic cc     # single topic
#   shell-common/tools/custom/gen_command_docs.sh --list         # discovery only
#   shell-common/tools/custom/gen_command_docs.sh --out-dir DIR  # write elsewhere
#
# Search the result with ripgrep:
#   rg "fzf 피커" docs/guide/commands/

# The markdown templates below are full of single-quoted backticks (inline code
# spans), which shellcheck reads as command substitution it cannot expand.
# shellcheck disable=SC2016

set -euo pipefail

_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
_SCRIPT_DIR="$(dirname "$_SCRIPT_PATH")"
SHELL_COMMON="${_SCRIPT_DIR%/tools/custom}"
export SHELL_COMMON
DOTFILES_ROOT="${SHELL_COMMON%/shell-common}"
export DOTFILES_ROOT

# shellcheck source=/dev/null
source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

FUNCTIONS_DIR="${SHELL_COMMON}/functions"
DEFAULT_OUT_DIR="${DOTFILES_ROOT}/docs/guide/commands"
NOTES_DIRNAME=".notes"

OPT_FORCE=0
OPT_LIST=0
OPT_TOPIC=""
OPT_OUT_DIR=""

_STUB_FILE=""

_cleanup() {
    [ -n "$_STUB_FILE" ] && [ -f "$_STUB_FILE" ] && rm -f "$_STUB_FILE"
    return 0
}
trap _cleanup EXIT

usage() {
    ux_info "Usage: gen_command_docs.sh [--force] [--topic <name>] [--out-dir <dir>] [--list]"
    ux_bullet "options"
    ux_bullet_sub "--force: 기존 문서도 다시 렌더링 (내용이 같으면 파일은 그대로 둔다)"
    ux_bullet_sub "--topic <name>: 특정 topic 만 생성 (예: cc, claude_skills_marketplace)"
    ux_bullet_sub "--out-dir <dir>: 출력 디렉토리 (기본 docs/guide/commands)"
    ux_bullet_sub "--list: 탐지된 topic 목록만 출력하고 종료"
}

# ---------------------------------------------------------------------------
# ux_lib -> markdown stubs
#
# Written to a temp file once and sourced by every render subshell. Sourced
# BEFORE the target file (so a file that self-loads ux_lib behind a
# `type ux_header` check keeps our stubs) and AGAIN after (so a file that
# loads ux_lib unconditionally cannot win).
# ---------------------------------------------------------------------------
make_stub_file() {
    _STUB_FILE="$(mktemp "${TMPDIR:-/tmp}/gen_command_docs_stubs.XXXXXX")"
    cat >"$_STUB_FILE" <<'STUBS'
UX_BOLD=""
UX_DIM=""
UX_RESET=""
UX_PRIMARY=""
UX_MUTED=""
UX_SUCCESS=""
UX_ERROR=""
UX_WARNING=""
UX_INFO=""
export UX_BOLD UX_DIM UX_RESET UX_PRIMARY UX_MUTED UX_SUCCESS UX_ERROR UX_WARNING UX_INFO

ux_header() { printf '**%s**\n\n' "$1"; }
ux_section() { printf '**%s**\n\n' "$1"; }
ux_bullet() { printf -- '- %s\n' "$1"; }
ux_bullet_sub() { printf -- '    - %s\n' "$1"; }
ux_numbered() { printf -- '%s. %s\n' "$1" "$2"; }
ux_info() { printf -- '- %s\n' "$*"; }
ux_success() { printf -- '- %s\n' "$*"; }
ux_warning() { printf -- '- %s\n' "$*"; }
ux_error() { printf -- '- %s\n' "$*"; }
ux_step() { printf -- '- %s\n' "$*"; }
ux_divider() { :; }
ux_divider_thick() { :; }
ux_spinner() { :; }

_gcd_row() {
    if [ -n "${3:-}" ]; then
        printf -- '- **%s** — %s — %s\n' "$1" "$2" "$3"
    else
        printf -- '- **%s** — %s\n' "$1" "${2:-}"
    fi
}
ux_table_row() { _gcd_row "$@"; }
ux_table_header() { _gcd_row "$@"; }
STUBS
}

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

# List every row function defined in a file, in definition order.
row_functions_in() {
    grep -oE '^_[a-z0-9_]+_help_rows_[a-z0-9_]+\(\)' "$1" 2>/dev/null | sed 's/()$//' || true
}

# "<topic>\t<file>" for every topic that owns at least one row function.
# A topic seen in more than one file keeps its first definition.
discover_topics() {
    local file fn topic seen=" "
    for file in "$FUNCTIONS_DIR"/*.sh; do
        [ -f "$file" ] || continue
        while IFS= read -r fn; do
            [ -n "$fn" ] || continue
            topic="${fn#_}"
            topic="${topic%%_help_rows_*}"
            case "$seen" in *" $topic "*) continue ;; esac
            seen="${seen}${topic} "
            printf '%s\t%s\n' "$topic" "$file"
        done <<<"$(row_functions_in "$file")"
    done
}

# Section names for a topic, in definition order.
topic_sections() {
    local file="$1" topic="$2" fn
    while IFS= read -r fn; do
        case "$fn" in
        "_${topic}_help_rows_"*) printf '%s\n' "${fn#_"${topic}"_help_rows_}" ;;
        esac
    done <<<"$(row_functions_in "$file")"
}

# Warn about `*_help.sh` files that predate the row-function SSOT pattern.
# They are invisible to discovery (which keys off `_help_rows_`), so without
# this they would drop out of the docs silently. Warning only — one legacy
# file must never fail the whole run. Sets N_LEGACY.
N_LEGACY=0
warn_legacy_help_files() {
    local file
    N_LEGACY=0
    for file in "$FUNCTIONS_DIR"/*_help.sh; do
        [ -f "$file" ] || continue
        # my_help.sh is the topic router itself, not a documentable topic.
        [ "$(basename "$file")" = "my_help.sh" ] && continue
        [ -n "$(row_functions_in "$file")" ] && continue
        ux_warning "$(basename "$file"): row 함수 없음 (레거시 포맷) — 문서 생성 제외"
        N_LEGACY=$((N_LEGACY + 1))
    done
}

# Aliases defined in a file, as "<alias> <target>" pairs.
aliases_in() {
    sed -n "s/^alias \([A-Za-z0-9_.-]\{1,\}\)=['\"]\{0,1\}\([A-Za-z0-9_]\{1,\}\)['\"]\{0,1\}[[:space:]]*$/\1 \2/p" "$1" 2>/dev/null || true
}

# Doc filename stem. Defaults to the dash-form topic, but prefers the
# shortest alias that points at the topic's router function — that is the
# name users actually type (`csm` for `claude_skills_marketplace`).
topic_doc_basename() {
    local file="$1" topic="$2"
    local best="${topic//_/-}"
    local name target
    while read -r name target; do
        [ -n "${name:-}" ] || continue
        [ "$target" = "$topic" ] || continue
        if [ "${#name}" -lt "${#best}" ]; then
            best="$name"
        fi
    done <<<"$(aliases_in "$file")"
    printf '%s\n' "$best"
}

# Alias list for the doc header: aliases pointing at the topic router or its
# help entry point.
topic_alias_list() {
    local file="$1" topic="$2"
    local name target out=""
    while read -r name target; do
        [ -n "${name:-}" ] || continue
        case "$target" in
        "$topic" | "${topic}_help") out="${out}${out:+, }\`${name}\`" ;;
        esac
    done <<<"$(aliases_in "$file")"
    printf '%s\n' "$out"
}

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

# Render a topic's summary + every section in ONE bash subshell.
# One process per topic keeps a full 40+ topic regeneration well under a
# second (NF-1); a process per section would not.
#
# The output is post-processed so the committed docs stay machine-independent:
# ANSI escapes stripped, and absolute paths folded back to `~/dotfiles` / `~`
# (some rows interpolate $DOTFILES_ROOT, which differs per worktree — without
# this every clone would regenerate a diff).
render_topic_body() {
    local file="$1" topic="$2"
    shift 2

    DOTFILES_FORCE_INIT=1 NO_COLOR=1 TERM=dumb DOTFILES_TEST_MODE=1 \
        SHELL_COMMON="$SHELL_COMMON" DOTFILES_ROOT="$DOTFILES_ROOT" \
        bash --noprofile --norc -c '
            set +u
            stubs="$1"; target="$2"; topic="$3"; shift 3
            . "$stubs" || exit 3
            . "$target" >/dev/null 2>&1 || exit 4
            . "$stubs" || exit 3

            if declare -F "_${topic}_help_summary" >/dev/null 2>&1; then
                printf "## 요약 (%s-help)\n\n" "${topic//_/-}"
                "_${topic}_help_summary"
                printf "\n"
            fi

            printf "## 섹션\n\n"
            for section in "$@"; do
                printf "### %s\n\n" "$section"
                "_${topic}_help_rows_${section}" || printf -- "- (렌더 실패)\n"
                printf "\n"
            done
        ' _ "$_STUB_FILE" "$file" "$topic" "$@" 2>/dev/null |
        LC_ALL=C sed \
            -e 's/\x1b\[[0-9;]*[A-Za-z]//g' \
            -e "s|${DOTFILES_ROOT}|~/dotfiles|g" \
            -e "s|${HOME}|~|g"
}

# Full markdown document for one topic.
render_topic_doc() {
    local file="$1" topic="$2" basename_stem="$3" notes_file="$4"
    shift 4

    local rel_source="${file#"${DOTFILES_ROOT}"/}"
    local topic_dash="${topic//_/-}"
    local aliases
    aliases="$(topic_alias_list "$file" "$topic")"

    if [ "$basename_stem" = "$topic_dash" ]; then
        printf '# %s\n\n' "$topic_dash"
    else
        printf '# %s (%s)\n\n' "$basename_stem" "$topic_dash"
    fi
    printf '> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `%s` 의 row 함수가 SSOT 입니다.\n' "$rel_source"
    printf '> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic %s --force`\n\n' "$topic"

    printf '## 호출\n\n'
    printf -- '- Help 진입점: `%s-help [section|--list|--all]`\n' "$topic_dash"
    printf -- '- 통합 라우팅: `my-help %s [section]`\n' "$topic"
    if [ -n "$aliases" ]; then
        printf -- '- Alias: %s\n' "$aliases"
    fi
    printf '\n'

    render_topic_body "$file" "$topic" "$@"

    printf '## 엣지케이스 / 의도된 동작\n\n'
    if [ -f "$notes_file" ]; then
        cat "$notes_file"
        printf '\n'
    else
        printf '아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면\n'
        printf '`docs/guide/commands/%s/%s.md` 에 추가한 뒤 이 문서를 재생성하세요.\n\n' \
            "$NOTES_DIRNAME" "$basename_stem"
    fi

    printf '## 소스\n\n'
    printf -- '- `%s`\n' "$rel_source"
    printf -- '- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`\n'
}

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

# Write only when the rendered content differs, so a no-op regeneration
# leaves the file (and its mtime) untouched. Echoes the verdict.
write_if_changed() {
    local target="$1" content="$2"
    if [ -f "$target" ] && [ "$content" = "$(cat "$target")" ]; then
        printf 'unchanged\n'
        return 0
    fi
    printf '%s\n' "$content" >"$target"
    printf 'written\n'
}

write_index() {
    local out_dir="$1"
    shift
    local content entry
    content="$(
        printf '# 커맨드 레퍼런스 인덱스\n\n'
        printf '`shell-common/functions/` 의 `_<topic>_help_rows_<section>()` 정의에서\n'
        printf '자동 생성한 커맨드별 상세 문서 모음입니다 (issue #1262).\n\n'
        printf '## 사용법\n\n'
        printf '```bash\n'
        printf '# 동작을 까먹었을 때 — 전체 텍스트 검색\n'
        printf 'rg "fzf 피커" docs/guide/commands/\n\n'
        printf '# 전체 재생성 (내용이 바뀐 파일만 갱신)\n'
        printf './shell-common/tools/custom/gen_command_docs.sh --force\n'
        printf '```\n\n'
        printf '이름 자체가 기억나지 않을 때는 `my-help search` (fzf topic finder) 를 쓰세요.\n\n'
        printf '## 문서 목록\n\n'
        for entry in "$@"; do
            printf -- '- [%s](./%s.md)\n' "$entry" "$entry"
        done
        printf '\n## 수기 보강 노트\n\n'
        printf '소스 주석에만 있는 엣지케이스는 자동 추출 대상이 아닙니다.\n'
        printf '`%s/<커맨드>.md` 에 작성하면 재생성 시 각 문서의\n' "$NOTES_DIRNAME"
        printf '"엣지케이스 / 의도된 동작" 절에 그대로 삽입됩니다.\n'
    )"
    write_if_changed "${out_dir}/README.md" "$content"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    while [ $# -gt 0 ]; do
        case "$1" in
        -h | --help | help)
            usage
            return 0
            ;;
        --force)
            OPT_FORCE=1
            shift
            ;;
        --list)
            OPT_LIST=1
            shift
            ;;
        --topic)
            OPT_TOPIC="${2:-}"
            [ -n "$OPT_TOPIC" ] || {
                ux_error "--topic requires a value"
                return 1
            }
            shift 2
            ;;
        --out-dir)
            OPT_OUT_DIR="${2:-}"
            [ -n "$OPT_OUT_DIR" ] || {
                ux_error "--out-dir requires a value"
                return 1
            }
            shift 2
            ;;
        *)
            ux_error "Unknown option: $1"
            usage
            return 1
            ;;
        esac
    done

    local out_dir="${OPT_OUT_DIR:-$DEFAULT_OUT_DIR}"
    local notes_dir="${out_dir}/${NOTES_DIRNAME}"

    if [ "$OPT_LIST" -eq 1 ]; then
        ux_header "Command doc topics"
        local topic file
        while IFS=$'\t' read -r topic file; do
            [ -n "$topic" ] || continue
            ux_table_row "$topic" "${file#"${DOTFILES_ROOT}"/}"
        done <<<"$(discover_topics)"
        return 0
    fi

    make_stub_file
    mkdir -p "$out_dir" "$notes_dir"

    ux_header "Command Docs Generator"

    local topic file stem doc content verdict
    local -a sections=()
    local -a stems=()
    local -a taken=()
    local n_written=0 n_unchanged=0 n_skipped=0 n_failed=0

    while IFS=$'\t' read -r topic file; do
        [ -n "$topic" ] || continue
        if [ -n "$OPT_TOPIC" ] && [ "$topic" != "$OPT_TOPIC" ]; then
            continue
        fi

        mapfile -t sections < <(topic_sections "$file" "$topic")
        if [ "${#sections[@]}" -eq 0 ]; then
            ux_warning "${topic}: row 함수 없음 — skip"
            n_failed=$((n_failed + 1))
            continue
        fi

        stem="$(topic_doc_basename "$file" "$topic")"
        # Two topics claiming one filename: the later one falls back to its
        # own topic name rather than silently overwriting the earlier doc.
        if [[ " ${taken[*]-} " == *" $stem "* ]]; then
            ux_warning "${topic}: 문서명 '${stem}' 충돌 — '${topic//_/-}' 로 대체"
            stem="${topic//_/-}"
        fi
        taken+=("$stem")
        stems+=("$stem")

        doc="${out_dir}/${stem}.md"
        if [ -f "$doc" ] && [ "$OPT_FORCE" -eq 0 ]; then
            n_skipped=$((n_skipped + 1))
            continue
        fi

        content="$(render_topic_doc "$file" "$topic" "$stem" "${notes_dir}/${stem}.md" "${sections[@]}")"
        if [ -z "$content" ]; then
            ux_warning "${topic}: 렌더 실패 — skip"
            n_failed=$((n_failed + 1))
            continue
        fi

        verdict="$(write_if_changed "$doc" "$content")"
        case "$verdict" in
        written) n_written=$((n_written + 1)) ;;
        *) n_unchanged=$((n_unchanged + 1)) ;;
        esac
    done <<<"$(discover_topics)"

    if [ -z "$OPT_TOPIC" ]; then
        warn_legacy_help_files
    fi

    if [ -z "$OPT_TOPIC" ] && [ "${#stems[@]}" -gt 0 ]; then
        local -a sorted_stems=()
        mapfile -t sorted_stems < <(printf '%s\n' "${stems[@]}" | LC_ALL=C sort)
        write_index "$out_dir" "${sorted_stems[@]}" >/dev/null
    fi

    ux_table_row "written" "$n_written"
    ux_table_row "unchanged" "$n_unchanged"
    ux_table_row "skipped (문서 존재, --force 없음)" "$n_skipped"
    ux_table_row "legacy (row 함수 없는 *_help.sh)" "$N_LEGACY"
    ux_table_row "failed" "$n_failed"
    ux_success "Docs: ${out_dir#"${DOTFILES_ROOT}"/}"
    ux_info "Search: rg \"<keyword>\" ${out_dir#"${DOTFILES_ROOT}"/}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
