#!/bin/sh
# shell-common/tools/integrations/git.sh
# Bash-specific git functions and features
# (This file requires bash and should not be sourced in other shells)

# Exit if not running in bash
[ -n "$BASH" ] || return 0

# ============================================================
# BASH-SPECIFIC HELPERS
# ============================================================

# Path abbreviation using bash builtins (no external forks).
# Truncates to last 3 directory components when deeper.
_short_pwd() {
    local full_path
    full_path="$PWD"

    # Abbreviate home directory (~)
    case "$full_path" in
        "$HOME"/*)
            full_path="~${full_path#"$HOME"}"
            ;;
        "$HOME")
            echo "~"
            return
            ;;
    esac

    # Count slashes using parameter expansion (no awk fork)
    local stripped="${full_path//[!\/]/}"
    local level_count=${#stripped}

    if [ "$level_count" -gt 3 ]; then
        # Extract last 3 path components using parameter expansion
        local tmp="${full_path%/*}"    # remove last component
        tmp="${tmp%/*}"                # remove second-to-last
        tmp="${full_path#"$tmp"/}"     # keep everything after
        echo ".../$tmp"
    else
        echo "$full_path"
    fi
}

# Render active Python virtual environment for bash prompt.
_prompt_virtualenv() {
    [ -n "${VIRTUAL_ENV:-}" ] || return 0

    local venv_prompt="${VIRTUAL_ENV_PROMPT:-}"
    if [ -n "$venv_prompt" ]; then
        # activate scripts often set a trailing space in VIRTUAL_ENV_PROMPT.
        venv_prompt="${venv_prompt% }"
        case "$venv_prompt" in
            \(*\))
                printf '%s ' "$venv_prompt"
                ;;
            *)
                printf '(%s) ' "$venv_prompt"
                ;;
        esac
        return 0
    fi

    local venv_name="${VIRTUAL_ENV##*/}"
    [ -n "$venv_name" ] && printf '(%s) ' "$venv_name"
}

# Git prompt setup (PS1 only for bash, zsh uses oh-my-zsh themes)
if [ -f /usr/share/git-core/contrib/completion/git-prompt.sh ]; then
    # shellcheck source=/usr/share/git-core/contrib/completion/git-prompt.sh
    . /usr/share/git-core/contrib/completion/git-prompt.sh
else
    __git_ps1() {
        local branch
        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
        if [ -n "$branch" ]; then
            local fmt="${1:-%s}"
            local suffix="${2-}"
            fmt="${fmt//%s/$branch}"
            printf "%s%s" "$fmt" "$suffix"
        fi
    }
fi

# Cache _short_pwd once per prompt, then reference cached value in PS1.
# This avoids calling _short_pwd twice (title + visible prompt).
_update_prompt_cache() {
    _CACHED_SHORT_PWD=$(_short_pwd)
}

PS1="\[\e]0;\u@\h: \${_CACHED_SHORT_PWD}\a\]\[\e[35m\]\$(_prompt_virtualenv)\[\e[32m\]\u@\h:\[\e[33m\]\${_CACHED_SHORT_PWD}\[\e[36m\]\$(__git_ps1 '(%s)' '')\[\e[0m\]\$ "

if [[ "${PROMPT_COMMAND-}" != *"_update_prompt_cache"* ]]; then
    if [ -n "${PROMPT_COMMAND-}" ]; then
        PROMPT_COMMAND="_update_prompt_cache;${PROMPT_COMMAND}"
    else
        PROMPT_COMMAND="_update_prompt_cache"
    fi
fi

# ============================================================
# BASH-SPECIFIC FUNCTIONS
# ============================================================

gsw() {
    local remote_branch="$1"
    local local_branch="${remote_branch#*/}"
    git switch -c "$local_branch" "$remote_branch"
}

unalias gf 2>/dev/null || true
gf() {
    local remote="${1:-origin}"
    case "$remote" in
    u | upstream-shorthand)
        remote="upstream"
        ;;
    esac
    ux_info "Fetching from '$remote' with prune..."
    git fetch "$remote" -p
}

