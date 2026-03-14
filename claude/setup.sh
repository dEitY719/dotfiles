#!/bin/bash

# claude/setup.sh: Claude Code environment setup
#
# PURPOSE: Set up Claude Code configuration with symbolic links
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
#
# SPECIAL INITIALIZATION (why this file is REQUIRED):
#   1. Creates ~/.claude/settings.json symlink (Claude Code settings)
#   2. Creates ~/.claude/statusline-command.sh symlink (status line script)
#   3. Creates ~/.claude/skills symlink (custom skills directory)
#   4. Creates ~/.claude/projects/GLOBAL/memory symlink (global memory)
#   5. Verifies ~/.claude directory structure
#
# These files/directories are version-controlled in dotfiles and should
# be managed via symbolic links for consistency across machines.
#
# See SETUP_GUIDE.md for more information

# --- Constants ---

# Initialize DOTFILES_ROOT
_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_ROOT="$(cd "$(dirname "$_SCRIPT_PATH")/.." && pwd)"
CLAUDE_DOTFILES="${DOTFILES_ROOT}/claude"

# Home directory locations
HOME_CLAUDE="${HOME}/.claude"
HOME_SETTINGS="${HOME_CLAUDE}/settings.json"
HOME_STATUSLINE="${HOME_CLAUDE}/statusline-command.sh"
HOME_SKILLS="${HOME_CLAUDE}/skills"
HOME_GLOBAL_MEMORY="${HOME_CLAUDE}/projects/GLOBAL/memory"

# Dotfiles source locations
CLAUDE_SETTINGS_SOURCE="${CLAUDE_DOTFILES}/settings.json"
CLAUDE_STATUSLINE_SOURCE="${CLAUDE_DOTFILES}/statusline-command.sh"
CLAUDE_SKILLS_SOURCE="${CLAUDE_DOTFILES}/skills"
CLAUDE_GLOBAL_MEMORY_SOURCE="${CLAUDE_DOTFILES}/global-memory"

# Load UX library (unified library at shell-common/tools/ux_lib/)
UX_LIB="${DOTFILES_ROOT}/shell-common/tools/ux_lib/ux_lib.sh"
if [ -f "$UX_LIB" ]; then
    source "$UX_LIB"
else
    echo "Error: UX library not found at $UX_LIB"
    exit 1
fi

# --- Logging Compatibility Functions ---

log_info() { ux_info "$1"; }
log_error() { ux_error "$1"; }
log_critical() {
    ux_error "$1"
    exit 1
}
log_dim() { echo "${UX_DIM}$1${UX_RESET}"; }
log_debug() { echo "${UX_MUTED}[DEBUG] $1${UX_RESET}"; }
log_warning() { ux_warning "$1"; }

log_error_and_exit() {
    log_critical "$1"
}

# --- Functions ---

backup_file() {
    local file_to_backup="$1"
    local backup_destination="$2"
    if [ -e "$file_to_backup" ]; then
        log_info "백업 파일 생성: $file_to_backup -> $backup_destination"
        if [ -d "$file_to_backup" ]; then
            cp -r "$file_to_backup" "$backup_destination" || log_error_and_exit "백업 디렉토리 생성 실패: $file_to_backup"
        else
            cp "$file_to_backup" "$backup_destination" || log_error_and_exit "백업 파일 생성 실패: $file_to_backup"
        fi
    fi
}

create_symlink() {
    local target="$1"
    local link_name="$2"

    if [ -L "$link_name" ]; then
        log_dim "기존 심볼릭 링크 제거: $link_name"
        rm "$link_name" || log_error_and_exit "기존 심볼릭 링크 제거 실패: $link_name"
    elif [ -f "$link_name" ] || [ -d "$link_name" ]; then
        log_warning "경고: $link_name 가 심볼릭 링크가 아닙니다. 백업 후 제거합니다."
        backup_file "$link_name" "${link_name}-$(date +%Y%m%d%H%M%S)-original"
        rm -rf "$link_name" || log_error_and_exit "기존 파일/디렉토리 제거 실패: $link_name"
    fi

    log_info "심볼릭 링크 생성: $link_name -> $target"
    ln -s "$target" "$link_name" || log_error_and_exit "심볼릭 링크 생성 실패: $link_name -> $target"
}

setup_skills_mount() {
    local sudoers_file="/etc/sudoers.d/claude-skills-mount"

    log_info "Skills 디렉토리 bind mount 설정"

    # Check if sudoers file already exists
    if [ -f "$sudoers_file" ]; then
        log_dim "✓ sudoers 설정이 이미 존재합니다"
        return 0
    fi

    # Create sudoers configuration
    log_info "sudoers 파일 생성: $sudoers_file"
    cat << EOF | sudo tee "$sudoers_file" > /dev/null
# Allow passwordless bind mount for Claude Code skills directory
# Created by dotfiles/claude/setup.sh
${USER} ALL=(ALL) NOPASSWD: /bin/mount --bind ${CLAUDE_SKILLS_SOURCE} ${HOME_SKILLS}
${USER} ALL=(ALL) NOPASSWD: /usr/bin/mount --bind ${CLAUDE_SKILLS_SOURCE} ${HOME_SKILLS}
${USER} ALL=(ALL) NOPASSWD: /bin/umount ${HOME_SKILLS}
${USER} ALL=(ALL) NOPASSWD: /usr/bin/umount ${HOME_SKILLS}
EOF

    if [ $? -ne 0 ]; then
        log_error "sudoers 파일 생성 실패"
        return 1
    fi

    # Set proper permissions
    log_info "sudoers 파일 권한 설정"
    sudo chmod 440 "$sudoers_file"

    if [ $? -eq 0 ]; then
        log_dim "✓ sudoers 설정 완료"
    else
        log_error "sudoers 파일 권한 설정 실패"
        return 1
    fi
}

