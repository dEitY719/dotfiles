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
alias gca='git commit --amend'                   # 커밋 메시지 작성
alias gp='git push'                              # 푸시
alias gl1='git log --oneline --graph --decorate' # 깔끔한 로그
alias glref='git log ref/main --oneline'         # ref 원격 main 브랜치 한줄 로그
alias gco='git checkout'                         # 체크아웃 (브랜치 이동 등)
gsw() {
    # 사용법: gsw origin/pr/refactor-cli
    # 원격 브랜치에서 로컬 브랜치를 생성하고 switch (자동으로 upstream 설정)
    local remote_branch="$1"
    local local_branch="${remote_branch#*/}" # origin/pr/refactor-cli -> pr/refactor-cli
    git switch -c "$local_branch" "$remote_branch"
}
alias gd='git diff'   # 변경사항 확인
alias gb='git branch' # 브랜치 목록
alias gf='git fetch origin -p'
alias gfu='git fetch upstream'      # upstream에서 fetch
alias gfa='git fetch --all --prune' # 원격 전체 fetch + 필요없는 브랜치 정리
alias gpl='git pull'                # 현재 브랜치만 pull

# Upstream 원격 저장소 추가 함수
gupa() {
    if [ $# -eq 0 ]; then
        echo "사용법: gupa <git-repo-url>"
        echo "예: gupa https://github.com/original-owner/repo.git"
        return 1
    fi
    git remote add upstream "$1"
    echo "✅ Upstream 원격 저장소 추가됨: $1"
    git remote -v
}

# 원격 저장소 삭제 함수
gupdel() {
    if [ $# -eq 0 ]; then
        echo "사용법: gupdel <remote-name>"
        echo "예: gupdel upstream"
        echo ""
        echo "현재 등록된 원격 저장소:"
        git remote -v
        return 1
    fi

    local remote="$1"
    if git remote remove "$remote" 2>/dev/null; then
        echo "✅ 원격 저장소 삭제됨: $remote"
        git remote -v
    else
        echo "❌ 원격 저장소를 찾을 수 없습니다: $remote"
        return 1
    fi
}

# 원격 저장소 조회
alias gr='git remote -v'

# Cherry-pick 함수
gcp() {
    if [ $# -eq 0 ]; then
        echo "사용법: gcp <commit-id> [commit-id2] [commit-id3] ..."
        echo "예: gcp abc1234"
        echo "예: gcp abc1234 def5678 ghi9012"
        return 1
    fi

    local failed=0
    for commit in "$@"; do
        if git cherry-pick "$commit"; then
            echo "✅ Cherry-pick 성공: $commit"
        else
            echo "❌ Cherry-pick 실패: $commit"
            failed=1
            break
        fi
    done

    return $failed
}

# Upstream main 브랜치 로그 (기본값)
alias glum='git log --oneline -n 20 upstream/main'

# Upstream 특정 브랜치 로그 함수
glub() {
    local branch="${1:-main}"
    git log --oneline -n 20 "upstream/$branch"
}

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
    # Color definitions
    local bold blue green reset
    bold=$(tput bold 2>/dev/null || echo "")
    blue=$(tput setaf 4 2>/dev/null || echo "")
    green=$(tput setaf 2 2>/dev/null || echo "")
    reset=$(tput sgr0 2>/dev/null || echo "")

    cat <<EOF

${bold}${blue}[Git Quick Commands]${reset}

  ${bold}${blue}Basic Commands:${reset}
    ${green}gs${reset}         : git status -sb (간략한 상태)
    ${green}ga${reset}         : git add . (모든 변경사항 스테이징)
    ${green}gc${reset}         : git commit -m (커밋)
    ${green}gca${reset}        : git commit --amend (커밋 수정)
    ${green}gp${reset}         : git push (푸시)
    ${green}gpl${reset}        : git pull (풀)
    ${green}gco${reset}        : git checkout (브랜치 전환)
    ${green}gd${reset}         : git diff (변경사항 확인)
    ${green}gb${reset}         : git branch (브랜치 목록)

  ${bold}${blue}Fetch & Sync:${reset}
    ${green}gf${reset}         : git fetch origin -p (origin fetch + prune)
    ${green}gfu${reset}        : git fetch upstream (upstream에서만 fetch)
    ${green}gfa${reset}        : git fetch --all --prune (모든 원격 fetch)
    ${green}gsw${reset}        : git switch -c <local> <remote> (원격 브랜치로부터 로컬 생성 + switch)
    ${green}gr${reset}         : git remote -v (원격 저장소 조회)

  ${bold}${blue}Logs:${reset}
    ${green}gl${reset}         : git_log (그래프 형태 로그)
    ${green}gl1${reset}        : git log --oneline --graph --decorate
    ${green}gl2${reset}        : git_log2 (대체 로그 포맷)
    ${green}git_log${reset}    : 컬러풀한 커밋 로그
    ${green}git_log2${reset}   : 간결한 한줄 로그
    ${green}glref${reset}      : git log ref/main --oneline (ref 원격 main 브랜치 한줄 로그)

  ${bold}${blue}Upstream:${reset}
    ${green}gupa${reset}       : git remote add upstream <url> (upstream 원격 저장소 추가)
    ${green}gupdel${reset}     : gupdel <remote-name> (원격 저장소 삭제)
    ${green}glum${reset}       : git log --oneline -n 20 upstream/main (upstream main 최근 20개)
    ${green}glub${reset}       : glub [branch] (upstream 특정 브랜치 최근 20개, 기본값: main)

  ${bold}${blue}Branch Upstream:${reset}
    ${green}gset-main${reset}  : git branch --set-upstream-to=origin/main main
    ${green}gset-dev${reset}   : git branch --set-upstream-to=origin/dev dev
    ${green}gset${reset}       : gset [branch] (현재 브랜치 또는 지정 브랜치 upstream 설정)

  ${bold}${blue}Cherry-pick:${reset}
    ${green}gcp${reset}        : gcp <commit-id> [commit-id2] ... (커밋 cherry-pick)
                  예: gcp abc1234 또는 gcp abc1234 def5678

  ${bold}${blue}Special:${reset}
    ${green}gpf_dev_server${reset} : git push -f origin HEAD:refs/heads/dev-server
    ${green}gpfu${reset}           : git push --set-upstream origin main --force-with-lease (main 강제 업스트림 푸시)

  ${bold}${blue}Git LFS:${reset}
    ${green}git_lfs_install${reset} : Ubuntu 환경에서 git-lfs 설치 및 초기화 (최초 1회)
    ${green}git_lfs_track${reset}   : git-lfs track <패턴...> (예: git_lfs_track "*.zip" "*.sql" "*.tar.gz")
    ${green}glfs${reset}            : git_lfs_track 단축 명령어
EOF
}
