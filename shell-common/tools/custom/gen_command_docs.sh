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
_RENDER_FILE=""
_WORK_DIR=""

# Frames the per-topic bodies in the render child's single output stream.
# Long and unlikely enough that no help row can collide with it.
GCD_DELIM="@@GEN_COMMAND_DOCS@@"
FAILED_TOPICS=" "

# Topics whose row functions render live host state rather than static help
# text, so their output differs per machine and must never be committed.
# `ssl` / `crt` (security_ssh_help.sh) print the values of $SSL_CERT_FILE,
# $REQUESTS_CA_BUNDLE and $NODE_EXTRA_CA_CERTS — on a corporate machine that
# bakes internal certificate paths into a doc that ships to a public repo.
# Read these with `ssl-help` / `crt-help` instead, where the values are
# genuinely yours.
#
# Locale-dependent output (`sort` collation, `cut -c` on multibyte text) is
# NOT handled here — the render child pins LC_ALL=C so it is deterministic.
GCD_DENY_TOPICS="ssl crt"

_cleanup() {
    [ -n "$_STUB_FILE" ] && [ -f "$_STUB_FILE" ] && rm -f "$_STUB_FILE"
    [ -n "$_RENDER_FILE" ] && [ -f "$_RENDER_FILE" ] && rm -f "$_RENDER_FILE"
    [ -n "$_WORK_DIR" ] && [ -d "$_WORK_DIR" ] && rm -rf "$_WORK_DIR"
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

# The child renderer. Reads a manifest of "<topic>\t<file>\t<sec1,sec2,...>"
# lines and streams every topic's body, framed by $GCD_DELIM marker lines the
# parent splits on.
make_render_file() {
    _RENDER_FILE="$(mktemp "${TMPDIR:-/tmp}/gen_command_docs_render.XXXXXX")"
    cat >"$_RENDER_FILE" <<'RENDER'
set +u
stubs="$1"
manifest="$2"

. "$stubs" || exit 3
for _f in "$FUNCTIONS_DIR"/*.sh; do
    [ -f "$_f" ] || continue
    . "$_f" >/dev/null 2>&1 || true
done
# Re-assert the stubs: a file that loads ux_lib unconditionally would otherwise
# have replaced the markdown renderers with the real terminal ones.
. "$stubs" || exit 3

# Every variable below is _gcd_-prefixed and the manifest is read into an
# array before the first row function runs. Both are load-bearing: we have
# just sourced ~96 files, and a help function that assigns an unlocalized
# global (my_help.sh sets a bare `topic=`) would otherwise rewrite the loop
# variable mid-iteration and file one topic's output under another's name.
_gcd_manifest_lines=()
while IFS= read -r _gcd_line; do
    [ -n "$_gcd_line" ] && _gcd_manifest_lines+=("$_gcd_line")
done <"$manifest"

# Emit a section body; returns non-zero only when the row function produced
# nothing at all. A row that prints its content and still exits non-zero
# (dot_help.sh's `show_mnt` call is a dangling name) is what the user sees
# from `<topic>-help <section>`, so it is documented, not discarded.
_gcd_emit_section() {
    _gcd_out="$("$1" 2>/dev/null)"
    if [ -z "$_gcd_out" ]; then
        return 1
    fi
    printf '%s\n' "$_gcd_out"
    return 0
}

for _gcd_entry in "${_gcd_manifest_lines[@]}"; do
    _gcd_topic="${_gcd_entry%%	*}"
    _gcd_rest="${_gcd_entry#*	}"
    _gcd_secs="${_gcd_rest#*	}"
    printf '%s TOPIC %s\n' "$GCD_DELIM" "$_gcd_topic"

    # Section headings must name a token the dispatcher accepts. Row-function
    # suffixes are underscore-form by necessity, but the `case` labels are
    # dash-form (`git-help release-artifacts`). The topic's own
    # _help_list_sections is the SSOT for the accepted spelling, so prefer it
    # and fall back to the suffix when the topic has no such function.
    _gcd_tokens=""
    if declare -F "_${_gcd_topic}_help_list_sections" >/dev/null 2>&1; then
        _gcd_tokens=$("_${_gcd_topic}_help_list_sections" 2>/dev/null |
            sed -e 's/^[[:space:]]*-[[:space:]]*//' -e 's/[[:space:]].*$//' -e 's/:$//')
    fi

    if declare -F "_${_gcd_topic}_help_summary" >/dev/null 2>&1; then
        printf '## 요약 (%s-help)\n\n' "$(printf '%s' "$_gcd_topic" | tr '_' '-')"
        _gcd_emit_section "_${_gcd_topic}_help_summary" ||
            printf '%s FAIL %s summary\n' "$GCD_DELIM" "$_gcd_topic"
        printf '\n'
    fi

    printf '## 섹션\n\n'
    for _gcd_suffix in $(printf '%s' "$_gcd_secs" | tr ',' ' '); do
        _gcd_heading="$_gcd_suffix"
        for _gcd_tok in $_gcd_tokens; do
            [ "$(printf '%s' "$_gcd_tok" | tr '-' '_')" = "$_gcd_suffix" ] || continue
            _gcd_heading="$_gcd_tok"
            break
        done
        printf '### %s\n\n' "$_gcd_heading"
        _gcd_emit_section "_${_gcd_topic}_help_rows_${_gcd_suffix}" ||
            printf '%s FAIL %s %s\n' "$GCD_DELIM" "$_gcd_topic" "$_gcd_heading"
        printf '\n'
    done
done
RENDER
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

# Render EVERY topic in ONE bash child that sources the whole functions/ tree
# up front.
#
# Why the whole tree and not just the topic's own file: row functions
# legitimately call helpers defined in sibling files — `_dot_help_rows_mounts`
# calls `show_mnt` from mount.sh, `_category_help_rows_topics` reaches into
# my_help.sh. Sourcing one file in isolation made those die mid-render, and the
# failure was papered over as literal "(렌더 실패)" text inside a doc that still
# counted as written. An interactive shell loads all of these together, so the
# whole tree is the faithful environment, not a workaround.
#
# One child for all topics also beats one child per topic on wall clock: the
# tree is sourced once (~100 ms) instead of once per topic.
#
# The output is post-processed so the committed docs stay machine-independent:
# ANSI escapes stripped, and absolute paths folded back to `~/dotfiles` / `~`
# (some rows interpolate $DOTFILES_ROOT, which differs per worktree — without
# this every clone would regenerate a diff).
render_all_bodies() {
    local manifest="$1" stream="$2"

    # LC_ALL=C pins collation and byte-wise truncation. Without it a row that
    # does `find | sort` or `cut -c1-57` over multibyte text renders
    # differently depending on the generating machine's locale, and the
    # committed docs stop being reproducible.
    DOTFILES_FORCE_INIT=1 NO_COLOR=1 TERM=dumb DOTFILES_TEST_MODE=1 LC_ALL=C \
        SHELL_COMMON="$SHELL_COMMON" DOTFILES_ROOT="$DOTFILES_ROOT" \
        FUNCTIONS_DIR="$FUNCTIONS_DIR" GCD_DELIM="$GCD_DELIM" \
        bash --noprofile --norc "$_RENDER_FILE" "$_STUB_FILE" "$manifest" 2>/dev/null |
        LC_ALL=C sed \
            -e 's/\x1b\[[0-9;]*[A-Za-z]//g' \
            -e "s|${DOTFILES_ROOT}|~/dotfiles|g" \
            -e "s|${HOME}|~|g" >"$stream"
}

# Split the combined stream into per-topic body files and surface render
# failures. A topic that reports a failed section is recorded in FAILED_TOPICS
# so main() can refuse to write a half-rendered doc — the previous code tested
# `[ -z "$content" ]`, which could never be true because the document header is
# emitted before anything can fail.
split_bodies() {
    local stream="$1" dir="$2"
    local line cur="" rest ftopic fsec

    FAILED_TOPICS=" "
    while IFS= read -r line; do
        case "$line" in
        "$GCD_DELIM TOPIC "*)
            cur="${line#"$GCD_DELIM TOPIC "}"
            : >"${dir}/${cur}.body"
            ;;
        "$GCD_DELIM FAIL "*)
            rest="${line#"$GCD_DELIM FAIL "}"
            ftopic="${rest%% *}"
            fsec="${rest#* }"
            ux_warning "${ftopic}: '${fsec}' 섹션 렌더 실패 — 문서를 갱신하지 않음"
            case "$FAILED_TOPICS" in *" $ftopic "*) ;; *) FAILED_TOPICS="${FAILED_TOPICS}${ftopic} " ;; esac
            ;;
        *)
            [ -n "$cur" ] && printf '%s\n' "$line" >>"${dir}/${cur}.body"
            ;;
        esac
    done <"$stream"
}

