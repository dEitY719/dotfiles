#!/bin/bash

# scripts/setup-skills-ssot.sh: Skills SSOT 연결 설정
#
# PURPOSE: claude/skills/를 SSOT로 삼아 OpenCode·Codex·Gemini에 연결
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
#
# 연결 전략:
#   - 전체 디렉토리 symlink: tools skills dir가 없거나 빈 경우
#     ~/.config/opencode/skills/ → ~/dotfiles/claude/skills/
#     ~/.gemini/skills/          → ~/dotfiles/claude/skills/
#   - Codex 전용 개별 연결: skill 디렉토리는 실제 폴더로 만들고
#     .system 디렉토리는 로컬 보존, 나머지 custom skill 디렉토리는 symlink
#     ~/.codex/skills/.system                          ← local (codex managed)
#     ~/.codex/skills/<custom-skill>                   → ~/dotfiles/claude/skills/<custom-skill>
#
#   - Codex 선택적 연결: claude/skills/.codex-allowlist 가 존재하고 비어 있지 않으면
#     해당 파일에 나열된 skill 만 연결되고 나머지 SSOT skill 은 codex 관리 대상에서 제거됨.
#     description 합계가 Codex 의 2% 컨텍스트 예산 (~5440자) 을 초과해 트렁케이션이
#     발생하는 것을 막는 용도. 한 줄에 하나의 skill 디렉토리 이름, '#' 으로 시작하는
#     주석과 빈 줄은 무시됨. 파일이 없거나 모두 비어 있으면 종전대로 전체 연결.
#
# ~/.claude/skills 는 claude/setup.sh (bind mount) 가 관리

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

log_info() { ux_info "$1"; }
log_error() { ux_error "$1"; }
log_dim() { echo "${UX_DIM}$1${UX_RESET}"; }
log_warning() { ux_warning "$1"; }
log_critical() { ux_error "$1"; exit 1; }

CODEX_MANAGED_MARKER=".dotfiles-skill-source"
CODEX_ALLOWLIST_FILE="${SKILLS_SOURCE}/.codex-allowlist"

# --- Helper Functions ---

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

# 전체 디렉토리를 SSOT로 symlink
# Usage: link_skills_dir <tool_name> <target_path>
link_skills_dir() {
    local tool="$1"
    local target="$2"

    # 이미 SSOT를 가리키는 symlink면 skip
    if [ -L "$target" ]; then
        local current_target
        current_target="$(readlink -f "$target" 2>/dev/null)"
        if [ "$current_target" = "$(readlink -f "$SKILLS_SOURCE")" ]; then
            log_dim "✓ [$tool] skills symlink 이미 연결됨: $target"
            return 0
        fi
        log_dim "[$tool] 기존 symlink 교체: $target"
        rm "$target"
    elif [ -d "$target" ]; then
        # 디렉토리가 존재하면 백업 후 제거
        local backup="${target}-$(date +%Y%m%d%H%M%S)-backup"
        log_warning "[$tool] 기존 디렉토리 백업: $target -> $backup"
        mv "$target" "$backup"
    fi

    log_info "[$tool] skills symlink 생성: $target -> $SKILLS_SOURCE"
    ln -s "$SKILLS_SOURCE" "$target" || log_critical "[$tool] symlink 생성 실패: $target"
}

# 개별 skill을 SSOT에서 symlink (기존 디렉토리 보존)
# Usage: link_skills_individual <tool_name> <target_dir>
link_skills_individual() {
    local tool="$1"
    local target_dir="$2"
    local linked=0
    local skipped=0

    for skill_path in "$SKILLS_SOURCE"/*/; do
        [ -d "$skill_path" ] || continue
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
    done

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
    local source_root
    source_root="$(readlink -f "$SKILLS_SOURCE")"

    mkdir -p "$target_dir"

    for skill_path in "$SKILLS_SOURCE"/*/; do
        [ -d "$skill_path" ] || continue

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
    done

    local existing_skill_entry
    for existing_skill_entry in "$target_dir"/*; do
        [ -e "$existing_skill_entry" ] || [ -L "$existing_skill_entry" ] || continue

        local existing_name
        existing_name="$(basename "$existing_skill_entry")"
        if [ "$existing_name" = ".system" ]; then
            continue
        fi

        if [ -d "${SKILLS_SOURCE}/${existing_name}" ] && \
           codex_skill_is_allowed "$existing_name" "$allowlist"; then
            continue
        fi

        if [ -L "$existing_skill_entry" ]; then
            local stale_target
            stale_target="$(readlink -f "$existing_skill_entry" 2>/dev/null || true)"
            case "$stale_target" in
                "$source_root"/*)
                    rm -f "$existing_skill_entry" || {
                        log_error "[codex] stale skill 제거 실패: $existing_skill_entry"
                        continue
                    }
                    pruned=$((pruned + 1))
                    continue
                    ;;
            esac

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

log_dim "\n--- Skills SSOT 연결 시작 ---"

# SSOT 존재 확인
if [ ! -d "$SKILLS_SOURCE" ]; then
    log_critical "SSOT 디렉토리가 없습니다: $SKILLS_SOURCE"
fi

# 1. OpenCode: 전체 디렉토리 symlink
OPENCODE_SKILLS="${HOME}/.config/opencode/skills"
if [ ! -d "${HOME}/.config/opencode" ]; then
    log_warning "OpenCode 설정 디렉토리가 없습니다. 건너뜁니다: ${HOME}/.config/opencode"
else
    link_skills_dir "opencode" "$OPENCODE_SKILLS"
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

# 3. Gemini: 전체 디렉토리 symlink
GEMINI_SKILLS="${HOME}/.gemini/skills"
if [ ! -d "${HOME}/.gemini" ]; then
    log_warning "Gemini 설정 디렉토리가 없습니다. 건너뜁니다: ${HOME}/.gemini"
else
    link_skills_dir "gemini" "$GEMINI_SKILLS"
fi

# --- Verify ---

log_dim "\n--- Skills SSOT 연결 확인 ---"

verify_link() {
    local tool="$1"
    local path="$2"
    local mode="$3"   # "dir" or "individual" or "codex"

    if [ "$mode" = "dir" ]; then
        if [ -L "$path" ]; then
            log_dim "✓ [$tool] $path -> $(readlink "$path")"
        else
            log_warning "[$tool] symlink 확인 실패: $path"
        fi
    elif [ "$mode" = "individual" ]; then
        local count
        count=$(find "$path" -maxdepth 1 -type l 2>/dev/null | wc -l)
        log_dim "✓ [$tool] $path (개별 symlink: ${count}개)"
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

[ -d "${HOME}/.config/opencode" ] && verify_link "opencode" "$OPENCODE_SKILLS" "dir"
if [ -n "${CODEX_HOME_LIST:-}" ]; then
    while IFS= read -r codex_home; do
        [ -n "$codex_home" ] || continue
        verify_link "codex" "${codex_home}/skills" "codex"
    done <<< "$CODEX_HOME_LIST"
fi
[ -d "${HOME}/.gemini" ] && verify_link "gemini" "$GEMINI_SKILLS" "dir"

log_dim "--- Skills SSOT 연결 완료 ---\n"
