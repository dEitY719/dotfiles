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
#     SKILL.md는 실파일 copy, 나머지 항목(references/, scripts/...)은 symlink
#     ~/.codex/skills/<skill>/SKILL.md                ← copy
#     ~/.codex/skills/<skill>/<entry(except SKILL.md)> → ~/dotfiles/claude/skills/<skill>/<entry>
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

# --- Helper Functions ---

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

# Codex는 symlink된 SKILL.md를 인식하지 못할 수 있어,
# skill 디렉토리는 실디렉토리로 유지하고 SKILL.md는 copy, 나머지는 symlink 한다.
# Usage: link_skills_individual_codex <target_dir>
link_skills_individual_codex() {
    local target_dir="$1"
    local linked=0
    local migrated=0
    local skipped=0
    local pruned=0
    local prune_skipped=0

    mkdir -p "$target_dir"

    for skill_path in "$SKILLS_SOURCE"/*/; do
        [ -d "$skill_path" ] || continue

        local skill_name
        skill_name="$(basename "$skill_path")"

        local skill_target_dir="${target_dir}/${skill_name}"
        local marker_file="${skill_target_dir}/${CODEX_MANAGED_MARKER}"
        local source_realpath
        source_realpath="$(readlink -f "$skill_path")"

        if [ -L "$skill_target_dir" ]; then
            local current_target
            current_target="$(readlink -f "$skill_target_dir" 2>/dev/null)"
            if [ "$current_target" = "$source_realpath" ]; then
                if [ -e "$skill_target_dir" ] || [ -L "$skill_target_dir" ]; then
                    rm -f "$skill_target_dir"
                fi
                migrated=$((migrated + 1))
            else
                log_dim "[codex] 기존 사용자 symlink 보존: $skill_target_dir"
                skipped=$((skipped + 1))
                continue
            fi
        fi

        if [ -d "$skill_target_dir" ]; then
            if [ -f "$marker_file" ] && grep -Fqx "$source_realpath" "$marker_file"; then
                :
            elif [ -f "$marker_file" ]; then
                printf "%s\n" "$source_realpath" > "$marker_file"
            elif [ -z "$(ls -A "$skill_target_dir" 2>/dev/null)" ]; then
                printf "%s\n" "$source_realpath" > "$marker_file"
            else
                log_dim "[codex] 기존 디렉토리 보존: $skill_target_dir"
                skipped=$((skipped + 1))
                continue
            fi
        else
            mkdir -p "$skill_target_dir"
            printf "%s\n" "$source_realpath" > "$marker_file"
        fi

        local entry_path
        for entry_path in "$skill_path"* "$skill_path".*; do
            [ -e "$entry_path" ] || continue

            local entry_name
            entry_name="$(basename "$entry_path")"
            if [ "$entry_name" = "." ] || [ "$entry_name" = ".." ]; then
                continue
            fi

            local entry_target="${skill_target_dir}/${entry_name}"
            local entry_source_realpath
            entry_source_realpath="$(readlink -f "$entry_path")"

            if [ "$entry_name" = "SKILL.md" ]; then
                if [ -L "$entry_target" ]; then
                    rm -f "$entry_target"
                elif [ -e "$entry_target" ] && [ ! -f "$entry_target" ]; then
                    log_warning "[codex] SKILL.md 엔트리 보존(일반 파일 아님): $entry_target"
                    continue
                fi

                if [ -f "$entry_target" ] && cmp -s "$entry_path" "$entry_target"; then
                    continue
                fi

                cp "$entry_path" "$entry_target" || {
                    log_error "[codex] SKILL.md copy 실패: $entry_target"
                    continue
                }
                continue
            fi

            if [ -L "$entry_target" ]; then
                local current_entry_target
                current_entry_target="$(readlink -f "$entry_target" 2>/dev/null)"
                if [ "$current_entry_target" = "$entry_source_realpath" ]; then
                    continue
                fi
                rm "$entry_target"
            elif [ -e "$entry_target" ]; then
                log_dim "[codex] 기존 엔트리 보존: $entry_target"
                continue
            fi

            ln -s "$entry_path" "$entry_target" || {
                log_error "[codex] skill 엔트리 symlink 생성 실패: $entry_target"
                continue
            }
        done

        if [ -e "${skill_target_dir}/SKILL.md" ]; then
            linked=$((linked + 1))
        else
            log_warning "[codex] SKILL.md 미연결: $skill_target_dir"
        fi
    done

    local existing_skill_dir
    for existing_skill_dir in "$target_dir"/*/; do
        [ -d "$existing_skill_dir" ] || continue

        local existing_name
        existing_name="$(basename "$existing_skill_dir")"
        if [ "$existing_name" = ".system" ]; then
            continue
        fi

        local existing_marker
        existing_marker="${existing_skill_dir%/}/${CODEX_MANAGED_MARKER}"
        [ -f "$existing_marker" ] || continue

        if [ -d "${SKILLS_SOURCE}/${existing_name}" ]; then
            continue
        fi

        local has_nonsymlink=0
        local existing_entry
        for existing_entry in "${existing_skill_dir%/}"/* "${existing_skill_dir%/}"/.*; do
            [ -e "$existing_entry" ] || continue
            local existing_entry_name
            existing_entry_name="$(basename "$existing_entry")"
            if [ "$existing_entry_name" = "." ] || [ "$existing_entry_name" = ".." ] || [ "$existing_entry_name" = "$CODEX_MANAGED_MARKER" ]; then
                continue
            fi
            if [ "$existing_entry_name" = "SKILL.md" ] && [ -f "$existing_entry" ]; then
                continue
            fi
            if [ ! -L "$existing_entry" ]; then
                has_nonsymlink=1
                break
            fi
        done

        if [ "$has_nonsymlink" -eq 1 ]; then
            log_warning "[codex] stale skill 보존(사용자 데이터 감지): ${existing_skill_dir%/}"
            prune_skipped=$((prune_skipped + 1))
            continue
        fi

        rm -rf "${existing_skill_dir%/}" || {
            log_error "[codex] stale skill 제거 실패: ${existing_skill_dir%/}"
            continue
        }
        pruned=$((pruned + 1))
    done

    log_info "[codex] skill 연결 완료: ${linked}개 준비, ${migrated}개 마이그레이션, ${skipped}개 기존 유지, ${pruned}개 정리, ${prune_skipped}개 보존"
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

# 2. Codex: skill 디렉토리는 실디렉토리, 내부 엔트리만 symlink (.system 보존)
CODEX_SKILLS="${HOME}/.codex/skills"
if [ ! -d "${HOME}/.codex" ]; then
    log_warning "Codex 설정 디렉토리가 없습니다. 건너뜁니다: ${HOME}/.codex"
else
    codex_can_manage=1
    # 기존에 전체 dir symlink였다면 해제 후 codex 전용 방식으로 마이그레이션
    if [ -L "$CODEX_SKILLS" ]; then
        local_codex_target="$(readlink -f "$CODEX_SKILLS" 2>/dev/null)"
        if [ "$local_codex_target" = "$(readlink -f "$SKILLS_SOURCE")" ]; then
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
        link_skills_individual_codex "$CODEX_SKILLS"
    fi
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
        local count
        count=$(find "$path" -mindepth 2 -maxdepth 2 -name "SKILL.md" 2>/dev/null | wc -l)
        log_dim "✓ [$tool] $path (SKILL.md 감지: ${count}개)"
    fi
}

[ -d "${HOME}/.config/opencode" ] && verify_link "opencode" "$OPENCODE_SKILLS" "dir"
if [ -d "${HOME}/.codex" ]; then
    verify_link "codex" "$CODEX_SKILLS" "codex"
fi
[ -d "${HOME}/.gemini" ] && verify_link "gemini" "$GEMINI_SKILLS" "dir"

log_dim "--- Skills SSOT 연결 완료 ---\n"
