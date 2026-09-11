#!/bin/bash
# scripts/sync-gemini-skills-namespace.sh: Antigravity/Gemini 네임스페이스 기반 skills 심볼릭 링크 일괄 등록
#
# PURPOSE: $WORKSPACE_ROOT 아래 각 <repo>/skills/<skill>/SKILL.md 를 탐색하여
#          ~/.gemini/config/skills 및 ~/.gemini/skills 에 <namespace>:<skill> 형태의
#          심볼릭 링크를 일괄 생성/동기화한다 (issue #1784).
#
# WHEN TO RUN: 수동 실행 가능, 또는 scripts/setup-skills-ssot.sh 내부에서 자동 호출.

set -e

_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_ROOT="$(cd "$(dirname "$_SCRIPT_PATH")/.." && pwd)"

# Load UX library
UX_LIB="${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
if [ -f "$UX_LIB" ]; then
    # shellcheck source=../shell-common/tools/ux_lib/ux_lib.sh
    source "$UX_LIB"
else
    ux_header() { echo "=== $1 ==="; }
    ux_section() { echo ""; echo "$1"; }
    ux_success() { echo "✓ $1"; }
    ux_info() { echo "ℹ $1"; }
    ux_warning() { echo "⚠ $1"; }
    ux_error() { echo "✗ $1" >&2; }
fi

SKILL_SOURCES_LIB="${DOTFILES_ROOT}/shell-common/functions/skill_sources.sh"
if [ -f "$SKILL_SOURCES_LIB" ]; then
    # shellcheck source=../shell-common/functions/skill_sources.sh
    source "$SKILL_SOURCES_LIB"
else
    echo "Error: skill sources library not found at $SKILL_SOURCES_LIB" >&2
    exit 1
fi

_usage() {
    cat <<'USAGE_EOF'
Usage: sync-gemini-skills-namespace.sh [options]

Options:
  --dry-run      실제 심볼릭 링크 생성/삭제 없이 대상 목록만 출력
  --prune        더 이상 유효하지 않은 네임스페이스 심볼릭 링크 정리 (기본 활성화)
  --no-prune     stale 심볼릭 링크 정리 비활성화
  -h, --help     도움말 출력 후 종료

대상 디렉터리:
  - ~/.gemini/config/skills/ (Antigravity CLI)
  - ~/.gemini/skills/        (Gemini CLI)
USAGE_EOF
}

DRY_RUN=0
PRUNE=1

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --prune)
            PRUNE=1
            shift
            ;;
        --no-prune)
            PRUNE=0
            shift
            ;;
        -h|--help|help)
            _usage
            exit 0
            ;;
        *)
            ux_error "알 수 없는 옵션: $1"
            _usage >&2
            exit 2
            ;;
    esac
done

WORKSPACE_ROOT_RESOLVED="$(_skill_workspace_root || true)"
if [ -z "$WORKSPACE_ROOT_RESOLVED" ]; then
    ux_warning "skill 소스 루트를 찾지 못했습니다 — 동기화를 건너뜁니다."
    exit 0
fi

# 네임스페이스 엔트리 수집: <skill_path><TAB><namespace>:<skill_name>
collect_namespace_skills() {
    local skill_path skill_name repo namespace entry_name seen="|"

    while IFS= read -r skill_path; do
        [ -n "$skill_path" ] || continue
        skill_name="${skill_path##*/}"
        repo="${skill_path%/*/*}"
        repo="${repo##*/}"

        # worktree 디렉터리 스킵 (예: *-issue-[0-9]*, 또는 .git 이 파일인 경우)
        case "$repo" in
            *-issue-[0-9]*) continue ;;
        esac
        [ -f "${skill_path%/*/*}/.git" ] && continue

        case "$repo" in
            *-skills) namespace="${repo%-skills}" ;;
            *) namespace="$repo" ;;
        esac
        entry_name="${namespace}:${skill_name}"

        case "$seen" in
            *"|${entry_name}|"*) continue ;;
        esac
        seen="${seen}${entry_name}|"

        printf "%s\t%s\n" "$skill_path" "$entry_name"
    done <<< "$(_skill_workspace_dirs "$WORKSPACE_ROOT_RESOLVED")"
}

_agy_is_installed() {
    [ -d "${HOME}/.gemini/antigravity-cli" ] && return 0
    command -v agy >/dev/null 2>&1
}

