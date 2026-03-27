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
#   - 개별 skill symlink: tools skills dir에 기존 내용이 있는 경우
#     ~/.codex/skills/<skill>/   → ~/dotfiles/claude/skills/<skill>/
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

# 2. Codex: 개별 skill symlink (.system 보존)
CODEX_SKILLS="${HOME}/.codex/skills"
if [ ! -d "${HOME}/.codex" ]; then
    log_warning "Codex 설정 디렉토리가 없습니다. 건너뜁니다: ${HOME}/.codex"
elif [ ! -d "$CODEX_SKILLS" ]; then
    # skills 디렉토리 자체가 없으면 전체 symlink
    link_skills_dir "codex" "$CODEX_SKILLS"
else
    # 기존 skills 디렉토리 있음 (.system 등 보존) → 개별 symlink
    link_skills_individual "codex" "$CODEX_SKILLS"
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
    local mode="$3"   # "dir" or "individual"

    if [ "$mode" = "dir" ]; then
        if [ -L "$path" ]; then
            log_dim "✓ [$tool] $path -> $(readlink "$path")"
        else
            log_warning "[$tool] symlink 확인 실패: $path"
        fi
    else
        local count
        count=$(find "$path" -maxdepth 1 -type l 2>/dev/null | wc -l)
        log_dim "✓ [$tool] $path (개별 symlink: ${count}개)"
    fi
}

[ -d "${HOME}/.config/opencode" ] && verify_link "opencode" "$OPENCODE_SKILLS" "dir"
if [ -d "${HOME}/.codex" ]; then
    if [ -L "$CODEX_SKILLS" ]; then
        verify_link "codex" "$CODEX_SKILLS" "dir"
    else
        verify_link "codex" "$CODEX_SKILLS" "individual"
    fi
fi
[ -d "${HOME}/.gemini" ] && verify_link "gemini" "$GEMINI_SKILLS" "dir"

log_dim "--- Skills SSOT 연결 완료 ---\n"
