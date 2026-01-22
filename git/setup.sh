#!/bin/bash

# git/setup.sh: Git configuration setup
#
# PURPOSE: Set up git configuration symlinks
# WHEN TO RUN: Via ./setup.sh (do NOT run manually)
#
# SPECIAL FEATURES (why this file is REQUIRED):
#   1. Creates ~/.gitconfig symlink to git/.gitconfig
#   2. Provides user feedback using UX library
#   3. Ensures proper git configuration initialization
#
# See SETUP_GUIDE.md for more information

# --- Constants ---
# 현재 스크립트가 위치한 git 디렉토리의 절대 경로를 설정합니다.
DOTFILES_GIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Dotfiles repository의 루트 경로
DOTFILES_REPO_ROOT="$(cd "$DOTFILES_GIT_DIR/.." && pwd)"

# gitdotfiles의 특정 파일들
GIT_CONFIG_SOURCE="${DOTFILES_GIT_DIR}/.gitconfig"
GIT_HOOKS_SOURCE_DIR="${DOTFILES_GIT_DIR}/hooks"

# 홈 디렉토리와 repository에 생성될 심볼릭 링크의 대상 경로
HOME_GITCONFIG="${HOME}/.gitconfig"
REPO_GIT_HOOKS_DIR="${DOTFILES_REPO_ROOT}/.git/hooks"


# --- Logging Initialization ---
# ux_lib.sh를 로드합니다.
# setup.sh가 dotfiles/git에 있으므로, shell-common/tools/ux_lib는 ../shell-common/tools/ux_lib에 있습니다.
UX_LIB_SCRIPT="${DOTFILES_GIT_DIR}/../shell-common/tools/ux_lib/ux_lib.sh"


if [[ -f "${UX_LIB_SCRIPT}" ]]; then
    source "${UX_LIB_SCRIPT}"
else
    echo "CRITICAL ERROR: UX library script not found at ${UX_LIB_SCRIPT}. Exiting." >&2
    exit 1
fi


# --- Functions ---
# log_critical 함수를 사용하여 log_error_and_exit 대체
log_error_and_exit() {
    ux_error "$1"
    exit 1
}


backup_file() {
    local file_to_backup="$1"
    local backup_destination="$2"
    if [ -e "$file_to_backup" ]; then
        ux_info "백업 파일 생성: $file_to_backup -> $backup_destination"
        cp "$file_to_backup" "$backup_destination" || log_error_and_exit "백업 파일 생성 실패: $file_to_backup"
    fi
}


create_symlink() {
    local target="$1"
    local link_name="$2"

    if [ -L "$link_name" ]; then
        # ux_dim does not exist, use muted style or echo with UX_MUTED
        echo "${UX_MUTED}기존 심볼릭 링크 제거: $link_name${UX_RESET}"
        rm "$link_name" || log_error_and_exit "기존 심볼릭 링크 제거 실패: $link_name"
    elif [ -f "$link_name" ]; then
        ux_warning "경고: $link_name 가 심볼릭 링크가 아닌 일반 파일입니다. 백업 후 제거합니다."
        backup_file "$link_name" "${link_name}-$(date +%Y%m%d%H%M%S)-original"
        rm "$link_name" || log_error_and_exit "기존 파일 제거 실패: $link_name"
    fi

    echo "${UX_MUTED}심볼릭 링크 생성: $link_name -> $target${UX_RESET}"
    ln -s "$target" "$link_name" || log_error_and_exit "심볼릭 링크 생성 실패: $link_name -> $target"
}


# --- SSH Setup Functions ---
# SSH 키 존재 여부 확인
check_ssh_key_exists() {
    [ -f "${HOME}/.ssh/id_ed25519" ]
}


# SSH 에이전트 실행 여부 확인
check_ssh_agent_running() {
    [ -n "$SSH_AUTH_SOCK" ]
}


# GitHub SSH 연결 가능 여부 확인
check_github_ssh_access() {
    ssh -T git@github.samsungds.net >/dev/null 2>&1
}


# SSH 에이전트 시작
start_ssh_agent() {
    eval "$(ssh-agent -s)" >/dev/null 2>&1
    ux_info "SSH 에이전트가 시작되었습니다 (PID: $SSH_AGENT_PID)"
}


# SSH 키를 에이전트에 등록
register_ssh_key() {
    if check_ssh_key_exists; then
        ssh-add "${HOME}/.ssh/id_ed25519" >/dev/null 2>&1
        ux_success "SSH 키가 에이전트에 등록되었습니다"
        return 0
    else
        ux_warning "SSH 키를 찾을 수 없습니다: ${HOME}/.ssh/id_ed25519"
        return 1
    fi
}


# SSH 키 생성
generate_ssh_key() {
    local ssh_dir="${HOME}/.ssh"
    local key_path="${ssh_dir}/id_ed25519"

    mkdir -p "$ssh_dir" 2>/dev/null || true

    # SSH 키가 이미 있으면 건너뜀
    if [ -f "$key_path" ]; then
        ux_info "SSH 키가 이미 존재합니다: $key_path"
        return 0
    fi

    ux_info "SSH 키를 생성합니다..."
    ssh-keygen -t ed25519 -C "$(hostname)" -N "" -f "$key_path" >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        ux_success "SSH 키가 생성되었습니다: $key_path"
        ux_info "공개키: $(cat "${key_path}.pub")"
        return 0
    else
        ux_error "SSH 키 생성 실패"
        return 1
    fi
}


