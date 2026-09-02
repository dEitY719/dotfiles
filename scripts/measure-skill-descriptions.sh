#!/usr/bin/env bash

# scripts/measure-skill-descriptions.sh: SKILL.md description 길이 일괄 측정
#
# PURPOSE: SKILL.md 의 frontmatter description 을 문자 수로 측정해 skill:check
#          Check 16 (PASS <=250 / WARN 251-400 / FAIL >400) 판정과 총량을
#          보고한다 (issue #1411).
# WHEN TO RUN: description 다이어트 진행 중 진척 확인, 또는 CI 게이트.
#
# 측정 대상은 기본적으로 워크스페이스에 clone 된 marketplace repo 들이다
# (issue #1680 — dotfiles `claude/skills/` 는 삭제됐다). 열거 규칙은
# shell-common/functions/skill_sources.sh 가 SSOT 이고, setup-skills-ssot.sh
# 가 실제로 하네스에 연결하는 것과 정확히 같은 목록을 본다. `--skills-dir` 로
# 단일 디렉토리(`<dir>/<skill>/SKILL.md`)를 직접 지정하면 그쪽이 우선한다.
#
# 판정 로직은 중복 구현하지 않고 Check 16 의 실행 가능 미러
# tests/bats/skills/_fixtures/skill_description_length.sh 를 그대로 재사용한다.
# 임계값이 바뀌면 그 파일과 checks.md 만 고치면 된다.
#
# 총량이 중요한 이유: description 은 전 세션의 available_skills 목록에 실리고
# Codex/Kimi 는 그 목록을 설치된 전체 스킬 합계 약 5,440자로 제한한다.

set -uo pipefail

_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_ROOT="$(cd "$(dirname "$_SCRIPT_PATH")/.." && pwd)"

# Codex 2% 컨텍스트 예산 — 설치된 전체 스킬 description 합계의 상한
CODEX_BUDGET=5440

# 비어 있으면 워크스페이스를 스캔한다. --skills-dir 가 주면 그 디렉토리만.
SKILLS_DIR=""
FAIL_ON_VIOLATION=0

UX_LIB="${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
if [ -t 1 ] && [ -r "$UX_LIB" ]; then
    # shellcheck source=../shell-common/tools/ux_lib/ux_lib.sh
    source "$UX_LIB"
else
    UX_SUCCESS="" UX_ERROR="" UX_WARNING="" UX_MUTED="" UX_RESET=""
fi

_usage() {
    cat <<'EOF'
Usage: measure-skill-descriptions.sh [--skills-dir <path>] [--strict] [-h|--help]

  --skills-dir <path>  측정 대상 디렉토리 (<path>/<skill>/SKILL.md).
                       생략하면 \${WORKSPACE_ROOT:-\$HOME/para/project/skills}
                       아래 clone 된 marketplace repo 전체를 스캔한다.
  --strict             FAIL 이 하나라도 있으면 종료 코드 1 (CI 게이트용)
  -h, --help           이 도움말 출력 후 종료

출력: 스킬별 "<이름> <문자수> <PASS|WARN|FAIL>" 한 줄씩 + 요약 1줄.
판정 SSOT: authoring-skills repo 의 skills/skill-check/references/checks.md (Check 16)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
    --skills-dir)
        [ $# -ge 2 ] || {
            printf '%s[FAIL]%s --skills-dir 에 경로가 필요합니다\n' "$UX_ERROR" "$UX_RESET" >&2
            exit 2
        }
        SKILLS_DIR="$2"
        shift 2
        ;;
    --strict)
        FAIL_ON_VIOLATION=1
        shift
        ;;
    -h | --help | help)
        _usage
        exit 0
        ;;
    *)
        printf '%s[FAIL]%s 알 수 없는 인자: %s\n' "$UX_ERROR" "$UX_RESET" "$1" >&2
        _usage >&2
        exit 2
        ;;
    esac
done

MIRROR="${DOTFILES_ROOT}/tests/bats/skills/_fixtures/skill_description_length.sh"
if [ ! -r "$MIRROR" ]; then
    printf '%s[FAIL]%s Check 16 미러를 찾을 수 없습니다: %s\n' "$UX_ERROR" "$UX_RESET" "$MIRROR" >&2
    printf 'Next: git status 로 tests/bats/skills/_fixtures/ 누락 여부를 확인하세요.\n' >&2
    exit 1
