#!/bin/bash

# bash/app/git.bash

alias gpf_dev_server='git push -f origin HEAD:refs/heads/dev-server'
alias git_log='git log --graph --pretty=format:"%Cred%h %C(bold blue)%d %Creset%s %Cgreen%ad %C(yellow)%an" --date=short'
alias gl=git_log
alias git_log2='git log --graph --decorate --date=short --abbrev-commit --pretty=oneline'
alias gl2=git_log2
export PS1="\[\e]0;\u@\h: \$(_short_pwd)\a\]\[\e[32m\]\u@\h:\[\e[33m\]\$(_short_pwd)\[\e[36m\]\$(__git_ps1 '(%s)')\[\e[0m\]\$ "

alias gs='git status -sb'                        # 간략한 상태 보기
alias ga='git add .'                             # 모든 변경사항 스테이징
alias gc='git commit -m'                         # 커밋 메시지 작성
alias gp='git push'                              # 푸시
alias gl1='git log --oneline --graph --decorate' # 깔끔한 로그
alias gco='git checkout'                         # 체크아웃 (브랜치 이동 등)
alias gd='git diff'                              # 변경사항 확인
alias gb='git branch'                            # 브랜치 목록
alias gf='git fetch origin -p'
alias gfa='git fetch --all --prune' # 원격 전체 fetch + 필요없는 브랜치 정리
alias gpl='git pull'                # 현재 브랜치만 pull

alias gset-main='git branch --set-upstream-to=origin/main main'
alias gset-dev='git branch --set-upstream-to=origin/dev dev'

gset() {
    # 사용법: gset <branch>
    local branch=${1:-$(git symbolic-ref --short HEAD)}
    git branch --set-upstream-to=origin/"$branch" "$branch"
}

# -------------------------------
# Git helper 도움말
# -------------------------------
gith() {
    cat <<-'EOF'

[Git Quick Commands]

  Basic Commands:
    gs         : git status -sb (간략한 상태)
    ga         : git add . (모든 변경사항 스테이징)
    gc         : git commit -m (커밋)
    gp         : git push (푸시)
    gpl        : git pull (풀)
    gco        : git checkout (브랜치 전환)
    gd         : git diff (변경사항 확인)
    gb         : git branch (브랜치 목록)

  Fetch & Sync:
    gf         : git fetch origin -p (원격 fetch + prune)
    gfa        : git fetch --all --prune (모든 원격 fetch)

  Logs:
    gl         : git_log (그래프 형태 로그)
    gl1        : git log --oneline --graph --decorate
    gl2        : git_log2 (대체 로그 포맷)
    git_log    : 컬러풀한 커밋 로그
    git_log2   : 간결한 한줄 로그

  Branch Upstream:
    gset-main  : git branch --set-upstream-to=origin/main main
    gset-dev   : git branch --set-upstream-to=origin/dev dev
    gset       : gset [branch] (현재 브랜치 또는 지정 브랜치 upstream 설정)

  Special:
    gpf_dev_server : git push -f origin HEAD:refs/heads/dev-server

EOF
}
