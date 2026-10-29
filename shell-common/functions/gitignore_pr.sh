#!/bin/sh
# shell-common/functions/gitignore_pr.sh
# gitignore-pr: append patterns to the repo-root .gitignore and open a PR in one
# shot (issue #2324). Branches from origin/<default>, never from the current
# HEAD, and always returns the user to the branch they started on.
#
# User-facing command: gitignore-pr (dash-form) / internal: gitignore_pr()
# POSIX + bash/zsh: no arrays, "$@" loops, `return` not `exit`, no `set -e`.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# Strip trailing slashes: the comparison key that makes `.omo` == `.omo/`.
_gitignore_pr_key() {
    local k="$1"
    while [ "${k%/}" != "$k" ]; do k="${k%/}"; done
    printf '%s\n' "$k"
}

# F-4a: strip leading ./ and trailing /, non [A-Za-z0-9-] -> -, join with -, cap 40.
_gitignore_pr_slug() {
    printf '%s\n' "$1" \
        | sed -e 's#^[./]*##' -e 's#/*$##' -e 's#[^A-Za-z0-9-]#-#g' -e '/^$/d' \
        | paste -sd- - | cut -c1-40
}

# F-5: origin/HEAD, then origin/main, then origin/master. Empty on failure.
_gitignore_pr_default_branch() {
    local ref b
    ref="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
    if [ -n "$ref" ]; then
        printf '%s\n' "${ref#origin/}"
        return 0
    fi
    for b in main master; do
        if git show-ref --verify --quiet "refs/remotes/origin/$b"; then
            printf '%s\n' "$b"
            return 0
        fi
    done
    return 1
}

# Work done on the chore branch. The caller owns returning to the original
# branch. Args: <root> <default> <branch> <repo> <added-newline-list> <title>
_gitignore_pr_commit_push_pr() {
    local root="$1" def="$2" branch="$3" repo="$4" added="$5" title="$6"
    local gi="$root/.gitignore" out body

    if [ -s "$gi" ] && [ -n "$(tail -c1 "$gi")" ]; then
        printf '\n' >>"$gi"
    fi
    if ! grep -qxF '# Agent/extra ignores' "$gi" 2>/dev/null; then
        printf '%s\n' '# Agent/extra ignores' >>"$gi"
    fi
    printf '%s\n' "$added" >>"$gi"

    git -C "$root" add .gitignore
    if ! out="$(git -C "$root" commit -q -m "$title" 2>&1)"; then
        ux_error "gitignore-pr: commit failed (hook?)"
        [ -n "$out" ] && ux_info "$out"
        git -C "$root" reset -q --hard HEAD
        return 3 # caller deletes the empty chore branch
    fi
    ux_success "Committed: $title"

    if ! git -C "$root" push -q -u origin "$branch"; then
        ux_error "gitignore-pr: push failed — commit kept on $branch"
        ux_info "Retry: git push -u origin $branch"
        return 1
    fi

    # shellcheck disable=SC2016 # backticks are literal Markdown
    body="Add to .gitignore:
$(printf '%s\n' "$added" | sed 's/.*/- `&`/')"
    if ! out="$(gh pr create --repo "$repo" --base "$def" --head "$branch" \
        --title "$title" --body "$body" --assignee @me 2>&1)"; then
        ux_error "gitignore-pr: gh pr create failed: $(printf '%s\n' "$out" | sed -n '1p')"
        ux_info "Branch and commit kept. Create manually: gh pr create --repo $repo --base $def --head $branch"
        return 1
    fi
    ux_success "PR: $(printf '%s\n' "$out" | sed -n '$p')"
    return 0
}