fi
# shellcheck source=../tests/bats/skills/_fixtures/skill_description_length.sh
source "$MIRROR"

# 측정 대상 디렉토리 목록 (한 줄에 하나). --skills-dir 는 평평한
# `<dir>/<skill>/` 레이아웃, 기본은 워크스페이스 열거 SSOT.
if [ -n "$SKILLS_DIR" ]; then
    if [ ! -d "$SKILLS_DIR" ]; then
        printf '%s[FAIL]%s skills 디렉토리 없음: %s\n' "$UX_ERROR" "$UX_RESET" "$SKILLS_DIR" >&2
        exit 1
    fi
    SKILL_DIRS="$(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort)"
    SOURCE_LABEL="$SKILLS_DIR"
else
    SOURCES_LIB="${DOTFILES_ROOT}/shell-common/functions/skill_sources.sh"
    if [ ! -r "$SOURCES_LIB" ]; then
        printf '%s[FAIL]%s skill 소스 라이브러리 없음: %s\n' "$UX_ERROR" "$UX_RESET" "$SOURCES_LIB" >&2
        exit 1
    fi
    # shellcheck source=../shell-common/functions/skill_sources.sh
    source "$SOURCES_LIB"

    if ! WORKSPACE_DIR="$(_skill_workspace_root)"; then
        printf '%s[FAIL]%s 워크스페이스 루트가 없습니다: %s\n' "$UX_ERROR" "$UX_RESET" \
            "${WORKSPACE_ROOT:-$HOME/para/project/skills}" >&2
        printf 'Next: marketplace repo 를 그 아래에 clone 하거나 --skills-dir 로 직접 지정하세요.\n' >&2
        exit 1
    fi
    SKILL_DIRS="$(_skill_workspace_dirs "$WORKSPACE_DIR")"
    SOURCE_LABEL="$WORKSPACE_DIR"
fi

total=0
count=0
pass=0
warn=0
fail=0
missing=0

while IFS= read -r _dir; do
    [ -n "$_dir" ] || continue
    [ -d "$_dir" ] || continue
    _name="$(basename "$_dir")"
    _md="${_dir}/SKILL.md"
    [ -f "$_md" ] || continue

    if ! _len="$(skill_desc_length "$_md")"; then
        # description 부재는 Check 3 의 소관 — 여기서는 N/A 로 집계만 한다.
        printf '%-36s %5s %s\n' "$_name" "-" "N/A"
        missing=$((missing + 1))
        continue
    fi

    _verdict="$(skill_desc_verdict "$_len")"
    case "$_verdict" in
    PASS) pass=$((pass + 1)) ;;
    WARN) warn=$((warn + 1)) ;;
    FAIL) fail=$((fail + 1)) ;;
    esac

    printf '%-36s %5d %s\n' "$_name" "$_len" "$_verdict"
    total=$((total + _len))
    count=$((count + 1))
done <<< "$SKILL_DIRS"

if [ "$count" -eq 0 ]; then
    printf '%s[FAIL]%s 측정 대상 SKILL.md 가 없습니다: %s\n' "$UX_ERROR" "$UX_RESET" "$SOURCE_LABEL" >&2
    exit 1
fi

mean=$((total / count))
budget_pct=$((total * 100 / CODEX_BUDGET))

printf -- '---\n'
printf 'source=%s\n' "$SOURCE_LABEL"
printf 'skills=%d total=%d자 mean=%d자 | PASS=%d WARN=%d FAIL=%d N/A=%d\n' \
    "$count" "$total" "$mean" "$pass" "$warn" "$fail" "$missing"
printf 'Codex 예산(%d자) 대비 총량: %d%%\n' "$CODEX_BUDGET" "$budget_pct"

if [ "$fail" -gt 0 ]; then
    printf '%s[WARN]%s FAIL %d건 — 400자 초과. Check 16 참조.\n' "$UX_WARNING" "$UX_RESET" "$fail"
    printf 'Next: /skill:check <skill> 로 개별 항목을 확인하세요.\n'
    [ "$FAIL_ON_VIOLATION" -eq 1 ] && exit 1
else
    printf '%s[OK]%s FAIL 없음 — 모든 description 이 400자 이내입니다.\n' "$UX_SUCCESS" "$UX_RESET"
fi

exit 0