git_rm_cached() {
    if [ $# -eq 0 ]; then
        ux_usage "grmc" "<file> [file2] ..." "Remove files from staging (keep in filesystem)"
        ux_bullet "grmc file.txt"
        ux_bullet "grmc file1.txt file2.txt"
        return 1
    fi

    for file in "$@"; do
        if git rm --cached "$file"; then
            ux_success "Removed from staging: $file"
        else
            ux_error "Failed to remove: $file"
            return 1
        fi
    done
}

gupa() {
    if [ $# -eq 0 ]; then
        ux_usage "gupa" "<git-repo-url>" "Add upstream remote repository"
        ux_bullet "gupa https://github.com/original-owner/repo.git"
        return 1
    fi
    git remote add upstream "$1"
    ux_success "Upstream remote added: $1"
    git remote -v
}

gupdel() {
    if [ $# -eq 0 ]; then
        ux_usage "gupdel" "<remote-name>" "Delete a git remote"
        ux_bullet "gupdel upstream"
        echo ""
        ux_section "Registered remotes"
        git remote -v
        return 1
    fi

    local remote="$1"
    if git remote remove "$remote" 2>/dev/null; then
        ux_success "Remote deleted: $remote"
        git remote -v
    else
        ux_error "Remote not found: $remote"
        return 1
    fi
}

# Internal: cherry-pick with optional strategy (-X theirs / -X ours)
_git_cherry_pick() {
    local strategy="$1"
    shift

    if [ $# -eq 0 ]; then
        local cmd_name="gcp"
        local desc="Cherry-pick one or more commits"
        local flag_info=""
        if [ -n "$strategy" ]; then
            cmd_name="gcp_${strategy}"
            desc="Cherry-pick with '${strategy}' conflict strategy"
            flag_info=" -X ${strategy}"
        fi
        ux_usage "$cmd_name" "<commit-id> [commit-id2] ..." "$desc"
        ux_bullet "$cmd_name abc1234"
        [ -n "$strategy" ] && ux_warning "Conflicts will use ${strategy} changes"
        return 1
    fi

    local failed=0
    for commit in "$@"; do
        if [ -n "$strategy" ]; then
            if git cherry-pick -X "$strategy" "$commit"; then
                ux_success "Cherry-pick${flag_info:-} succeeded: $commit"
            else
                ux_error "Cherry-pick${flag_info:-} failed: $commit"
                failed=1
                break
            fi
        else
            if git cherry-pick "$commit"; then
                ux_success "Cherry-pick succeeded: $commit"
            else
                ux_error "Cherry-pick failed: $commit"
                failed=1
                break
            fi
        fi
    done

    return $failed
}

gcp() { _git_cherry_pick "" "$@"; }
gcp_theirs() { _git_cherry_pick "theirs" "$@"; }
gcp_ours() { _git_cherry_pick "ours" "$@"; }

gcp_author() {
    local commit_range="$1"
    local author="${2:-dEitY719}"

    if [ -z "$commit_range" ]; then
        ux_usage "gcp_author" "<commit-range> [author-name]" "Cherry-pick commits by specific author"
        ux_bullet "gcp_author 751e304..7ffcbd4"
        ux_bullet "gcp_author 751e304..7ffcbd4 dEitY719"
        ux_warning "Format: <start>..<end> or <start>^..<end>"
        return 1
    fi

    local commits
    commits=$(git log --author="$author" --no-merges --reverse --pretty=format:"%h" "$commit_range" 2>/dev/null)

    if [ -z "$commits" ]; then
        ux_error "No commits found by '$author' in range $commit_range"
        return 1
    fi

    ux_info "Cherry-picking commits by '$author' in range $commit_range:"
    echo "$commits"
    echo ""
    echo "$commits" | xargs git cherry-pick
}

glub() {
    local branch="${1:-main}"
    git log --oneline -n 20 "upstream/$branch"
}

alias gset-main='git branch --set-upstream-to=origin/main main'
alias gset-dev='git branch --set-upstream-to=origin/dev dev'

gset() {
    local branch=${1:-$(git symbolic-ref --short HEAD)}
    git branch --set-upstream-to=origin/"$branch" "$branch"
}

git_lfs_install() {
    local script_path
    script_path="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_git_lfs.sh"

    if [ ! -f "$script_path" ]; then
        ux_error "install_git_lfs.sh not found: $script_path"
        return 1
    fi

    bash "$script_path" "$@"
}

git_lfs_track() {
    if [ $# -eq 0 ]; then
        ux_usage "git_lfs_track" "<pattern...>" "Track file patterns with Git LFS"
        ux_bullet "git_lfs_track \"*.zip\" \"*.sql\" \"*.tar.gz\""
        return 1
    fi

    for pattern in "$@"; do
        git lfs track "$pattern"
        ux_success "Added $pattern to .gitattributes"
    done

    ux_warning "Remember to commit the .gitattributes file!"
}

alias glfs='git_lfs_track'
