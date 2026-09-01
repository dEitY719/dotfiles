#!/bin/bash

# scripts/setup-skills-ssot.sh: Skills SSOT 연결 설정
#
# PURPOSE: claude/skills/를 SSOT로 삼아 OpenCode·Codex·Gemini·Hermes에 연결
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
#
# 연결 전략 (issue #791 / #1376 — 5 CLI 모두 entry-level 합성):
#   - entry-level 합성 디렉토리 (#707 / #791 / #1376):
#     ~/.config/opencode/skills/<skill>     → ~/dotfiles/claude/skills/<skill>
#     ~/.gemini/skills/<skill>              → ~/dotfiles/claude/skills/<skill>
#     ~/.hermes/skills/dotfiles/<skill>     → ~/dotfiles/claude/skills/<skill>
#
#   - Hermes 예외 (#1376, NF-1): Hermes 는 다른 CLI 와 달리 ~/.hermes/skills/
#     루트를 자체 hub/curator 가 능동적으로 관리한다 (.hub/, .bundled_manifest,
#     .curator_state, .usage.json* 메타데이터 + apple/ github/ 등 카테고리
#     디렉토리). 루트에 직접 합성하면 그 네임스페이스와 충돌하므로,
#     전용 서브디렉토리 ~/.hermes/skills/dotfiles/ 안에서만 합성한다.
#
#   - Codex 전용 합성: .system 디렉토리는 로컬 보존
#     ~/.codex/skills/.system                          ← local (codex managed)
#     ~/.codex/skills/<custom-skill>                   → ~/dotfiles/claude/skills/<custom-skill>
#
#   - Codex 선택적 연결: claude/skills/.codex-allowlist 가 존재하고 비어 있지 않으면
#     해당 파일에 나열된 skill 만 연결되고 나머지 SSOT skill 은 codex 관리 대상에서 제거됨.
#     description 합계가 Codex 의 2% 컨텍스트 예산 (~5440자) 을 초과해 트렁케이션이
#     발생하는 것을 막는 용도. 한 줄에 하나의 skill 디렉토리 이름, '#' 으로 시작하는
#     주석과 빈 줄은 무시됨. 파일이 없거나 모두 비어 있으면 종전대로 전체 연결.
#
#   - 마이그레이션 (#791): 기존 opencode/gemini 의 디렉토리-단위 symlink 는
#     entry-level 합성으로 변환된다. 사용자가 직접 만든 symlink (target 이
#     SSOT 가 아닌 경우) 는 보존 + warn.
#
# ~/.claude*/skills 는 claude/setup.sh 가 entry-level 합성 디렉토리로 관리 (#707, F-8).
# 5 CLI 모두 동일 layout (Hermes 만 서브디렉토리 — 위 예외 참고) 이므로 외부에서
# 추가된 symlink 도 5 곳 전부에 동일하게 적용된다.
#
# Antigravity CLI (agy) 는 본 스크립트에 별도 분기가 없다 — agy 의 OAuth 토큰이
# ~/.gemini/antigravity-cli/ 에 저장되어 Gemini 런타임을 그대로 공유하므로
# ~/.gemini/skills 합성을 자동 상속한다. 상세: agy/AGENTS.md (Non-Goals).

# --- Constants ---

_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_ROOT="$(cd "$(dirname "$_SCRIPT_PATH")/.." && pwd)"
SKILLS_SOURCE="${DOTFILES_ROOT}/claude/skills"

# Load UX library
UX_LIB="${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
if [ -f "$UX_LIB" ]; then
    source "$UX_LIB"
else
    echo "Error: UX library not found at $UX_LIB"
    exit 1
fi

# 워크스페이스 소스 판별/열거의 SSOT (issue #1652 / #1410 F-6). Claude Code
# 계정 쪽(shell-common/tools/integrations/claude.sh)이 같은 파일을 읽으므로
# "무엇이 워크스페이스 skill 인가" 규칙이 두 벌로 갈라지지 않는다.
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
CODEX_ALLOWLIST_FILE="${SKILLS_SOURCE}/.codex-allowlist"

# --- Helper Functions ---

