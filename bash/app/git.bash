#!/bin/bash

# bash/app/git.bash
# Note: This file uses bash-specific features (read -a, __git_ps1, etc.)
# and is only loaded in bash shells

# Exit if not running in bash
[ -n "$BASH" ] || return 0

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
alias git_log='git log --graph --pretty=tformat:"%Cred%h %C(bold blue)%d %Creset%s %Cgreen%ad %C(yellow)%an" --date=short'
alias git_log2='git log --graph --decorate --date=short --abbrev-commit --pretty=oneline'
alias gl2=git_log2

# PS1 only for bash (zsh uses oh-my-zsh themes)
if [ -n "$BASH" ]; then
    export PS1="\[\e]0;\u@\h: \$(_short_pwd)\a\]\[\e[32m\]\u@\h:\[\e[33m\]\$(_short_pwd)\[\e[36m\]\$(__git_ps1 '(%s)')\[\e[0m\]\$ "
fi

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

# Fetch from remote with prune (default: origin)
# Usage: gf [remote]
#   gf              -> git fetch origin -p
#   gf upstream     -> git fetch upstream -p
#   gf u            -> git fetch upstream -p (shorthand)
#   gf <remote>     -> git fetch <remote> -p
unalias gf 2>/dev/null || true
gf() {
    local remote="${1:-origin}"

    # Handle shorthand aliases
    case "$remote" in
    u | upstream-shorthand)
        remote="upstream"
        ;;
    esac

    ux_info "Fetching from '$remote' with prune..."
    git fetch "$remote" -p
}

alias gfu='git fetch upstream'      # upstream에서 fetch
alias gfa='git fetch --all --prune' # 원격 전체 fetch + 필요없는 브랜치 정리
alias gpl='git pull'                # 현재 브랜치만 pull
alias grmc='git rm --cached'        # 파일을 스테이징에서 제거 (파일 시스템은 유지)

