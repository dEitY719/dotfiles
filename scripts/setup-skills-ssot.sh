#!/bin/bash

# scripts/setup-skills-ssot.sh: Skills 워크스페이스 연결 설정
#
# PURPOSE: 워크스페이스에 clone 된 marketplace repo 의 skills/ 를
#          OpenCode·Codex·Gemini·Hermes 에 연결
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
#
# 소스는 워크스페이스 하나뿐이다 (issue #1680 — #1410 Phase 4 컷오버). 예전의
# dotfiles `claude/skills/` SSOT 는 15개 marketplace repo 로 분리된 뒤 삭제됐고,
# "무엇이 skill 소스인가" 의 SSOT 는 shell-common/functions/skill_sources.sh 다:
#
#     ${WORKSPACE_ROOT:-$HOME/para/project/skills}/<repo>/skills/<skill>/SKILL.md
#
# 연결 전략 (issue #791 / #1376 — 아래 CLI 모두 entry-level 합성):
#   - entry-level 합성 디렉토리 (#707 / #791 / #1376):
#     ~/.config/opencode/skills/<skill>     → <workspace>/<repo>/skills/<skill>
#     ~/.gemini/skills/<skill>              → <workspace>/<repo>/skills/<skill>
#     ~/.gemini/config/skills/<skill>       → <workspace>/<repo>/skills/<skill>  (agy)
#     ~/.hermes/skills/dotfiles/<skill>     → <workspace>/<repo>/skills/<skill>
#
#   - Hermes 예외 (#1376, NF-1): Hermes 는 다른 CLI 와 달리 ~/.hermes/skills/
#     루트를 자체 hub/curator 가 능동적으로 관리한다 (.hub/, .bundled_manifest,
#     .curator_state, .usage.json* 메타데이터 + apple/ github/ 등 카테고리
#     디렉토리). 루트에 직접 합성하면 그 네임스페이스와 충돌하므로,
#     전용 서브디렉토리 ~/.hermes/skills/dotfiles/ 안에서만 합성한다.
#
#   - Codex 전용 합성: .system 디렉토리는 로컬 보존
#     ~/.codex/skills/.system                          ← local (codex managed)
#     ~/.codex/skills/<custom-skill>                   → <workspace>/<repo>/skills/<skill>
#
#   - 마이그레이션 (#791): 기존 opencode/gemini 의 디렉토리-단위 symlink 는
#     entry-level 합성으로 변환된다. 사용자가 직접 만든 symlink (target 이
#     관리 대상 밖이면서 살아 있는 경우) 는 보존 + warn.
#
# ~/.claude*/skills 는 claude/setup.sh 가 entry-level 합성 디렉토리로 관리 (#707, F-8).
# 모두 동일 layout (Hermes 만 서브디렉토리 — 위 예외 참고) 이므로 외부에서
# 추가된 symlink 도 합성 대상 전부에 동일하게 적용된다.
#
# Antigravity CLI (agy) 는 전용 분기를 갖는다 (#1731). agy 는 OAuth 토큰을
# ~/.gemini/antigravity-cli/ 에 두어 Gemini 런타임을 공유하지만, skill 검색
# 경로까지 상속하지는 않는다 — agy 의 Global Customizations Root 는
# ~/.gemini/config/ 이고 skill 은 그 아래 skills/ 에서만 발견된다.
# ~/.gemini/skills 는 agy 가 읽지 않으므로 (#1684 에서 FAIL 로 실측),
# 두 경로 모두에 합성한다. 상세: agy/AGENTS.md.

# --- Constants ---

_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_ROOT="$(cd "$(dirname "$_SCRIPT_PATH")/.." && pwd)"

# Load UX library
UX_LIB="${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
if [ -f "$UX_LIB" ]; then
    source "$UX_LIB"
else
    echo "Error: UX library not found at $UX_LIB"
    exit 1
fi