# Git 리모트를 SSH로 변경
configure_git_remote_ssh() {
    local repo_root="$1"
    local current_remote
    local new_remote

    if [ -z "$repo_root" ]; then
        return 0
    fi

    # 현재 리모트 URL 확인
    current_remote=$(git -C "$repo_root" remote get-url origin 2>/dev/null)

    if [ -z "$current_remote" ]; then
        return 0
    fi

    # HTTPS -> SSH 변환 필요 여부 확인
    if [[ "$current_remote" == https://github.samsungds.net/* ]]; then
        # https://github.samsungds.net/org/repo.git -> git@github.samsungds.net:org/repo.git
        new_remote=$(echo "$current_remote" | sed 's|https://github\.samsungds\.net/|git@github.samsungds.net:|')
        git -C "$repo_root" remote set-url origin "$new_remote" 2>/dev/null
        ux_success "Git 리모트가 SSH로 변경되었습니다"
        ux_info "  기존: $current_remote"
        ux_info "  변경: $new_remote"
    fi
}


# SSH 설정 자동화 (한 번에 처리)
setup_ssh_auto() {
    ux_header "SSH 설정 자동화 확인"

    # 1. SSH 키 확인 및 생성
    if ! check_ssh_key_exists; then
        ux_warning "SSH 키가 없습니다"
        generate_ssh_key || return 1
    else
        ux_success "SSH 키 존재: ${HOME}/.ssh/id_ed25519"
    fi

    # 2. SSH 에이전트 확인 및 시작
    if ! check_ssh_agent_running; then
        ux_warning "SSH 에이전트가 실행 중이 아닙니다"
        start_ssh_agent || return 1
    else
        ux_success "SSH 에이전트 실행 중"
    fi

    # 3. SSH 키를 에이전트에 등록
    register_ssh_key || return 1

    # 4. GitHub SSH 연결 테스트
    ux_info "GitHub SSH 연결을 테스트합니다..."
    if check_github_ssh_access; then
        ux_success "✓ GitHub SSH 연결 성공"
    else
        ux_warning "⚠ GitHub SSH 연결 실패"
        ux_info "다음 단계를 확인하세요:"
        ux_info "  1. 공개키를 GitHub에 등록했는지 확인"
        ux_info "  2. SSH 설정 가이드: git/doc/SSH_SETUP_GUIDE.md"
        return 1
    fi

    # 5. Git 리모트를 SSH로 변경 (해당 프로젝트)
    configure_git_remote_ssh "$DOTFILES_REPO_ROOT"

    ux_success "SSH 설정이 완료되었습니다"
}


# --- Main Script Logic ---
ux_header "Git dotfiles setup 시작"


# SSH 설정 자동화 (선택적, 실패해도 진행)
setup_ssh_auto || ux_warning "SSH 설정 중 일부 작업이 실패했습니다. 수동으로 구성하세요."
echo ""


# .gitconfig 심볼릭 링크 생성
if [ -f "$GIT_CONFIG_SOURCE" ]; then
    create_symlink "$GIT_CONFIG_SOURCE" "$HOME_GITCONFIG"
else
    ux_warning "경고: .gitconfig 파일이 '${GIT_CONFIG_SOURCE}' 경로에 없습니다. 심볼릭 링크를 생성하지 않습니다."
fi


# Git hooks 설정
# .git/hooks 디렉토리 생성 (필요시)
mkdir -p "$REPO_GIT_HOOKS_DIR" 2>/dev/null || true

# Pre-commit hook 심볼릭 링크 생성
# Source: git/hooks/pre-commit (tracked in git)
# Target: .git/hooks/pre-commit (symlink, not tracked)
if [ -f "${GIT_HOOKS_SOURCE_DIR}/pre-commit" ]; then
    PRE_COMMIT_TARGET="${REPO_GIT_HOOKS_DIR}/pre-commit"
    create_symlink "${GIT_HOOKS_SOURCE_DIR}/pre-commit" "$PRE_COMMIT_TARGET"
    chmod +x "${GIT_HOOKS_SOURCE_DIR}/pre-commit"
    ux_info "Pre-commit hook 설정 완료: ${PRE_COMMIT_TARGET}"
else
    ux_warning "경고: pre-commit hook 파일이 '${GIT_HOOKS_SOURCE_DIR}/pre-commit' 경로에 없습니다."
fi


# --- Global Git Hooks Setup ---
GLOBAL_HOOKS_DIR="${HOME}/.config/git/hooks"
GLOBAL_HOOK_SOURCE="${DOTFILES_GIT_DIR}/global-hooks/pre-commit"
GLOBAL_HOOK_TARGET="${GLOBAL_HOOKS_DIR}/pre-commit"

ux_info "Global Git Hooks 설정 시작"

if [ -f "$GLOBAL_HOOK_SOURCE" ]; then
    mkdir -p "$GLOBAL_HOOKS_DIR"
    create_symlink "$GLOBAL_HOOK_SOURCE" "$GLOBAL_HOOK_TARGET"
    chmod +x "$GLOBAL_HOOK_SOURCE"
    
    # Configure git to use global hooks path (use ~ for portability across machines)
    git config --global core.hooksPath "~/.config/git/hooks"
    ux_success "Global core.hooksPath가 ~/.config/git/hooks로 설정되었습니다."
else
    ux_warning "경고: Global pre-commit hook 파일이 '${GLOBAL_HOOK_SOURCE}' 경로에 없습니다."
fi


ux_success "Git dotfiles setup 완료"
echo "${UX_MUTED}Git 설정이 적용되었습니다.${UX_RESET}"

exit 0