# --- Main Script Logic ---

log_debug "\n--- Claude Code dotfiles setup 시작 ---"

# ~/.claude 디렉토리 확인 및 생성
if [ ! -d "$HOME_CLAUDE" ]; then
    log_info "~/.claude 디렉토리 생성"
    mkdir -p "$HOME_CLAUDE" || log_error_and_exit "~/.claude 디렉토리 생성 실패"
fi

# settings.json 파일 존재 여부 확인
if [ ! -f "$CLAUDE_SETTINGS_SOURCE" ]; then
    log_error_and_exit "settings.json 파일이 '${CLAUDE_SETTINGS_SOURCE}' 경로에 존재하지 않습니다."
fi

# statusline-command.sh 파일 존재 여부 확인
if [ ! -f "$CLAUDE_STATUSLINE_SOURCE" ]; then
    log_error_and_exit "statusline-command.sh 파일이 '${CLAUDE_STATUSLINE_SOURCE}' 경로에 존재하지 않습니다."
fi

# skills 디렉토리 존재 여부 확인
if [ ! -d "$CLAUDE_SKILLS_SOURCE" ]; then
    log_error_and_exit "skills 디렉토리가 '${CLAUDE_SKILLS_SOURCE}' 경로에 존재하지 않습니다."
fi

# global-memory 디렉토리 존재 여부 확인
if [ ! -d "$CLAUDE_GLOBAL_MEMORY_SOURCE" ]; then
    log_error_and_exit "global-memory 디렉토리가 '${CLAUDE_GLOBAL_MEMORY_SOURCE}' 경로에 존재하지 않습니다."
fi

# settings.json 심볼릭 링크 생성
create_symlink "$CLAUDE_SETTINGS_SOURCE" "$HOME_SETTINGS"

# statusline-command.sh 심볼릭 링크 생성
create_symlink "$CLAUDE_STATUSLINE_SOURCE" "$HOME_STATUSLINE"

# skills 디렉토리 생성 (bind mount 사용)
if [ ! -d "$HOME_SKILLS" ]; then
    log_info "~/.claude/skills 디렉토리 생성"
    mkdir -p "$HOME_SKILLS" || log_error_and_exit "~/.claude/skills 디렉토리 생성 실패"
fi

# skills bind mount를 위한 sudoers 설정
setup_skills_mount

# global memory 디렉토리 심볼릭 링크 생성
if [ ! -d "$(dirname "$HOME_GLOBAL_MEMORY")" ]; then
    log_info "~/.claude/projects/GLOBAL 디렉토리 생성"
    mkdir -p "$(dirname "$HOME_GLOBAL_MEMORY")" || log_error_and_exit "~/.claude/projects/GLOBAL 디렉토리 생성 실패"
fi
create_symlink "$CLAUDE_GLOBAL_MEMORY_SOURCE" "$HOME_GLOBAL_MEMORY"

# --- Verify Links ---

log_debug "\n--- 심볼릭 링크 확인 ---"

if [ -L "$HOME_SETTINGS" ]; then
    log_dim "✓ settings.json 심볼릭 링크 확인됨"
else
    log_error_and_exit "settings.json 심볼릭 링크 생성 실패"
fi

if [ -L "$HOME_STATUSLINE" ]; then
    log_dim "✓ statusline-command.sh 심볼릭 링크 확인됨"
else
    log_error_and_exit "statusline-command.sh 심볼릭 링크 생성 실패"
fi

if [ -d "$HOME_SKILLS" ]; then
    log_dim "✓ skills 디렉토리 확인됨"
else
    log_error_and_exit "skills 디렉토리 생성 실패"
fi

if [ -L "$HOME_GLOBAL_MEMORY" ]; then
    log_dim "✓ global memory 심볼릭 링크 확인됨"
else
    log_error_and_exit "global memory 심볼릭 링크 생성 실패"
fi

# --- Completion Messages ---

log_debug "--- Claude Code dotfiles setup 완료 ---"
echo ""

ux_success "Claude Code 설정이 완료되었습니다!"
ux_info "다음 설정이 적용되었습니다:"
ux_bullet "~/.claude/settings.json → ~/dotfiles/claude/settings.json (symlink)"
ux_bullet "~/.claude/statusline-command.sh → ~/dotfiles/claude/statusline-command.sh (symlink)"
ux_bullet "~/.claude/skills ← ~/dotfiles/claude/skills (bind mount)"
ux_bullet "~/.claude/projects/GLOBAL/memory → ~/dotfiles/claude/global-memory (symlink)"
ux_bullet "/etc/sudoers.d/claude-skills-mount (passwordless mount)"
echo ""

ux_section "다음 단계"
ux_bullet "새 쉘을 열면 skills가 자동으로 bind mount됩니다"
ux_bullet "Claude Code 재시작하여 변경 사항 적용"
ux_bullet "필요시 설정 파일 편집: ${UX_BOLD}vim ~/dotfiles/claude/settings.json${UX_RESET}"
echo ""

exit 0