# 심볼릭 링크 동기화 대상 디렉터리
TARGET_DIRS=()
if _agy_is_installed || [ -d "${HOME}/.gemini/config/skills" ]; then
    TARGET_DIRS+=("${HOME}/.gemini/config/skills")
fi
if [ -d "${HOME}/.gemini" ]; then
    TARGET_DIRS+=("${HOME}/.gemini/skills")
fi

if [ ${#TARGET_DIRS[@]} -eq 0 ]; then
    ux_info "Gemini / Antigravity 설정 디렉터리가 없어 동기화를 건너뜁니다."
    exit 0
fi

SKILL_ENTRIES="$(collect_namespace_skills)"
if [ -z "$SKILL_ENTRIES" ]; then
    ux_warning "등록할 네임스페이스 스킬이 없습니다."
    exit 0
fi

# O(1) 조회를 위한 associative array 구성
declare -A SKILL_MAP=()
while IFS=$'\t' read -r src_path link_name; do
    [ -n "$src_path" ] && [ -n "$link_name" ] || continue
    SKILL_MAP["$link_name"]="$(readlink -f "$src_path" 2>/dev/null || printf '%s' "$src_path")"
done <<< "$SKILL_ENTRIES"

entry_count="$(printf '%s\n' "$SKILL_ENTRIES" | grep -c .)"
ux_header "Gemini / Antigravity 네임스페이스 스킬 동기화"
ux_info "발견된 스킬: ${entry_count}개 (루트: ${WORKSPACE_ROOT_RESOLVED})"
[ "$DRY_RUN" -eq 1 ] && ux_warning "DRY-RUN 모드: 실제 링크를 생성하거나 삭제하지 않습니다."

for target_dir in "${TARGET_DIRS[@]}"; do
    ux_section "대상: ${target_dir}"
    [ "$DRY_RUN" -eq 0 ] && mkdir -p "$target_dir"

    linked=0
    unchanged=0
    pruned=0

    while IFS=$'\t' read -r src_path link_name; do
        [ -n "$src_path" ] && [ -n "$link_name" ] || continue
        dest_link="${target_dir}/${link_name}"
        src_real="$(readlink -f "$src_path" 2>/dev/null || printf '%s' "$src_path")"

        if [ -L "$dest_link" ]; then
            dest_real="$(readlink -f "$dest_link" 2>/dev/null || true)"
            if [ "$dest_real" = "$src_real" ]; then
                unchanged=$((unchanged + 1))
                continue
            fi
        fi

        if [ "$DRY_RUN" -eq 1 ]; then
            ux_info "[dry-run] link: ${link_name} -> ${src_path}"
            linked=$((linked + 1))
        else
            ln -sfn "$src_path" "$dest_link"
            linked=$((linked + 1))
        fi
    done <<< "$SKILL_ENTRIES"

    # Stale prune: target_dir 내의 *:* 형태 symlink 중 유효하지 않거나 소스가 사라진 것 정리
    if [ "$PRUNE" -eq 1 ]; then
        shopt -s nullglob
        for existing in "$target_dir"/*; do
            [ -L "$existing" ] || continue
            fname="${existing##*/}"
            case "$fname" in
                *:*) ;;
                *) continue ;; # 네임스페이스 심볼릭 링크만 관리
            esac

            # link 가 가리키는 대상이 없거나 존재하지 않는 디렉터리인 경우
            if [ ! -e "$existing" ]; then
                if [ "$DRY_RUN" -eq 1 ]; then
                    ux_info "[dry-run] prune (broken): ${fname}"
                    pruned=$((pruned + 1))
                else
                    rm -f "$existing"
                    pruned=$((pruned + 1))
                fi
                continue
            fi

            # 소스 목록에 포함되어 있는지 O(1) 해시맵 검사
            existing_target="$(readlink -f "$existing" 2>/dev/null || true)"
            expected_target="${SKILL_MAP[$fname]:-}"

            if [ -z "$expected_target" ] || [ "$expected_target" != "$existing_target" ]; then
                if [ "$DRY_RUN" -eq 1 ]; then
                    ux_info "[dry-run] prune (unmanaged/stale): ${fname}"
                    pruned=$((pruned + 1))
                else
                    rm -f "$existing"
                    pruned=$((pruned + 1))
                fi
            fi
        done
        shopt -u nullglob
    fi

    ux_success "완료: 신규/갱신 ${linked}개, 유지 ${unchanged}개, 정리 ${pruned}개"
done

ux_success "네임스페이스 스킬 동기화 완료"