# 워크트리에서 실행하면 DOTFILES_ROOT 는 워크트리 경로다. 정리 대상 링크는
# main 체크아웃 경로(`~/dotfiles/claude/skills/...`)로 적혀 있으므로 워크트리
# 경로만 보면 하나도 매치되지 않는다 — 두 경로 모두를 레거시 패턴으로
# 인정해야 한다 (#1732). main 체크아웃 해석은 #589 의 canonicalize SSOT 를
# 그대로 쓴다 — 서브모듈 오탐 가드와 DOTFILES_ROOT_NO_CANONICALIZE 탈출구를
# 여기서 다시 구현하지 않기 위해서다.
DOTFILES_ROOT_LIB="${DOTFILES_ROOT}/shell-common/functions/dotfiles_root.sh"
if [ -f "$DOTFILES_ROOT_LIB" ]; then
    source "$DOTFILES_ROOT_LIB"
else
    echo "Error: dotfiles root library not found at $DOTFILES_ROOT_LIB"
    exit 1
fi
DOTFILES_MAIN_ROOT="$(_resolve_dotfiles_root_canonical "$DOTFILES_ROOT")"

# 소스 판별/열거의 SSOT (issue #1652 / #1410 F-6 → #1680). Claude Code
# 계정 쪽(shell-common/tools/integrations/claude.sh)이 같은 파일을 읽으므로
# "무엇이 skill 소스인가" 규칙이 두 벌로 갈라지지 않는다.
SKILL_SOURCES_LIB="${DOTFILES_ROOT}/shell-common/functions/skill_sources.sh"
if [ -f "$SKILL_SOURCES_LIB" ]; then
    source "$SKILL_SOURCES_LIB"
else
    echo "Error: skill sources library not found at $SKILL_SOURCES_LIB"
    exit 1
fi

log_info() { ux_info "$1"; }
log_error() { ux_error "$1"; }
log_dim() { echo "${UX_DIM}$1${UX_RESET}"; }
log_warning() { ux_warning "$1"; }
log_critical() { ux_error "$1"; exit 1; }

CODEX_MANAGED_MARKER=".dotfiles-skill-source"

# --- Helper Functions ---

# 소스 루트의 정규화 경로. symlink 판별은 raw target 과 resolved target
# 양쪽에서 이뤄지므로(compose 는 `readlink`, codex 는 `readlink -f`) 두 형태를
# 모두 준비해 둔다. 존재하지 않는 경로에서도 실패하지 않도록 원본으로 폴백.
_realpath_or_self() {
    readlink -f "$1" 2>/dev/null || printf "%s" "$1"
}

