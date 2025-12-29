#!/bin/sh
# shell-common/aliases/git.sh
# Shared git aliases for bash and zsh

# Git status shortcuts
alias gs='git status -sb'                        # 간략한 상태 보기
alias ga='git add .'                             # 모든 변경사항 스테이징
alias gc='git commit -m'                         # 커밋 메시지 작성
alias gca='git commit --amend'                   # 커밋 메시지 수정

# Git push/pull
alias gp='git push'                              # 푸시
alias gpf='git push --force-with-lease'          # 강제 푸시 (안전한 버전)
alias gpfu='git push --set-upstream origin main --force-with-lease' # upstream 설정 후 강제 푸시
alias gpf_dev_server='git push -f origin HEAD:refs/heads/dev-server' # dev-server 강제 푸시
alias gpl='git pull'                             # 현재 브랜치만 pull

# Git log
alias gl1='git log --oneline --graph --decorate' # 깔끔한 로그
alias git_log='git log --graph --pretty=tformat:"%Cred%h %C(bold blue)%d %Creset%s %Cgreen%ad %C(yellow)%an" --date=short' # 상세 로그
alias gl2='git log --graph --decorate --date=short --abbrev-commit --pretty=oneline' # 간단한 그래프 로그
alias git_log2='git log --graph --decorate --date=short --abbrev-commit --pretty=oneline' # 별칭
alias glref='git log ref/main --oneline'         # ref 원격 main 브랜치 한줄 로그

# Git branch/checkout
alias gb='git --no-pager branch'                 # 브랜치 목록 (pager 비활성화)
alias gco='git checkout'                         # 체크아웃 (브랜치 이동 등)

# Git diff
alias gd='git diff'                              # 변경사항 확인

# Git remote/fetch
alias gr='git remote -v'                         # 원격 저장소 목록
alias gfu='git fetch upstream'                   # upstream에서 fetch
alias gfa='git fetch --all --prune'              # 원격 전체 fetch + 필요없는 브랜치 정리

# Git cleanup
alias grmc='git rm --cached'                     # 파일을 스테이징에서 제거 (파일 시스템은 유지)