# 소스 루트의 정규화 경로. symlink 판별은 raw target 과 resolved target
# 양쪽에서 이뤄지므로(compose 는 `readlink`, codex 는 `readlink -f`) 두 형태를
# 모두 준비해 둔다. 존재하지 않는 경로에서도 실패하지 않도록 원본으로 폴백.
_realpath_or_self() {
    readlink -f "$1" 2>/dev/null || printf "%s" "$1"
}

SKILLS_SOURCE_REAL="$(_realpath_or_self "$SKILLS_SOURCE")"
# 빈 문자열 = 워크스페이스 없음/너무 넓음 → dotfiles SSOT 단독 동작(종전과 동일).
WORKSPACE_ROOT_RESOLVED="$(_skill_workspace_root || true)"
WORKSPACE_ROOT_REAL=""
[ -n "$WORKSPACE_ROOT_RESOLVED" ] \
    && WORKSPACE_ROOT_REAL="$(_realpath_or_self "$WORKSPACE_ROOT_RESOLVED")"

# 모든 skill 소스 디렉토리를 한 줄에 하나씩 표준출력으로 낸다.
#
# 소스는 두 곳 (issue #1652 / #1410 F-6):
#   1. dotfiles SSOT     ${SKILLS_SOURCE}/<skill>/
#   2. 워크스페이스 clone <root>/<repo>/skills/<skill>   (열거 규칙은 shell-common SSOT)
#
# dotfiles 를 먼저 내보내 이름 충돌 시 dotfiles 가 이긴다 — 이 이슈는 소스를
# **추가**만 하므로(NF-1) 기존 링크가 다른 곳으로 재조준돼선 안 된다. 워크스페이스
# repo 끼리 충돌하면 정렬 순서상 앞선 repo 가 이긴다(재현 가능한 결정).
# 진단 로그는 stdout 을 오염시키지 않도록 stderr 로 보낸다.
collect_skill_sources() {
    local seen="|"
    local skill_path skill_name

    for skill_path in "$SKILLS_SOURCE"/*/; do
        [ -d "$skill_path" ] || continue
        skill_name="$(basename "$skill_path")"
        seen="${seen}${skill_name}|"
        printf "%s\n" "$skill_path"
    done

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

    for root in "$SKILLS_SOURCE" "$SKILLS_SOURCE_REAL" \
                "$WORKSPACE_ROOT_RESOLVED" "$WORKSPACE_ROOT_REAL"; do
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

# Read codex allowlist file and emit one skill name per line.
# Strips comments (#...) and blank lines. Stdout is empty if no entries
# were found, allowing callers to detect "no allowlist" via -z check.
read_codex_allowlist() {
    local file="${1:-$CODEX_ALLOWLIST_FILE}"
    [ -f "$file" ] || return 0

    awk '
        {
            sub(/#.*/, "")        # strip inline comments
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            if (length($0) == 0) next
            print
        }
    ' "$file"
}