# Git rm --cached 함수 (여러 파일 처리)
git_rm_cached() {
    if [ $# -eq 0 ]; then
        ux_usage "git_rm_cached" "<file> [file2] ..." "Remove files from staging (keep in filesystem)"
        ux_bullet "git_rm_cached file.txt"
        ux_bullet "git_rm_cached file1.txt file2.txt"
        return 1
    fi

    for file in "$@"; do
        if git rm --cached "$file"; then
            ux_success "스테이징에서 제거됨: $file"
        else
            ux_error "제거 실패: $file"
            return 1
        fi
    done
}

# Upstream 원격 저장소 추가 함수
gupa() {
    if [ $# -eq 0 ]; then
        ux_usage "gupa" "<git-repo-url>" "Add upstream remote repository"
        ux_bullet "gupa https://github.com/original-owner/repo.git"
        return 1
    fi
    git remote add upstream "$1"
    ux_success "Upstream 원격 저장소 추가됨: $1"
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

# Cherry-pick with conflict resolution strategy (theirs)
# 사용법: gcp_theirs <commit-id> [commit-id2] ...
# 예: gcp_theirs abc1234
# Conflict 발생 시 incoming 변경사항 (branch의 내용) 유지
gcp_theirs() {
    if [ $# -eq 0 ]; then
        echo "사용법: gcp_theirs <commit-id> [commit-id2] ..."
        echo "예: gcp_theirs abc1234"
        echo "⚠️ Conflict 발생 시 incoming 변경사항(theirs) 유지"
        return 1
    fi

    local failed=0
    for commit in "$@"; do
        if git cherry-pick -X theirs "$commit"; then
            echo "✅ Cherry-pick -X theirs 성공: $commit"
        else
            echo "❌ Cherry-pick -X theirs 실패: $commit"
            failed=1
            break
        fi
    done

    return $failed
}

# Cherry-pick with conflict resolution strategy (ours)
# 사용법: gcp_ours <commit-id> [commit-id2] ...
# 예: gcp_ours abc1234
# Conflict 발생 시 현재 branch의 변경사항 유지
gcp_ours() {
    if [ $# -eq 0 ]; then
        echo "사용법: gcp_ours <commit-id> [commit-id2] ..."
        echo "예: gcp_ours abc1234"
        echo "⚠️ Conflict 발생 시 현재 branch의 변경사항(ours) 유지"
        return 1
    fi

    local failed=0
    for commit in "$@"; do
        if git cherry-pick -X ours "$commit"; then
            echo "✅ Cherry-pick -X ours 성공: $commit"
        else
            echo "❌ Cherry-pick -X ours 실패: $commit"
            failed=1
            break
        fi
    done

    return $failed
}

# Cherry-pick abort 및 continue 단축어
alias gcpa='git cherry-pick --abort'    # Cherry-pick 작업 중단
alias gcpc='git cherry-pick --continue' # Cherry-pick 작업 계속

# Cherry-pick 함수 (특정 작가의 커밋들을 범위에서 찾아 cherry-pick)
# 사용법: gcp_author <커밋범위> [사용자이름]
# 예: gcp_author 751e304..7ffcbd4
# 예: gcp_author 751e304..7ffcbd4 dEitY719
# 예: gcp_author 751e304^..7ffcbd4 (시작 커밋 포함)
gcp_author() {
    local commit_range="$1"
    local author="${2:-dEitY719}" # 기본값: dEitY719

    if [ -z "$commit_range" ]; then
        echo "사용법: gcp_author <커밋범위> [사용자이름]"
        echo "예: gcp_author 751e304..7ffcbd4"
        echo "예: gcp_author 751e304..7ffcbd4 dEitY719"
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
# Check and Cherry-pick Missing Commits
# -------------------------------
# gcp_scan: Intelligently identify and cherry-pick missing commits
#
# Compares two branches and shows commits present in source but missing in base.
# Uses `git cherry` to detect commits and provides interactive confirmation.
#
# Usage:
#   gcp_scan [--author=<name|all>]         # defaults: main <- upstream/main, author=dEitY719
#   gcp_scan develop origin --author=all   # custom branches + show all commits
#
# Note: git cherry marks commits as:
#   '+' = present in source, missing in base (will be cherry-picked)
#   '-' = already merged in base
#
gcp_scan() {
    local base="main"
    local source="upstream/main"
    local author="dEitY719"
    local positional=()

    # Parse arguments (positional: base source; flag: --author)
    while [ $# -gt 0 ]; do
        case "$1" in
        --author=*)
            author="${1#--author=}"
            ;;
        --author)
            if [ -n "${2-}" ]; then
                author="$2"
                shift
            else
                ux_error "--author requires a value"
                return 1
            fi
            ;;
        *)
            positional+=("$1")
            ;;
        esac
        shift
    done

    if [ "${#positional[@]}" -ge 1 ]; then
        base="${positional[0]}"
    fi
    if [ "${#positional[@]}" -ge 2 ]; then
        source="${positional[1]}"
    fi

    ux_header "Scanning for missing commits from '$source' in '$base'..."

    # Verify branches exist
    if ! git rev-parse --verify "$base" >/dev/null 2>&1; then
        ux_error "Base branch '$base' does not exist."
        return 1
    fi
    if ! git rev-parse --verify "$source" >/dev/null 2>&1; then
        ux_error "Source branch '$source' does not exist."
        return 1
    fi

    # Find missing commits (present in source, missing in base)
    # git cherry base source lists commits in source not in base
    local missing_list
    missing_list=$(git cherry "$base" "$source" | grep "^+" | awk '{print $2}')

    if [ -z "$missing_list" ]; then
        ux_success "No missing commits found! '$base' is up to date with '$source'."
        return 0
    fi

    local total_count
    total_count=$(echo "$missing_list" | wc -l)
    local author_lc
    author_lc=$(printf '%s' "$author" | tr '[:upper:]' '[:lower:]')

    # Filter by author unless explicitly showing all
    local selected_list=""
    if [ "$author_lc" = "all" ]; then
        selected_list="$missing_list"
    else
        while IFS= read -r sha; do
            [ -z "$sha" ] && continue
            local commit_author
            commit_author=$(git show -s --format='%an' "$sha")
            if [ "$(printf '%s' "$commit_author" | tr '[:upper:]' '[:lower:]')" = "$author_lc" ]; then
                if [ -z "$selected_list" ]; then
                    selected_list="$sha"
                else
                    selected_list="$selected_list"$'\n'"$sha"
                fi
            fi
        done <<<"$missing_list"
    fi

    if [ -z "$selected_list" ]; then
        ux_warning "No missing commits match author '$author'."
        ux_info "Use --author=all to show all missing commits."
        return 0
    fi

    local count
    count=$(echo "$selected_list" | wc -l)

    # [IMPROVEMENT] Check for duplicate commits (same subject already in base branch)
    local final_selected_list=""
    local duplicate_list=""
    local duplicate_count=0

    while IFS= read -r sha; do
        [ -z "$sha" ] && continue
        local subject
        subject=$(git show -s --format='%s' "$sha")

        # Check if base branch has a commit with same subject (search recent 200 commits for speed)
        if git log "$base" -n 200 --format='%s' 2>/dev/null | grep -Fqx "$subject"; then
            duplicate_list="${duplicate_list}${sha}"$'\n'
            ((duplicate_count++))
        else
            if [ -z "$final_selected_list" ]; then
                final_selected_list="$sha"
            else
                final_selected_list="${final_selected_list}"$'\n'"${sha}"
            fi
        fi
    done <<<"$selected_list"

    # Update count if duplicates exist
    if [ $duplicate_count -gt 0 ]; then
        count=$((count - duplicate_count))
    fi

    # Calculate range (Oldest..Newest)
    # git cherry outputs in chronological order (oldest first)
    local first_sha
    first_sha=$(echo "$selected_list" | head -n 1)
    local last_sha
    last_sha=$(echo "$selected_list" | tail -n 1)
    local range_str="${first_sha}^..${last_sha}"

    # Verify contiguity
    local range_count
    range_count=$(git rev-list --count "$range_str")
    local is_contiguous=0
    if [ "$range_count" -eq "$count" ]; then
        is_contiguous=1
    fi

    # Display Summary
    ux_section "Analysis Result"
    ux_bullet "Missing (all authors): ${UX_BOLD}${total_count}${UX_RESET}"
    ux_bullet "Author filter: ${UX_BOLD}${author}${UX_RESET} -> ${UX_BOLD}${count}${UX_RESET} commit(s)"
    if [ $duplicate_count -gt 0 ]; then
        ux_bullet "Duplicates (already applied): ${UX_BOLD}${UX_YELLOW}${duplicate_count}${UX_RESET}"
    fi
    ux_bullet "Suggested Range: ${UX_BOLD}${range_str}${UX_RESET}"
    if [ $is_contiguous -eq 1 ]; then
        ux_success "Range is contiguous (clean cherry-pick)."
    else
        ux_warning "Range is NOT contiguous (contains $((range_count - count)) other commits in between)."
    fi

    # Display Commits (preserve selected_list order with duplicate marking)
    echo ""
    ux_section "Commit List"
    echo "Commits to cherry-pick:"
    {
        for sha in $selected_list; do
            local is_dup=0
            local subject
            subject=$(git show -s --format='%s' "$sha")

            # Check if this is a duplicate
            if git log "$base" -n 200 --format='%s' 2>/dev/null | grep -Fqx "$subject"; then
                is_dup=1
            fi

            local line
            line=$(git log --no-walk --format="%C(auto)%h %C(green)%ad %C(blue)%an%C(auto)%d %s" --date=short "$sha")

            if [ $is_dup -eq 1 ]; then
                echo "${UX_YELLOW}${line} ${UX_BOLD}[DUPLICATE - Already in $base]${UX_RESET}"
            else
                echo "$line"
            fi
        done
    } | nl -w 2 -s '. '

    echo ""
    # Interactive Confirmation
    if ux_confirm "Do you want to cherry-pick these $count commits?" "n"; then
        echo ""
        if [ $is_contiguous -eq 1 ] && [ $duplicate_count -eq 0 ]; then
            ux_info "Executing: git cherry-pick $range_str"
            if git cherry-pick "$range_str"; then
                ux_success "Cherry-pick complete!"
            else
                ux_error "Cherry-pick encountered conflicts. Resolve manually and run:"
                ux_error "  git cherry-pick --continue"
                return 1
            fi
        else
            # Non-contiguous OR has duplicates: cherry-pick individually for better control
            if [ $duplicate_count -gt 0 ]; then
                ux_warning "Duplicates detected. Cherry-picking individually with auto-skip for duplicates..."
            elif [ $is_contiguous -eq 0 ]; then
                ux_warning "Non-contiguous range detected. Cherry-picking individually..."
            fi
            local picked=0
            local skipped=0
            for sha in $selected_list; do
                local subject
                subject=$(git show -s --format='%s' "$sha")

                # Check if this commit is a duplicate (already in base)
                local is_dup=0
                if git log "$base" -n 200 --format='%s' 2>/dev/null | grep -Fqx "$subject"; then
                    is_dup=1
                fi

                if [ $is_dup -eq 1 ]; then
                    ux_warning "Skipping $sha (already in $base)..."
                    ((skipped++))
                else
                    ux_info "Cherry-picking $sha..."
                    if git cherry-pick "$sha"; then
                        ((picked++))
                    else
                        ux_error "Failed at $sha. Resolve and run: git cherry-pick --continue"
                        return 1
                    fi
                fi
            done
            ux_success "Cherry-picked $picked/$count commits successfully! (Skipped $skipped duplicates)"
        fi
    else
        ux_info "Cancelled. You can use the range above manually: git cherry-pick $range_str"
    fi
}

# Quick shorthand for gcp_scan
alias gcs='gcp_scan'

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
    ux_table_row "gf [remote]" "gf / gf u / gf <name>" "Fetch & prune (default: origin, u=upstream)"
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
    ux_table_row "gcp_theirs" "gcp_theirs <commit>..." "Cherry-pick with -X theirs (incoming)"
    ux_table_row "gcp_ours" "gcp_ours <commit>..." "Cherry-pick with -X ours (current)"
    # ux_table_row "gcpa" "git cherry-pick --abort" "Abort cherry-pick operation"
    # ux_table_row "gcpc" "git cherry-pick --continue" "Continue cherry-pick after resolving conflicts"
    ux_table_row "gcp_author" "gcp_author <range> [author]" "Cherry-pick by author"
    ux_table_row "gcp_scan" "gcp_scan [base] [src] [--author=<name|all>]" "Compare & pick missing (default: main <- upstream/main, author=dEitY719)"
    echo ""

    ux_section "Cherry-pick -X (Merge Strategy)"
    ux_bullet "gcp_theirs: ${UX_ERROR}Conflict${UX_RESET} 발생시 ${UX_WARNING}incoming(cherry-pick되는 커밋의 변경)${UX_RESET} 선택"
    ux_bullet "gcp_ours: ${UX_ERROR}Conflict${UX_RESET} 발생시 ${UX_SUCCESS}current branch(현재 브랜치의 변경)${UX_RESET} 선택"
    ux_bullet "예: gcp_theirs abc1234 def5678 - ${UX_MUTED}두 커밋을 theirs 전략으로 cherry-pick${UX_RESET}"
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
