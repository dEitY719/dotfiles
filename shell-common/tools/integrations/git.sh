#!/bin/sh
# shell-common/tools/external/git.sh
# Bash-specific git functions and features
# (This file requires bash and should not be sourced in other shells)

# Exit if not running in bash
[ -n "$BASH" ] || return 0

# ============================================================
# BASH-SPECIFIC HELPERS
# ============================================================

# Custom path abbreviation function (bash/zsh compatible)
_short_pwd() {
    local full_path pwd_output max_dirs
    pwd_output=$(pwd)
    full_path="$pwd_output"
    max_dirs=3

    # Abbreviate home directory (~)
    case "$full_path" in
        "$HOME"*)
            full_path="~${full_path#"$HOME"}"
            ;;
    esac

    # Count directory levels using awk (portable)
    local part_count level_count
    level_count=$(echo "$full_path" | awk -F/ '{print NF-1}')

    if [ "$level_count" -gt "$max_dirs" ]; then
        # Use sed for portable substring (last 3 dirs + /)
        local truncated
        truncated=$(echo "$full_path" | sed "s|.*/\([^/]*/[^/]*/[^/]*\)$|.../\1|")
        echo "$truncated"
    else
        echo "$full_path"
    fi
}

# Render active Python virtual environment for bash prompt.
# Show venv only when VIRTUAL_ENV is actually set.
_prompt_virtualenv() {
    local venv_prompt venv_name

    [ -n "${VIRTUAL_ENV:-}" ] || return 0

    venv_prompt="${VIRTUAL_ENV_PROMPT:-}"
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

    if [ -n "${VIRTUAL_ENV:-}" ]; then
        venv_name="${VIRTUAL_ENV##*/}"
        [ -n "$venv_name" ] && printf '(%s) ' "$venv_name"
    fi
}

# Git prompt setup (PS1 only for bash, zsh uses oh-my-zsh themes)
if [ -f /usr/share/git-core/contrib/completion/git-prompt.sh ]; then
    # shellcheck source=/usr/share/git-core/contrib/completion/git-prompt.sh
    source /usr/share/git-core/contrib/completion/git-prompt.sh
else
    # Fallback: define __git_ps1 locally if not available system-wide
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

_set_dotfiles_bash_ps1() {
    export PS1="\[\e]0;\u@\h: \$(_short_pwd)\a\]\[\e[35m\]\$(_prompt_virtualenv)\[\e[32m\]\u@\h:\[\e[33m\]\$(_short_pwd)\[\e[36m\]\$(__git_ps1 '(%s)' '')\[\e[0m\]\$ "
}

_set_dotfiles_bash_ps1

if [[ "${PROMPT_COMMAND-}" != *"_set_dotfiles_bash_ps1"* ]]; then
    if [ -n "${PROMPT_COMMAND-}" ]; then
        PROMPT_COMMAND="_set_dotfiles_bash_ps1;${PROMPT_COMMAND}"
    else
        PROMPT_COMMAND="_set_dotfiles_bash_ps1"
    fi
fi

# ============================================================
# BASH-SPECIFIC FUNCTIONS
# ============================================================
# Note: Portable aliases and simple functions are in:
#   - shell-common/aliases/git.sh (for all shells)
#   - shell-common/functions/git.sh (for all shells)

gsw() {
    # Switch to remote branch and create local tracking branch
    # Usage: gsw origin/pr/refactor-cli
    local remote_branch="$1"
    local local_branch="${remote_branch#*/}"
    git switch -c "$local_branch" "$remote_branch"
}

# Fetch from remote with prune (default: origin)
# Usage: gf [remote]
#   gf              -> git fetch origin -p
#   gf upstream     -> git fetch upstream -p
#   gf u            -> git fetch upstream -p (shorthand)
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

# Git rm --cached function (handles multiple files)
git_rm_cached() {
    if [ $# -eq 0 ]; then
        ux_usage "git_rm_cached" "<file> [file2] ..." "Remove files from staging (keep in filesystem)"
        ux_bullet "git_rm_cached file.txt"
        ux_bullet "git_rm_cached file1.txt file2.txt"
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

# Add upstream remote repository
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

# Delete remote repository
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

# Cherry-pick function
gcp() {
    if [ $# -eq 0 ]; then
        ux_usage "gcp" "<commit-id> [commit-id2] ..." "Cherry-pick one or more commits"
        ux_bullet "gcp abc1234"
        ux_bullet "gcp abc1234 def5678 ghi9012"
        return 1
    fi

    local failed=0
    for commit in "$@"; do
        if git cherry-pick "$commit"; then
            ux_success "Cherry-pick succeeded: $commit"
        else
            ux_error "Cherry-pick failed: $commit"
            failed=1
            break
        fi
    done

    return $failed
}

# Cherry-pick with conflict resolution strategy (theirs)
# Usage: gcp_theirs <commit-id> [commit-id2] ...
# Example: gcp_theirs abc1234
gcp_theirs() {
    if [ $# -eq 0 ]; then
        ux_usage "gcp_theirs" "<commit-id> [commit-id2] ..." "Cherry-pick with 'theirs' conflict strategy"
        ux_bullet "gcp_theirs abc1234"
        ux_warning "Conflicts will use incoming (theirs) changes"
        return 1
    fi

    local failed=0
    for commit in "$@"; do
        if git cherry-pick -X theirs "$commit"; then
            ux_success "Cherry-pick -X theirs succeeded: $commit"
        else
            ux_error "Cherry-pick -X theirs failed: $commit"
            failed=1
            break
        fi
    done

    return $failed
}

# Cherry-pick with conflict resolution strategy (ours)
# Usage: gcp_ours <commit-id> [commit-id2] ...
# Example: gcp_ours abc1234
gcp_ours() {
    if [ $# -eq 0 ]; then
        ux_usage "gcp_ours" "<commit-id> [commit-id2] ..." "Cherry-pick with 'ours' conflict strategy"
        ux_bullet "gcp_ours abc1234"
        ux_warning "Conflicts will use current branch (ours) changes"
        return 1
    fi

    local failed=0
    for commit in "$@"; do
        if git cherry-pick -X ours "$commit"; then
            ux_success "Cherry-pick -X ours succeeded: $commit"
        else
            ux_error "Cherry-pick -X ours failed: $commit"
            failed=1
            break
        fi
    done

    return $failed
}

# Cherry-pick by author in a commit range
# Usage: gcp_author <commit-range> [author-name]
# Example: gcp_author 751e304..7ffcbd4
# Example: gcp_author 751e304..7ffcbd4 dEitY719
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

# Show upstream branch logs
glub() {
    local branch="${1:-main}"
    git log --oneline -n 20 "upstream/$branch"
}

# Set upstream for current branch
alias gset-main='git branch --set-upstream-to=origin/main main'
alias gset-dev='git branch --set-upstream-to=origin/dev dev'

gset() {
    # Usage: gset <branch>
    local branch=${1:-$(git symbolic-ref --short HEAD)}
    git branch --set-upstream-to=origin/"$branch" "$branch"
}

# Git LFS install function (Ubuntu only)
git_lfs_install() {
    local script_path
    script_path="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/tools/custom/install_git_lfs.sh"

    if [ ! -f "$script_path" ]; then
        ux_error "install_git_lfs.sh not found: $script_path"
        return 1
    fi

    bash "$script_path" "$@"
}

# Git LFS track function
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

# NOTE: gcp_scan() function has been moved to shell-common/functions/gcp_scan.sh
# for portability across bash, zsh, and other shells. The function is available
# after sourcing that file, which is done automatically during initialization.