# Full markdown document for one topic.
render_topic_doc() {
    local file="$1" topic="$2" basename_stem="$3" notes_file="$4" body_file="$5"

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

    cat "$body_file"

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
# leaves the file (and its mtime) untouched.
# Returns 0 when it wrote, 1 when the content was already identical.
write_if_changed() {
    local target="$1" content="$2"
    if [ -f "$target" ] && [ "$content" = "$(<"$target")" ]; then
        return 1
    fi
    printf '%s\n' "$content" >"$target"
    return 0
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
    make_render_file
    _WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gen_command_docs_work.XXXXXX")"
    mkdir -p "$out_dir" "$notes_dir"

    ux_header "Command Docs Generator"

    local topic file stem doc content body i
    local -a sections=()
    local -a stems=()
    local -a taken=()
    local -a r_topic=() r_file=() r_stem=()
    local n_written=0 n_unchanged=0 n_skipped=0 n_failed=0 n_denied=0
    local manifest="${_WORK_DIR}/manifest.tsv"
    : >"$manifest"

    # Plan pass: resolve each topic's filename and section list up front so the
    # render child can handle every topic in a single process.
    while IFS=$'\t' read -r topic file; do
        [ -n "$topic" ] || continue
        if [ -n "$OPT_TOPIC" ] && [ "$topic" != "$OPT_TOPIC" ]; then
            continue
        fi

        case " $GCD_DENY_TOPICS " in
        *" $topic "*)
            ux_warning "${topic}: 호스트 환경값을 렌더 — 문서 생성 제외 (${topic}-help 로 직접 확인)"
            n_denied=$((n_denied + 1))
            continue
            ;;
        esac

        mapfile -t sections < <(topic_sections "$file" "$topic")

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

        r_topic+=("$topic")
        r_file+=("$file")
        r_stem+=("$stem")
        printf '%s\t%s\t%s\n' "$topic" "$file" "$(
            IFS=,
            printf '%s' "${sections[*]}"
        )" >>"$manifest"
    done <<<"$(discover_topics)"

    # Render pass: one child for every topic, then compose and write.
    if [ "${#r_topic[@]}" -gt 0 ]; then
        render_all_bodies "$manifest" "${_WORK_DIR}/stream"
        split_bodies "${_WORK_DIR}/stream" "$_WORK_DIR"

        for i in "${!r_topic[@]}"; do
            topic="${r_topic[$i]}"
            stem="${r_stem[$i]}"
            body="${_WORK_DIR}/${topic}.body"

            # A topic whose rows failed keeps its previous doc rather than
            # publishing a half-rendered one.
            case "$FAILED_TOPICS" in
            *" $topic "*)
                n_failed=$((n_failed + 1))
                continue
                ;;
            esac
            if [ ! -s "$body" ]; then
                ux_warning "${topic}: 렌더 결과 없음 — 문서를 갱신하지 않음"
                n_failed=$((n_failed + 1))
                continue
            fi

            content="$(render_topic_doc "${r_file[$i]}" "$topic" "$stem" "${notes_dir}/${stem}.md" "$body")"
            if write_if_changed "${out_dir}/${stem}.md" "$content"; then
                n_written=$((n_written + 1))
            else
                n_unchanged=$((n_unchanged + 1))
            fi
        done
    fi

    if [ -z "$OPT_TOPIC" ]; then
        warn_legacy_help_files
    fi

    if [ -z "$OPT_TOPIC" ] && [ "${#stems[@]}" -gt 0 ]; then
        local -a sorted_stems=()
        mapfile -t sorted_stems < <(printf '%s\n' "${stems[@]}" | LC_ALL=C sort)
        if write_index "$out_dir" "${sorted_stems[@]}"; then
            n_written=$((n_written + 1))
        else
            n_unchanged=$((n_unchanged + 1))
        fi
    fi

    ux_table_row "written" "$n_written"
    ux_table_row "unchanged" "$n_unchanged"
    ux_table_row "skipped (문서 존재, --force 없음)" "$n_skipped"
    ux_table_row "legacy (row 함수 없는 *_help.sh)" "$N_LEGACY"
    ux_table_row "denied (호스트 환경값 렌더)" "$n_denied"
    ux_table_row "failed" "$n_failed"
    ux_success "Docs: ${out_dir#"${DOTFILES_ROOT}"/}"
    ux_info "Search: rg \"<keyword>\" ${out_dir#"${DOTFILES_ROOT}"/}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
