#!/bin/sh
# shell-common/aliases/git.sh
# Portable git aliases for bash and zsh
# (No bash-specific features)

# Git status shortcuts
alias gs='git status -sb'                        # 간략한 상태 보기
alias ga='git add .'                             # 모든 변경사항 스테이징
alias gc='git commit -m'                         # 커밋 메시지 작성
alias gca='git commit --amend'                   # 커밋 메시지 수정

# Git push/pull
alias gp='SKIP_PRE_PUSH=1 git push'              # 빠른 푸시 (main 우회 허용)
alias gpf='git push --force-with-lease'          # 강제 푸시 (안전한 버전)
alias gps='git push'                             # 안전한 푸시 (Hook 활성화)
alias gpl='git pull'                             # 현재 브랜치만 pull

# Git log
alias gl1='git log --oneline --graph --decorate' # 깔끔한 로그
alias gl2='git log --graph --decorate --date=short --abbrev-commit --pretty=oneline' # 간단한 그래프 로그
alias glref='git log ref/main --oneline'         # ref 원격 main 브랜치 한줄 로그

# Git branch/checkout
alias gb='git --no-pager branch'                 # 브랜치 목록 (pager 비활성화)
alias gco='git checkout'                         # 체크아웃 (브랜치 이동 등)

# Git diff
alias gd='git diff'                              # 변경사항 확인
alias grs='git restore'                          # 파일 변경사항 취소

# Git remote/fetch
alias gr='git remote -v'                         # 원격 저장소 목록
alias gfu='git fetch upstream'                   # upstream에서 fetch
alias gfa='git fetch --all --prune'              # 원격 전체 fetch + 필요없는 브랜치 정리

# Git cleanup
alias grmc='git rm --cached'                     # 파일을 스테이징에서 제거 (파일 시스템은 유지)

# Git cherry-pick
alias gcpa='git cherry-pick --abort'             # Cherry-pick 작업 중단
alias gcpc='git cherry-pick --continue'          # Cherry-pick 작업 계속
alias gcps='git cherry-pick --skip'              # Cherry-pick 작업 건너뛰기

# Git hook diagnostics
hook_check() {
    # Handle help option
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        hook_help
        return 0
    fi

    # Find shell-common/tools/custom directory dynamically
    local dotfiles_root
    if [ -n "${DOTFILES_ROOT:-}" ]; then
        dotfiles_root="$DOTFILES_ROOT"
    else
        # Try to find it by searching for shell-common directory
        dotfiles_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)" || {
            echo "Error: Could not determine DOTFILES_ROOT" >&2
            return 1
        }
    fi

    local hook_check_script="$dotfiles_root/shell-common/tools/custom/hook_check.sh"

    if [ ! -f "$hook_check_script" ]; then
        echo "Error: hook_check.sh not found at: $hook_check_script" >&2
        return 1
    fi

    bash "$hook_check_script" "$@"
}

alias hook-check='hook_check'                     # Git hook 설정 진단 (hook-check --help로 도움말 보기)