# Test whether a skill name is allowed.
# Args: <skill_name> <allowlist_text>
# Returns 0 if skill is allowed (allowlist empty OR skill listed), 1 otherwise.
codex_skill_is_allowed() {
    local skill="$1"
    local allowlist="$2"

    [ -z "$allowlist" ] && return 0

    case "
${allowlist}
" in
        *"
${skill}
"*) return 0 ;;
    esac
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
#   - target 이 SSOT 로 향하는 dir-symlink → 해제 후 합성으로 전환.
#   - target 이 사용자 symlink (다른 위치) → 보존 + warn (skip, 무손실).
#   - target 이 일반 파일 → 보존 + warn (사용자 데이터 가능성, skip).
#   - target 이 일반 디렉토리 → 합성 시도 (기존 entry 보존).
# Usage: link_skills_compose <tool_name> <target_dir>
link_skills_compose() {
    local tool="$1"
    local target="$2"
    local source_root
    source_root="$(readlink -f "$SKILLS_SOURCE")"

    # 1. Migrate legacy directory-symlink → real directory.
    if [ -L "$target" ]; then
        local current_target
        current_target="$(readlink -f "$target" 2>/dev/null)"
        if [ "$current_target" = "$source_root" ]; then
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
            if skill_source_is_managed "$current_link"; then
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
        skill_source_is_managed "$existing_target_path" || continue
        if [ ! -d "$existing_target_path" ]; then
            log_info "[$tool] stale entry 정리: $existing"
            rm -f "$existing"
            pruned=$((pruned + 1))
        fi
    done

    log_info "[$tool] skill 합성 완료: ${linked}개 신규, ${refreshed}개 갱신, ${skipped}개 보존, ${pruned}개 정리"
}

# 개별 skill을 SSOT에서 symlink (기존 디렉토리 보존)
# Usage: link_skills_individual <tool_name> <target_dir>
link_skills_individual() {
    local tool="$1"
    local target_dir="$2"
    local linked=0
    local skipped=0

    while IFS= read -r skill_path; do
        [ -n "$skill_path" ] || continue
        local skill_name
        skill_name="$(basename "$skill_path")"
        local link_target="${target_dir}/${skill_name}"

        if [ -L "$link_target" ]; then
            local current_target
            current_target="$(readlink -f "$link_target" 2>/dev/null)"
            if [ "$current_target" = "$(readlink -f "$skill_path")" ]; then
                skipped=$((skipped + 1))
                continue
            fi
            rm "$link_target"
        elif [ -d "$link_target" ]; then
            # 실제 디렉토리면 건너뜀 (도구 내장 스킬 보존)
            log_dim "[$tool] 내장 디렉토리 보존: $link_target"
            skipped=$((skipped + 1))
            continue
        fi

        ln -s "$skill_path" "$link_target" || {
            log_error "[$tool] skill symlink 생성 실패: $link_target"
            continue
        }
        linked=$((linked + 1))
    done <<< "$SKILL_SOURCE_LIST"

    log_info "[$tool] 개별 skill 연결 완료: ${linked}개 신규, ${skipped}개 기존 유지"
}

# Codex skills 연결:
# - .system 은 로컬 보존
# - custom skill 은 디렉토리 symlink (SSOT 직결)
# - 기존 copy/marker 레이아웃(.dotfiles-skill-source)은 자동 마이그레이션
# - allowlist 가 존재하면 그 안에 명시된 skill 만 연결 (Codex 컨텍스트 예산 보호)
# Usage: link_skills_individual_codex <target_dir> [allowlist_text]
link_skills_individual_codex() {
    local target_dir="$1"
    local allowlist="${2:-}"
    local linked=0
    local unchanged=0
    local migrated=0
    local skipped=0
    local pruned=0
    local prune_skipped=0
    local excluded=0

    mkdir -p "$target_dir"

    while IFS= read -r skill_path; do
        [ -n "$skill_path" ] || continue

        local skill_name
        skill_name="$(basename "$skill_path")"
        if [ "$skill_name" = ".system" ]; then
            continue
        fi

        if ! codex_skill_is_allowed "$skill_name" "$allowlist"; then
            excluded=$((excluded + 1))
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

            log_dim "[codex] 기존 사용자 symlink 보존: $skill_target"
            skipped=$((skipped + 1))
            continue
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

        if skill_source_path_for "$existing_name" >/dev/null && \
           codex_skill_is_allowed "$existing_name" "$allowlist"; then
            continue
        fi

        if [ -L "$existing_skill_entry" ]; then
            local stale_target
            stale_target="$(readlink -f "$existing_skill_entry" 2>/dev/null || true)"
            if skill_source_is_managed "$stale_target"; then
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

    if [ -n "$allowlist" ]; then
        log_info "[codex] skill 연결 완료: ${linked}개 신규, ${unchanged}개 유지, ${migrated}개 마이그레이션, ${skipped}개 보존, ${pruned}개 정리, ${prune_skipped}개 stale 보존, ${excluded}개 allowlist 제외"
    else
        log_info "[codex] skill 연결 완료: ${linked}개 신규, ${unchanged}개 유지, ${migrated}개 마이그레이션, ${skipped}개 보존, ${pruned}개 정리, ${prune_skipped}개 stale 보존"
    fi
}

# --- Main ---

ux_section "Skills SSOT 연결"

# SSOT 존재 확인
if [ ! -d "$SKILLS_SOURCE" ]; then
    log_critical "SSOT 디렉토리가 없습니다: $SKILLS_SOURCE"
fi

# 소스 목록을 한 번만 만들어 4개 CLI fan-out 이 공유한다 (issue #1652).
# fan-out 로직 자체는 그대로다 — 달라진 건 enumeration 뿐 (F-4).
SKILL_SOURCE_LIST="$(collect_skill_sources)"

if [ -n "$WORKSPACE_ROOT_RESOLVED" ]; then
    workspace_skill_count="$(printf '%s\n' "$SKILL_SOURCE_LIST" \
        | grep -c "^${WORKSPACE_ROOT_RESOLVED}/" || true)"
    log_info "[workspace] ${workspace_skill_count}개 skill 합류 (루트: $WORKSPACE_ROOT_RESOLVED)"
fi

# 1. OpenCode: entry-level 합성 (issue #791 — 5 CLI 공통 layout)
OPENCODE_SKILLS="${HOME}/.config/opencode/skills"
if [ ! -d "${HOME}/.config/opencode" ]; then
    log_warning "OpenCode 설정 디렉토리가 없습니다. 건너뜁니다: ${HOME}/.config/opencode"
else
    link_skills_compose "opencode" "$OPENCODE_SKILLS"
fi

# 2. Codex: .system 보존 + custom skill 디렉토리 symlink (선택적 allowlist 적용)
CODEX_HOME_LIST="$(collect_codex_homes)"
if [ -z "$CODEX_HOME_LIST" ]; then
    log_warning "Codex 설정 디렉토리가 없습니다. 건너뜁니다: ~/.codex 또는 ~/.config/codex"
else
    CODEX_ALLOWLIST_TEXT="$(read_codex_allowlist "$CODEX_ALLOWLIST_FILE")"
    if [ -n "$CODEX_ALLOWLIST_TEXT" ]; then
        codex_allowlist_count="$(printf '%s\n' "$CODEX_ALLOWLIST_TEXT" | grep -c .)"
        log_info "[codex] allowlist 적용: ${codex_allowlist_count}개 skill (출처: $CODEX_ALLOWLIST_FILE)"
    fi

    while IFS= read -r codex_home; do
        [ -n "$codex_home" ] || continue

        CODEX_SKILLS="${codex_home}/skills"
        codex_can_manage=1

        # 기존에 전체 dir symlink였다면 해제 후 codex 전용 방식으로 마이그레이션
        if [ -L "$CODEX_SKILLS" ]; then
            codex_link_target="$(readlink -f "$CODEX_SKILLS" 2>/dev/null)"
            if [ "$codex_link_target" = "$(readlink -f "$SKILLS_SOURCE")" ]; then
                if [ -e "$CODEX_SKILLS" ] || [ -L "$CODEX_SKILLS" ]; then
                    rm -f "$CODEX_SKILLS"
                fi
            else
                log_warning "Codex skills 경로가 사용자 symlink입니다. 건너뜁니다: $CODEX_SKILLS"
                codex_can_manage=0
            fi
        fi

        if [ "$codex_can_manage" -eq 1 ]; then
            mkdir -p "$CODEX_SKILLS"
            link_skills_individual_codex "$CODEX_SKILLS" "$CODEX_ALLOWLIST_TEXT"
        fi
    done <<< "$CODEX_HOME_LIST"
fi

# 3. Gemini: entry-level 합성 (issue #791 — 5 CLI 공통 layout)
#    agy 상속 근거는 파일 상단 헤더 주석 참고.
GEMINI_SKILLS="${HOME}/.gemini/skills"
if [ ! -d "${HOME}/.gemini" ]; then
    log_warning "Gemini 설정 디렉토리가 없습니다. 건너뜁니다: ${HOME}/.gemini"
else
    link_skills_compose "gemini" "$GEMINI_SKILLS"
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

ux_section "Skills SSOT 연결 확인"

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
[ -d "${HOME}/.hermes" ] && verify_link "hermes" "$HERMES_SKILLS" "compose"

ux_success "Skills SSOT 연결 완료"