# 끊어진 symlink 하나가 "옛 dotfiles SSOT(claude/skills, #1680 삭제)를
# 가리키다 끊어졌다"인지 판별한다. `skill_source_is_managed`는 워크스페이스
# 루트만 인식하므로(F-3), 삭제된 옛 SSOT를 가리키던 링크는 그 검사를
# 통과하지 못하면서 동시에 broken이다 — 두 조건을 함께 봐야만 "복구할 사용자
# 데이터가 없는 broken symlink"와 "정체를 알 수 없는 임의의 broken symlink"
# (예: 일시적으로 unmount된 사용자 마운트)를 구분할 수 있다 (agy+codex FOLLOW-UP,
# PR #1729).
# Usage: _ssot_is_legacy_broken_link <resolved_target_path>
_ssot_is_legacy_broken_link() {
    case "$1" in
        "${DOTFILES_ROOT}/claude/skills" | "${DOTFILES_ROOT}/claude/skills"/* \
            | "${DOTFILES_MAIN_ROOT}/claude/skills" | "${DOTFILES_MAIN_ROOT}/claude/skills"/*)
            return 0
            ;;
        *) return 1 ;;
    esac
}

# 위 판정을 "링크 하나"에 적용하는 호출부용 래퍼 (#1732). 끊어짐 검사와 raw
# target 획득을 한곳에 묶어, 6개 호출부가 조건을 각자 손으로 조립하지 않게
# 한다 — 규칙이 바뀔 때 고쳐야 할 곳도 여기 하나뿐이다.
#
# raw(`readlink`)로 매치하는 이유: 끊어진 링크는 부모 디렉토리(`claude/`)까지
# 사라졌을 수 있고 `readlink -f` 는 마지막 컴포넌트를 뺀 나머지가 전부 존재해야
# 값을 낸다. 존재 여부와 무관한 경로 패턴 매치는 raw 문자열로 해야 한다.
# `readlink` 는 링크가 실제로 끊어졌을 때만 실행된다 (살아 있는 링크가 절대
# 다수이므로 루프마다 fork 를 아끼는 효과).
# Usage: _ssot_link_is_legacy_stale <link_path>
_ssot_link_is_legacy_stale() {
    local _target
    [ ! -e "$1" ] || return 1
    _target="$(readlink "$1" 2>/dev/null)"
    # 상대 경로로 적힌 링크도 같은 판정을 받아야 한다 (#1732 agy FOLLOW-UP).
    # 이 스크립트 자신은 항상 절대 경로로 링크를 만들지만, 수동/외부 도구가
    # 만든 상대 경로 링크는 절대 경로 prefix 매칭을 그냥 빠져나간다. 끊어진
    # 링크라 `readlink -f` 는 못 쓰므로, 존재 여부와 무관하게 `..` 를 펴 주는
    # `realpath -m` 으로 링크 자신의 디렉토리 기준 절대 경로를 만든다.
    case "$_target" in
        "" | /*) ;;
        *) _target="$(realpath -m "$(dirname "$1")/$_target" 2>/dev/null)" ;;
    esac
    _ssot_is_legacy_broken_link "$_target"
}

# 빈 문자열 = 워크스페이스 없음/너무 넓음 → 연결할 소스가 없다.
WORKSPACE_ROOT_RESOLVED="$(_skill_workspace_root || true)"
WORKSPACE_ROOT_REAL=""
[ -n "$WORKSPACE_ROOT_RESOLVED" ] \
    && WORKSPACE_ROOT_REAL="$(_realpath_or_self "$WORKSPACE_ROOT_RESOLVED")"

# 모든 skill 소스 디렉토리를 한 줄에 하나씩 표준출력으로 낸다.
#
# 소스는 워크스페이스 clone 한 곳뿐이다 (issue #1680):
#   <root>/<repo>/skills/<skill>   (열거 규칙은 shell-common SSOT)
#
# 워크스페이스 repo 끼리 이름이 겹치면 정렬 순서상 앞선 repo 가 이긴다
# (재현 가능한 결정). 진단 로그는 stdout 을 오염시키지 않도록 stderr 로 보낸다.
collect_skill_sources() {
    local seen="|"
    local skill_path skill_name

    [ -n "$WORKSPACE_ROOT_RESOLVED" ] || return 0

    while IFS= read -r skill_path; do
        [ -n "$skill_path" ] || continue
        skill_name="$(basename "$skill_path")"

        case "$seen" in
            *"|${skill_name}|"*)
                log_dim "[skills] 이름 충돌 — 먼저 발견된 소스 유지, 건너뜀: ${skill_path}" >&2
                continue
                ;;
        esac

        seen="${seen}${skill_name}|"
        printf "%s\n" "$skill_path"
    done <<< "$(_skill_workspace_dirs "$WORKSPACE_ROOT_RESOLVED")"
}

# symlink target 이 우리가 관리하는 소스 루트 아래인지 판별.
# 관리 대상이면 갱신/정리해도 되고, 아니면 사용자 데이터로 보고 보존한다.
# raw / resolved 두 형태를 모두 대조한다 — 호출부마다 비교 대상이 다르다.
skill_source_is_managed() {
    local path="$1"
    local root

    [ -n "$path" ] || return 1

    for root in "$WORKSPACE_ROOT_RESOLVED" "$WORKSPACE_ROOT_REAL"; do
        [ -n "$root" ] || continue
        case "$path" in
            "$root"/*) return 0 ;;
        esac
    done
    return 1
}

# skill 이름으로 소스 경로를 되찾는다. 없으면 비어 있는 출력 + rc 1.
# codex 의 stale prune 이 "이 이름이 아직 유효한 소스인가" 를 물을 때 쓴다.
skill_source_path_for() {
    local name="$1"
    local candidate

    [ -n "$name" ] || return 1

    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        if [ "$(basename "$candidate")" = "$name" ]; then
            printf "%s\n" "$candidate"
            return 0
        fi
    done <<< "$SKILL_SOURCE_LIST"

    return 1
}

collect_codex_homes() {
    local default_config_home
    local -a candidates=()
    local candidate
    local resolved
    local seen="|"

    if [ -n "${CODEX_HOME:-}" ]; then
        candidates+=("${CODEX_HOME}")
    fi

    candidates+=("${HOME}/.codex")
    default_config_home="${XDG_CONFIG_HOME:-${HOME}/.config}/codex"
    candidates+=("${default_config_home}")
    candidates+=("${HOME}/.cod")

    for candidate in "${candidates[@]}"; do
        [ -n "$candidate" ] || continue
        [ -d "$candidate" ] || continue

        resolved="$(readlink -f "$candidate" 2>/dev/null || printf "%s" "$candidate")"
        case "$seen" in
            *"|${resolved}|"*)
                continue
                ;;
        esac

        seen="${seen}${resolved}|"
        printf "%s\n" "$resolved"
    done
}

# Entry-level 합성 + 레거시 dir-symlink 마이그레이션 (issue #791).
# OpenCode / Gemini 가 #707 의 Claude Code entry-composition layout 과
# 동일하게 동작하도록 한다. 호출 후 <target_dir> 은 실제 디렉토리이며 그
# child entry 들이 SSOT 의 각 skill 으로 가는 symlink. 외부에서 추가된
# symlink 가 이후 같은 디렉토리에 추가 entry 를 layer할 수 있다.
#
# 마이그레이션 정책:
#   - target 이 관리 대상으로 향하는 dir-symlink → 해제 후 합성으로 전환.
#   - target 이 끊어진 dir-symlink이면서 옛 dotfiles `claude/skills/`(#1680
#     삭제)를 가리키던 것 → 해제 후 합성으로 전환. 그 경우에만 "보존할 사용자
#     데이터가 없다"고 확신할 수 있다.
#   - target 이 끊어진 dir-symlink이지만 다른 곳(예: 일시적으로 unmount된
#     사용자 마운트)을 가리켰던 것 → 보존 + warn (skip, 무손실).
#   - target 이 사용자 symlink (살아 있고 관리 대상 밖) → 보존 + warn (skip, 무손실).
#   - target 이 일반 파일 → 보존 + warn (사용자 데이터 가능성, skip).
#   - target 이 일반 디렉토리 → 합성 시도 (기존 entry 보존).
# Usage: link_skills_compose <tool_name> <target_dir>
link_skills_compose() {
    local tool="$1"
    local target="$2"

    # 1. Migrate legacy directory-symlink → real directory.
    if [ -L "$target" ]; then
        local current_target
        current_target="$(readlink -f "$target" 2>/dev/null)"
        if skill_source_is_managed "$current_target" || _ssot_link_is_legacy_stale "$target"; then
            log_info "[$tool] legacy dir-symlink 감지 — entry-level 합성으로 마이그레이션"
            rm -f "$target"
        else
            log_warning "[$tool] 사용자 symlink 감지 — 합성 마이그레이션 건너뜀: $target"
            return 0
        fi
    elif [ -e "$target" ] && [ ! -d "$target" ]; then
        log_warning "[$tool] 비-디렉토리 항목 감지 — 합성 마이그레이션 건너뜀: $target"
        return 0
    fi

    mkdir -p "$target" || log_critical "[$tool] target 디렉토리 생성 실패: $target"

    local linked=0 refreshed=0 skipped=0 pruned=0
    local skill_path skill_name link_target source_realpath current_link existing_target_path

    while IFS= read -r skill_path; do
        [ -n "$skill_path" ] || continue
        skill_name="$(basename "$skill_path")"
        link_target="${target}/${skill_name}"
        source_realpath="$(readlink -f "$skill_path")"

        if [ -L "$link_target" ]; then
            current_link="$(readlink "$link_target")"
            if [ "$current_link" = "$skill_path" ] \
                || [ "$(readlink -f "$link_target" 2>/dev/null)" = "$source_realpath" ]; then
                continue
            fi
            # 디렉토리-단위 마이그레이션과 같은 판정을 엔트리에도 적용한다
            # (#1732): 옛 SSOT 를 가리키다 끊어진 링크는 이름이 살아 있는
            # 소스와 겹치는 한 그 스킬을 계속 가린다.
            if skill_source_is_managed "$current_link" \
                || _ssot_link_is_legacy_stale "$link_target"; then
                rm -f "$link_target"
                refreshed=$((refreshed + 1))
            else
                log_dim "[$tool] 사용자 symlink 보존: $link_target"
                skipped=$((skipped + 1))
                continue
            fi
        elif [ -e "$link_target" ]; then
            log_dim "[$tool] 비-symlink 엔트리 보존: $link_target"
            skipped=$((skipped + 1))
            continue
        else
            linked=$((linked + 1))
        fi

        ln -s "$skill_path" "$link_target" || {
            log_error "[$tool] skill symlink 생성 실패: $link_target"
            continue
        }
    done <<< "$SKILL_SOURCE_LIST"

    # Stale cleanup: SSOT 로 향하던 symlink 의 원본이 사라진 경우만 정리.
    # SSOT 밖을 가리키는 entry (private overlay 등) 는 보존.
    local existing
    for existing in "$target"/*; do
        [ -L "$existing" ] || continue
        existing_target_path="$(readlink "$existing")"
        # 이름이 더 이상 어떤 소스와도 겹치지 않는 레거시 링크는 위 엔트리
        # 루프가 아예 방문하지 않는다 — 여기서만 정리된다 (#1732).
        if _ssot_link_is_legacy_stale "$existing"; then
            log_info "[$tool] legacy stale entry 정리: $existing"
            rm -f "$existing"
            pruned=$((pruned + 1))
            continue
        fi
        skill_source_is_managed "$existing_target_path" || continue
        if [ ! -d "$existing_target_path" ]; then
            log_info "[$tool] stale entry 정리: $existing"
            rm -f "$existing"
            pruned=$((pruned + 1))
        fi
    done

    log_info "[$tool] skill 합성 완료: ${linked}개 신규, ${refreshed}개 갱신, ${skipped}개 보존, ${pruned}개 정리"
}

# Codex skills 연결:
# - .system 은 로컬 보존
# - custom skill 은 디렉토리 symlink (소스 직결)
# - 기존 copy/marker 레이아웃(.dotfiles-skill-source)은 자동 마이그레이션
# Usage: link_skills_individual_codex <target_dir>
link_skills_individual_codex() {
    local target_dir="$1"
    local linked=0
    local unchanged=0
    local migrated=0
    local skipped=0
    local pruned=0
    local prune_skipped=0

    mkdir -p "$target_dir"

    while IFS= read -r skill_path; do
        [ -n "$skill_path" ] || continue

        local skill_name
        skill_name="$(basename "$skill_path")"
        if [ "$skill_name" = ".system" ]; then
            continue
        fi

        local skill_target="${target_dir}/${skill_name}"
        local source_realpath
        source_realpath="$(readlink -f "$skill_path")"

        if [ -L "$skill_target" ]; then
            local current_target
            current_target="$(readlink -f "$skill_target" 2>/dev/null || true)"
            if [ "$current_target" = "$source_realpath" ]; then
                unchanged=$((unchanged + 1))
                continue
            fi

            # compose 쪽과 동일한 레거시 판정 (#1732).
            if _ssot_link_is_legacy_stale "$skill_target"; then
                rm -f "$skill_target"
                migrated=$((migrated + 1))
            else
                log_dim "[codex] 기존 사용자 symlink 보존: $skill_target"
                skipped=$((skipped + 1))
                continue
            fi
        fi

        if [ -e "$skill_target" ] && [ ! -d "$skill_target" ]; then
            log_warning "[codex] 기존 엔트리 보존(디렉토리 아님): $skill_target"
            skipped=$((skipped + 1))
            continue
        fi

        if [ -d "$skill_target" ]; then
            local marker_file="${skill_target}/${CODEX_MANAGED_MARKER}"
            local can_migrate=0
            local has_user_data=0

            if [ -f "$marker_file" ]; then
                can_migrate=1
            else
                local existing_entry
                for existing_entry in "${skill_target}"/* "${skill_target}"/.*; do
                    [ -e "$existing_entry" ] || continue
                    local existing_entry_name
                    existing_entry_name="$(basename "$existing_entry")"
                    if [ "$existing_entry_name" = "." ] || [ "$existing_entry_name" = ".." ]; then
                        continue
                    fi
                    if [ "$existing_entry_name" = "SKILL.md" ] && [ -f "$existing_entry" ]; then
                        can_migrate=1
                        continue
                    fi
                    if [ -L "$existing_entry" ]; then
                        local existing_entry_target
                        existing_entry_target="$(readlink -f "$existing_entry" 2>/dev/null || true)"
                        case "$existing_entry_target" in
                            "$source_realpath"/*)
                                can_migrate=1
                                continue
                                ;;
                        esac
                    fi
                    has_user_data=1
                    break
                done
            fi

            if [ "$has_user_data" -eq 1 ] || [ "$can_migrate" -eq 0 ]; then
                log_dim "[codex] 기존 디렉토리 보존: $skill_target"
                skipped=$((skipped + 1))
                continue
            fi

            rm -rf "$skill_target" || {
                log_error "[codex] 기존 디렉토리 제거 실패: $skill_target"
                skipped=$((skipped + 1))
                continue
            }
            migrated=$((migrated + 1))
        fi

        ln -s "$skill_path" "$skill_target" || {
            log_error "[codex] skill symlink 생성 실패: $skill_target"
            continue
        }
        linked=$((linked + 1))
    done <<< "$SKILL_SOURCE_LIST"

    local existing_skill_entry
    for existing_skill_entry in "$target_dir"/*; do
        [ -e "$existing_skill_entry" ] || [ -L "$existing_skill_entry" ] || continue

        local existing_name
        existing_name="$(basename "$existing_skill_entry")"
        if [ "$existing_name" = ".system" ]; then
            continue
        fi

        if skill_source_path_for "$existing_name" >/dev/null; then
            continue
        fi

        if [ -L "$existing_skill_entry" ]; then
            local stale_target
            stale_target="$(readlink -f "$existing_skill_entry" 2>/dev/null || true)"
            if skill_source_is_managed "$stale_target" \
                || _ssot_link_is_legacy_stale "$existing_skill_entry"; then
                rm -f "$existing_skill_entry" || {
                    log_error "[codex] stale skill 제거 실패: $existing_skill_entry"
                    continue
                }
                pruned=$((pruned + 1))
                continue
            fi

            log_warning "[codex] stale skill symlink 보존(사용자 데이터 감지): $existing_skill_entry"
            prune_skipped=$((prune_skipped + 1))
            continue
        fi

        if [ -d "$existing_skill_entry" ] && [ -f "${existing_skill_entry}/${CODEX_MANAGED_MARKER}" ]; then
            rm -rf "$existing_skill_entry" || {
                log_error "[codex] stale managed dir 제거 실패: $existing_skill_entry"
                continue
            }
            pruned=$((pruned + 1))
            continue
        fi

        log_warning "[codex] stale skill 보존(사용자 데이터 감지): $existing_skill_entry"
        prune_skipped=$((prune_skipped + 1))
    done

    log_info "[codex] skill 연결 완료: ${linked}개 신규, ${unchanged}개 유지, ${migrated}개 마이그레이션, ${skipped}개 보존, ${pruned}개 정리, ${prune_skipped}개 stale 보존"
}

# --- Main ---

ux_section "Skills 워크스페이스 연결"

# 소스 목록을 한 번만 만들어 4개 CLI fan-out 이 공유한다 (issue #1652).
SKILL_SOURCE_LIST="$(collect_skill_sources)"

# 소스가 하나도 없으면 아무것도 하지 않고 끝낸다. 그냥 진행하면 아래 fan-out 의
# stale prune 이 "이 이름은 더 이상 소스가 아니다" 라고 판단해 이미 합성된 링크를
# 전부 지운다 — 워크스페이스를 아직 clone 하지 않은 PC 에서 setup 한 번으로 모든
# 하네스의 skill 이 사라지는 시나리오다 (#1680).
if [ -z "$SKILL_SOURCE_LIST" ]; then
    log_warning "skill 소스가 없습니다 — 합성을 건너뜁니다 (루트: ${WORKSPACE_ROOT_RESOLVED:-<미설정>})"
    log_info "marketplace repo 를 \${WORKSPACE_ROOT:-\$HOME/para/project/skills} 아래에 clone 한 뒤 다시 실행하세요."
    exit 0
fi

workspace_skill_count="$(printf '%s\n' "$SKILL_SOURCE_LIST" | grep -c .)"
log_info "[workspace] ${workspace_skill_count}개 skill 발견 (루트: $WORKSPACE_ROOT_RESOLVED)"

# 1. OpenCode: entry-level 합성 (issue #791 — 5 CLI 공통 layout)
OPENCODE_SKILLS="${HOME}/.config/opencode/skills"
if [ ! -d "${HOME}/.config/opencode" ]; then
    log_warning "OpenCode 설정 디렉토리가 없습니다. 건너뜁니다: ${HOME}/.config/opencode"
else
    link_skills_compose "opencode" "$OPENCODE_SKILLS"
fi

# 2. Codex: .system 보존 + custom skill 디렉토리 symlink
CODEX_HOME_LIST="$(collect_codex_homes)"
if [ -z "$CODEX_HOME_LIST" ]; then
    log_warning "Codex 설정 디렉토리가 없습니다. 건너뜁니다: ~/.codex 또는 ~/.config/codex"
else
    while IFS= read -r codex_home; do
        [ -n "$codex_home" ] || continue

        CODEX_SKILLS="${codex_home}/skills"
        codex_can_manage=1

        # 기존에 전체 dir symlink였다면 해제 후 codex 전용 방식으로 마이그레이션.
        # 끊어진 링크가 #1680 이 삭제한 dotfiles SSOT 를 가리키던 예전 링크일
        # 때만 같은 취급 — 그 외의 끊어진 링크는 사용자 symlink 취급으로 보존한다
        # (agy+codex FOLLOW-UP, PR #1729).
        if [ -L "$CODEX_SKILLS" ]; then
            codex_link_target="$(readlink -f "$CODEX_SKILLS" 2>/dev/null)"
            if skill_source_is_managed "$codex_link_target" || _ssot_link_is_legacy_stale "$CODEX_SKILLS"; then
                rm -f "$CODEX_SKILLS"
            else
                log_warning "Codex skills 경로가 사용자 symlink입니다. 건너뜁니다: $CODEX_SKILLS"
                codex_can_manage=0
            fi
        fi

        if [ "$codex_can_manage" -eq 1 ]; then
            mkdir -p "$CODEX_SKILLS"
            link_skills_individual_codex "$CODEX_SKILLS"
        fi
    done <<< "$CODEX_HOME_LIST"
fi

# 3. Gemini: entry-level 합성 (issue #791 — 5 CLI 공통 layout)
GEMINI_SKILLS="${HOME}/.gemini/skills"
if [ ! -d "${HOME}/.gemini" ]; then
    log_warning "Gemini 설정 디렉토리가 없습니다. 건너뜁니다: ${HOME}/.gemini"
else
    link_skills_compose "gemini" "$GEMINI_SKILLS"
fi

# 3b. Antigravity CLI (agy): 자체 Global Customizations Root 에서 합성 (#1731).
#     ~/.gemini 를 공유하지만 skills 검색 경로는 상속하지 않는다 — 근거는
#     파일 상단 헤더 주석 참고.
#
#     설치 판별은 상태 디렉토리 **또는** PATH 상의 바이너리다 (PR #1734 agy
#     FOLLOW-UP): 디렉토리만 보면 바이너리를 막 설치했고 아직 한 번도 실행하지
#     않은 환경 — 또는 토큰을 정리한 뒤 — 에서 조용히 스킵된다. 반대로 바이너리만
#     보면 순정 Gemini PC 에서 오탐할 일이 없다(agy 가 없으면 `command -v` 도
#     실패). 둘 중 하나라도 잡히면 합성한다.
_agy_is_installed() {
    [ -d "${HOME}/.gemini/antigravity-cli" ] && return 0
    command -v agy >/dev/null 2>&1
}

AGY_SKILLS="${HOME}/.gemini/config/skills"
if _agy_is_installed; then
    link_skills_compose "agy" "$AGY_SKILLS"
else
    log_warning "Antigravity(agy) 를 찾지 못했습니다. 건너뜁니다: ${HOME}/.gemini/antigravity-cli / PATH"
fi

# 4. Hermes: 전용 네임스페이스 서브디렉토리에서 entry-level 합성 (issue #1376)
#    루트를 직접 합성하지 않는 이유는 파일 상단 "Hermes 예외" 참고.
HERMES_SKILLS="${HOME}/.hermes/skills/dotfiles"
if [ ! -d "${HOME}/.hermes" ]; then
    log_warning "Hermes 설정 디렉토리가 없습니다. 건너뜁니다: ${HOME}/.hermes"
else
    link_skills_compose "hermes" "$HERMES_SKILLS"
fi

# --- Verify ---

ux_section "Skills 워크스페이스 연결 확인"

verify_link() {
    local tool="$1"
    local path="$2"
    local mode="$3"   # "compose" or "codex"

    if [ "$mode" = "compose" ]; then
        # Entry-level 합성: 실제 디렉토리 + child symlink 카운트.
        local count
        if [ -d "$path" ] && [ ! -L "$path" ]; then
            count=$(find "$path" -mindepth 1 -maxdepth 1 -type l 2>/dev/null | wc -l)
            log_dim "✓ [$tool] $path (entry symlink: ${count}개)"
        else
            log_warning "[$tool] entry-level 합성 디렉토리 확인 실패: $path"
        fi
    else
        local link_count
        local system_state
        link_count=$(find "$path" -mindepth 1 -maxdepth 1 -type l 2>/dev/null | wc -l)
        if [ -d "$path/.system" ]; then
            system_state="present"
        else
            system_state="missing"
        fi
        log_dim "✓ [$tool] $path (custom symlink: ${link_count}개, .system: ${system_state})"
    fi
}

[ -d "${HOME}/.config/opencode" ] && verify_link "opencode" "$OPENCODE_SKILLS" "compose"
if [ -n "${CODEX_HOME_LIST:-}" ]; then
    while IFS= read -r codex_home; do
        [ -n "$codex_home" ] || continue
        verify_link "codex" "${codex_home}/skills" "codex"
    done <<< "$CODEX_HOME_LIST"
fi
[ -d "${HOME}/.gemini" ] && verify_link "gemini" "$GEMINI_SKILLS" "compose"
_agy_is_installed && verify_link "agy" "$AGY_SKILLS" "compose"
[ -d "${HOME}/.hermes" ] && verify_link "hermes" "$HERMES_SKILLS" "compose"

ux_success "Skills 워크스페이스 연결 완료"
