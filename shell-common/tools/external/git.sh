#!/bin/bash
# shell-common/tools/external/git.sh
# Bash-specific git functions and features
# (This file requires bash and should not be sourced in other shells)

# Exit if not running in bash
[ -n "$BASH" ] || return 0

# ============================================================
# BASH-SPECIFIC HELPERS
# ============================================================

# Custom path abbreviation function (bash array syntax required)
_short_pwd() {
    local full_path
    full_path=$(pwd)
    local max_dirs=3
    local parts=()

    # Abbreviate home directory (~)
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
            fmt="${fmt//%s/$branch}"
            printf "%s%s" "$fmt" "$2"
        fi
    }
fi
export PS1="\[\e]0;\u@\h: \$(_short_pwd)\a\]\[\e[32m\]\u@\h:\[\e[33m\]\$(_short_pwd)\[\e[36m\]\$(__git_ps1 '(%s)')\[\e[0m\]\$ "

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
    ux_info "Starting Git LFS installation"

    # Update apt
    sudo apt-get update

    # Install git-lfs
    sudo apt-get install -y git-lfs

    # Initialize git-lfs
    git lfs install

    # Verify installation
    if command -v git-lfs &>/dev/null; then
        ux_success "Git LFS installed successfully"
        git lfs version
    else
        ux_error "Git LFS installation did not complete correctly"
    fi
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

# Intelligently identify and cherry-pick missing commits
# Compares two branches and shows commits present in source but missing in base.
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

    # Check for duplicate commits (same subject already in base branch)
    local final_selected_list=""
    local duplicate_list=""
    local duplicate_count=0

    while IFS= read -r sha; do
        [ -z "$sha" ] && continue
        local subject
        subject=$(git show -s --format='%s' "$sha")

        # Check if base branch has a commit with same subject (search recent 200 commits)
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