gitignore_pr() {
    case "${1:-}" in
        -h | --help | help)
            gitignore_pr_help
            return 0
            ;;
    esac

    local root
    if ! root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
        ux_error "gitignore-pr: not a git repository"
        return 1
    fi

    # F-2: no args -> list untracked entries, change nothing.
    if [ $# -eq 0 ]; then
        ux_header "Untracked entries"
        local u
        git -C "$root" status --short --untracked-files=normal | sed -n 's/^?? //p' \
            | while IFS= read -r u; do ux_bullet "$u"; done
        ux_info "Usage: gitignore-pr <pattern>..."
        return 0
    fi

    if ! command -v gh >/dev/null 2>&1; then
        ux_error "gitignore-pr: gh CLI not found"
        return 1
    fi

    # F-6: --repo HOST/OWNER/REPO from origin, via the gh_host.sh SSOT.
    # Raw config value (not `git remote get-url`) so insteadOf rewrites do not
    # change which host we pin.
    command -v _gh_host_from_url >/dev/null 2>&1 ||
        . "${SHELL_COMMON:-$HOME/dotfiles/shell-common}/lib/gh_host.sh" 2>/dev/null
    if ! command -v _gh_host_from_url >/dev/null 2>&1; then
        ux_error "gitignore-pr: cannot load shell-common/lib/gh_host.sh"
        return 1
    fi
    local url host slug repo
    url="$(git -C "$root" config --get remote.origin.url)"
    if [ -z "$url" ]; then
        ux_error "gitignore-pr: no origin remote"
        return 1
    fi
    if ! host="$(_gh_host_from_url "$url" 2>/dev/null)" \
        || ! slug="$(_gh_parse_owner_repo_url "$url" 2>/dev/null)"; then
        ux_error "gitignore-pr: origin is not a known GitHub remote: $url"
        return 1
    fi
    repo="$host/$slug"

    # NF-1: no staged/unstaged tracked changes (untracked files are fine).
    if [ -n "$(git -C "$root" status --porcelain --untracked-files=no)" ]; then
        ux_error "gitignore-pr: working tree has uncommitted changes — commit or stash them first"
        return 1
    fi

    local def
    if ! def=$(_gitignore_pr_default_branch); then
        git -C "$root" fetch -q origin 2>/dev/null
        if ! def=$(_gitignore_pr_default_branch); then
            ux_error "gitignore-pr: cannot detect origin's default branch"
            return 1
        fi
    fi
    if ! git -C "$root" fetch -q origin "$def"; then
        ux_error "gitignore-pr: git fetch origin $def failed"
        return 1
    fi

    # F-1 + F-3: normalize, then skip what origin/<default>'s .gitignore (and
    # earlier args) already hold. Read via `git show` so no branch is created
    # when everything is skipped.
    local existing p norm key added=""
    # Same normalization as _gitignore_pr_key, one sed for the whole file.
    existing="$(git -C "$root" show "origin/$def:.gitignore" 2>/dev/null | sed 's#/*$##')"
    # A newline would split one arg into several lines; a leading # is a comment.
    for p in "$@"; do
        case $p in
            *'
'* | '#'*)
                ux_error "gitignore-pr: invalid pattern (newline or leading #): $p"
                return 1
                ;;
        esac
    done
    for p in "$@"; do
        norm="$p"
        # ./foo and <root>/foo are not valid gitignore spellings: make root-relative.
        while [ "${norm#./}" != "$norm" ]; do norm="${norm#./}"; done
        case $norm in "$root"/*) norm="${norm#"$root"/}" ;; esac
        key=$(_gitignore_pr_key "$norm")
        [ -d "$root/${norm#/}" ] && norm=$key/
        if [ -z "$key" ]; then
            ux_warning "Ignoring empty pattern: $p"
            continue
        fi
        if printf '%s\n' "$existing" | grep -qxF -- "$key"; then
            ux_info "Already in .gitignore: $norm (skipped)"
            continue
        fi
        existing="$existing
$key"
        added="${added:+$added
}$norm"
    done
    if [ -z "$added" ]; then
        ux_success "Nothing to add — all patterns already ignored"
        return 0
    fi

    # F-4 / F-4a / F-4b
    local branch
    branch=chore/gitignore-$(_gitignore_pr_slug "$added")
    if git -C "$root" show-ref --verify --quiet "refs/heads/$branch" \
        || git -C "$root" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
        ux_error "gitignore-pr: branch $branch already exists (local or origin) — not touching it"
        ux_info "Existing PR: gh pr list --repo $repo --head $branch --state all"
        return 1
    fi

    local title n
    title="chore: ignore $(printf '%s\n' "$added" | paste -sd' ' -)"
    if [ "${#title}" -gt 72 ]; then
        n=$(($(printf '%s\n' "$added" | wc -l) - 1))
        title="chore: ignore $(printf '%s\n' "$added" | sed -n '1p')"
        [ "$n" -gt 0 ] && title="$title and $n more"
    fi

    # F-4c: remember where we were; detached HEAD returns to the same commit.
    local orig orig_detached=""
    if ! orig="$(git -C "$root" symbolic-ref --quiet --short HEAD)"; then
        orig="$(git -C "$root" rev-parse HEAD)"
        orig_detached=1
    fi

    if ! git -C "$root" switch -q -c "$branch" "origin/$def"; then
        ux_error "gitignore-pr: cannot create $branch from origin/$def"
        return 1
    fi

    local rc=0
    _gitignore_pr_commit_push_pr "$root" "$def" "$branch" "$repo" "$added" "$title" || rc=$?

    if [ -n "$orig_detached" ]; then
        git -C "$root" switch -q --detach "$orig"
    else
        git -C "$root" switch -q "$orig"
    fi
    # shellcheck disable=SC2181 # status of the if/else switch above
    if [ $? -ne 0 ]; then
        ux_warning "gitignore-pr: could not switch back — still on $branch"
        ux_info "Return manually: git switch $orig (add --detach for a commit)"
        [ "$rc" -eq 3 ] && rc=1 # chore branch is checked out: keep it
    elif [ "$rc" -eq 3 ]; then
        git -C "$root" branch -q -D "$branch"
        rc=1
    fi
    return "$rc"
}

alias gitignore-pr='gitignore_pr'
