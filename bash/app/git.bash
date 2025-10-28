#!/bin/bash

# bash/app/git.bash

# -------------------------------
# Git Push Force with Upstream
# -------------------------------
alias gpfu='git push --set-upstream origin main --force-with-lease'
# 설명: 현재 main 브랜치를 원격(origin/main)에 강제로 업스트림 설정 + 푸시
# 사용 예시: main 브랜치가 원격보다 앞설 때, "rejected (fetch first)" 문제 해결용

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
alias glref='git log ref/main --oneline'         # ref 원격 main 브랜치 한줄 로그
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
# Git LFS 설치 함수 (Ubuntu 전용)
# -------------------------------
git_lfs_install() {
    echo "[Git LFS 설치 시작]"

    # apt 업데이트
    sudo apt-get update

    # git-lfs 설치
    sudo apt-get install -y git-lfs

    # git-lfs 초기화
    git lfs install

    # 설치 확인
    if command -v git-lfs &>/dev/null; then
        echo "[완료] Git LFS 설치 성공 ✅"
        git lfs version
    else
        echo "[실패] Git LFS 설치가 올바르게 완료되지 않았습니다 ❌"
    fi
}

# -------------------------------
# Git LFS Track 함수
# -------------------------------
git_lfs_track() {
    if [ $# -eq 0 ]; then
        echo "사용법: git_lfs_track <패턴...>"
        echo "예: git_lfs_track \"*.zip\" \"*.sql\" \"*.tar.gz\""
        return 1
    fi

    for pattern in "$@"; do
        git lfs track "$pattern"
        echo "[추가됨] $pattern → .gitattributes"
    done

    echo "⚠️ 반드시 .gitattributes 파일을 커밋하세요!"
}

alias glfs='git_lfs_track'

# -------------------------------
# Git helper 도움말
# -------------------------------
githelp() {
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
    glref      : git log ref/main --oneline (ref 원격 main 브랜치 한줄 로그)


  Branch Upstream:
    gset-main  : git branch --set-upstream-to=origin/main main
    gset-dev   : git branch --set-upstream-to=origin/dev dev
    gset       : gset [branch] (현재 브랜치 또는 지정 브랜치 upstream 설정)

  Special:
    gpf_dev_server : git push -f origin HEAD:refs/heads/dev-server
    gpfu           : git push --set-upstream origin main --force-with-lease (main 강제 업스트림 푸시)

  Git LFS:
    git_lfs_install : Ubuntu 환경에서 git-lfs 설치 및 초기화 (최초 1회)
    git_lfs_track   : git-lfs track <패턴...> (예: git_lfs_track "*.zip" "*.sql" "*.tar.gz")
    glfs            : git_lfs_track 단축 명령어
EOF
}
