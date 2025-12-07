#!/bin/bash

# bash/app/git.bash

# --- 커스텀 경로 축약 함수 ---
_short_pwd() {
    local full_path
    full_path=$(pwd)
    local max_dirs=3
    local parts=()

    # 홈 디렉토리 축약 (~)
    if [[ "$full_path" == "$HOME"* ]]; then
        full_path="~${full_path#"$HOME"}"
    fi

    IFS='/' read -ra parts <<<"$full_path"
    local part_count=${#parts[@]}

    if ((part_count > max_dirs)); then
        local truncated_parts
        truncated_parts=("${parts[@]: -max_dirs}")
        local truncated
        truncated=$(
            IFS=/
            echo "${truncated_parts[*]}"
        )
        echo ".../$truncated"
    else
        echo "$full_path"
    fi
}

# -------------------------------
# Git Push Force with Upstream
# -------------------------------
alias gpfu='git push --set-upstream origin main --force-with-lease'
# 설명: 현재 main 브랜치를 원격(origin/main)에 강제로 업스트림 설정 + 푸시
# 사용 예시: main 브랜치가 원격보다 앞설 때, "rejected (fetch first)" 문제 해결용

alias gpf_dev_server='git push -f origin HEAD:refs/heads/dev-server'
alias git_log='git log --graph --pretty=format:"%Cred%h %C(bold blue)%d %Creset%s %Cgreen%ad %C(yellow)%an" --date=short'
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
alias grmc='git rm --cached'        # 파일을 스테이징에서 제거 (파일 시스템은 유지)

# Git rm --cached 함수 (여러 파일 처리)
git_rm_cached() {
    if [ $# -eq 0 ]; then
        echo "사용법: git_rm_cached <파일명> [파일명2] ..."
        echo "예: git_rm_cached file.txt"
        echo "예: git_rm_cached file1.txt file2.txt"
        echo "⚠️ 스테이징에서 제거되지만 파일은 유지됩니다"
        return 1
    fi

    for file in "$@"; do
        if git rm --cached "$file"; then
            echo "✅ 스테이징에서 제거됨: $file"
        else
            echo "❌ 제거 실패: $file"
            return 1
        fi
    done
}

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

# Cherry-pick 함수 (특정 작가의 커밋들을 범위에서 찾아 cherry-pick)
# 사용법: gcpa <커밋범위> [사용자이름]
# 예: gcpa 751e304..7ffcbd4
# 예: gcpa 751e304..7ffcbd4 dEitY719
# 예: gcpa 751e304^..7ffcbd4 (시작 커밋 포함)
gcpa() {
    local commit_range="$1"
    local author="${2:-dEitY719}" # 기본값: dEitY719

    if [ -z "$commit_range" ]; then
        echo "사용법: gcpa <커밋범위> [사용자이름]"
        echo "예: gcpa 751e304..7ffcbd4"
        echo "예: gcpa 751e304..7ffcbd4 dEitY719"
        echo "⚠️ 커밋범위 형식: <start>..<end> 또는 <start>^..<end>"
        return 1
    fi

    # 지정된 범위와 작가의 커밋들을 가져오기
    local commits
    commits=$(git log --author="$author" --no-merges --reverse --pretty=format:"%h" "$commit_range" 2>/dev/null)

    if [ -z "$commits" ]; then
        echo "❌ '$author' 작가의 커밋을 찾을 수 없습니다: $commit_range"
        return 1
    fi

    echo "📝 Cherry-picking commits by '$author' in range $commit_range:"
    echo "$commits"
    echo ""
    echo "$commits" | xargs git cherry-pick
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
    ux_header "Git Quick Commands"

    ux_section "Basic Commands"
    ux_table_row "gs" "git status -sb" "Short status"
    ux_table_row "ga" "git add ." "Stage all changes"
    ux_table_row "gc" "git commit -m" "Commit with message"
    ux_table_row "gca" "git commit --amend" "Amend last commit"
    ux_table_row "gp" "git push" "Push to remote"
    ux_table_row "gpl" "git pull" "Pull from remote"
    ux_table_row "gco" "git checkout" "Checkout branch/commit"
    ux_table_row "gd" "git diff" "Show changes"
    ux_table_row "gb" "git branch" "List branches"
    ux_table_row "grmc" "git rm --cached" "Unstage, keep file"
    echo ""

    ux_section "Fetch & Sync"
    ux_table_row "gf" "git fetch origin -p" "Fetch origin & prune"
    ux_table_row "gfu" "git fetch upstream" "Fetch upstream"
    ux_table_row "gfa" "git fetch --all" "Fetch all & prune"
    ux_table_row "gsw" "git switch -c" "Switch to remote branch"
    ux_table_row "gr" "git remote -v" "List remotes"
    echo ""

    ux_section "Logs"
    ux_table_row "gl" "git_log" "Graph log (default 11)"
    ux_table_row "gl1" "log --oneline" "One-line graph log"
    ux_table_row "gl2" "git_log2" "Alternative log format"
    ux_table_row "glref" "log ref/main" "Ref log for main"
    echo ""

    ux_section "Upstream"
    ux_table_row "gupa" "remote add upstream" "Add upstream remote"
    ux_table_row "gupdel" "gupdel <remote>" "Remove remote"
    ux_table_row "glum" "log upstream/main" "Upstream main log"
    ux_table_row "glub" "glub [branch]" "Upstream branch log"
    echo ""

    ux_section "Branch Configuration"
    ux_table_row "gset-main" "set-upstream main" "Track origin/main"
    ux_table_row "gset-dev" "set-upstream dev" "Track origin/dev"
    ux_table_row "gset" "gset [branch]" "Track origin/[branch]"
    echo ""

    ux_section "Cherry-pick"
    ux_table_row "gcp" "gcp <commit>..." "Cherry-pick commits"
    ux_table_row "gcpa" "gcpa <range> [author]" "Cherry-pick by author"
    echo ""

    ux_section "Special"
    ux_table_row "gpf_dev_server" "push force dev" "Force push dev-server"
    ux_table_row "gpfu" "push --force-with-lease" "Force push main"
    echo ""

    ux_section "Git LFS"
    ux_table_row "git_lfs_install" "Install LFS" "Ubuntu setup"
    ux_table_row "glfs" "track <pattern>" "Track files with LFS"
    echo ""
}

# gl 함수 (최근 11개 기본, -a/--all 옵션으로 모두 보기)
unalias gl 2>/dev/null || true
gl() {
    local show_all=0
    local args=()

    for arg in "$@"; do
        if [ "$arg" = "-a" ] || [ "$arg" = "--all" ]; then
            show_all=1
        else
            args+=("$arg")
        fi
    done

    if [ $show_all -eq 1 ]; then
        git_log "${args[@]}"
    else
        git_log -n 11 "${args[@]}"
    fi
}
