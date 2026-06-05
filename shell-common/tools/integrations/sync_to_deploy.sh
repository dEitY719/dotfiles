#!/bin/sh
# shell-common/tools/integrations/sync_to_deploy.sh
# Merge internal/external main branches and push the result to a deploy branch.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

if ! type ux_header >/dev/null 2>&1; then
    _sync_to_deploy_dir="${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}"
    . "${_sync_to_deploy_dir}/tools/ux_lib/ux_lib.sh" 2>/dev/null || true
    unset _sync_to_deploy_dir
fi

_sync_to_deploy_usage() {
    ux_header "sync-to-deploy"
    ux_section "Usage"
    ux_bullet "sync-to-deploy <deploy-branch>"
    ux_section "Examples"
    ux_bullet "sync-to-deploy dev-server"
    ux_bullet "sync-to-deploy prod-server"
    ux_section "Environment overrides"
    ux_table_header "Variable" "Default" "Purpose"
    ux_table_row "SYNC_INTERNAL_REMOTE" "origin" "Remote that receives deploy branch"
    ux_table_row "SYNC_EXTERNAL_REMOTE" "upstream" "Remote merged into internal main"
    ux_table_row "SYNC_BRANCH" "main" "Source branch on both remotes"
    ux_table_row "SYNC_DEPLOY_WHITELIST" "" "Optional allowed deploy branches"
    ux_table_row "SYNC_TMP_BRANCH" "sync-to-deploy-tmp" "Temporary merge branch"
}

_sync_to_deploy_in_whitelist() {
    _sync_to_deploy_target="$1"
    _sync_to_deploy_list="$2"

    [ -n "$_sync_to_deploy_list" ] || return 0

    for _sync_to_deploy_branch in $_sync_to_deploy_list; do
        [ "$_sync_to_deploy_branch" = "$_sync_to_deploy_target" ] && return 0
    done

    return 1
}

_sync_to_deploy_ref_exists() {
    git show-ref --verify --quiet "$1"
}

sync_to_deploy() (
    case "${1:-}" in
    "" | -h | --help | help)
        [ -n "${1:-}" ] || ux_error "Deploy branch is required."
        _sync_to_deploy_usage
        [ -n "${1:-}" ]
        return $?
        ;;
    esac

    if [ $# -ne 1 ]; then
        ux_error "Expected exactly one deploy branch."
        _sync_to_deploy_usage
        return 1
    fi

    _sync_to_deploy_deploy_branch="$1"
    _sync_to_deploy_internal_remote="${SYNC_INTERNAL_REMOTE:-origin}"
    _sync_to_deploy_external_remote="${SYNC_EXTERNAL_REMOTE:-upstream}"
    _sync_to_deploy_branch="${SYNC_BRANCH:-main}"
    _sync_to_deploy_whitelist="${SYNC_DEPLOY_WHITELIST:-}"
    _sync_to_deploy_tmp_branch="${SYNC_TMP_BRANCH:-sync-to-deploy-tmp}"
    _sync_to_deploy_conflict=0

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        ux_error "Run from inside a git repository."
        return 1
    fi

    if ! _sync_to_deploy_in_whitelist "$_sync_to_deploy_deploy_branch" "$_sync_to_deploy_whitelist"; then
        ux_error "Deploy branch is not in SYNC_DEPLOY_WHITELIST: $_sync_to_deploy_deploy_branch"
        return 1
    fi

    if ! git diff-index --quiet HEAD --; then
        ux_error "Uncommitted changes found. Commit or stash before running sync-to-deploy."
        return 1
    fi

    _sync_to_deploy_original_ref="$(git symbolic-ref --short -q HEAD || git rev-parse HEAD)"
    if [ "$_sync_to_deploy_original_ref" = "$_sync_to_deploy_tmp_branch" ]; then
        ux_error "Already on temporary branch: $_sync_to_deploy_tmp_branch"
        return 1
    fi

    # shellcheck disable=SC2317  # invoked by trap
    _sync_to_deploy_cleanup() {
        [ "$_sync_to_deploy_conflict" -eq 1 ] && return 0
        git merge --abort >/dev/null 2>&1 || true
        _sync_to_deploy_current_ref="$(git symbolic-ref --short -q HEAD || git rev-parse HEAD)"
        if [ "$_sync_to_deploy_current_ref" != "$_sync_to_deploy_original_ref" ]; then
            git checkout "$_sync_to_deploy_original_ref" >/dev/null 2>&1 || true
        fi
        git branch -D "$_sync_to_deploy_tmp_branch" >/dev/null 2>&1 || true
    }
    trap _sync_to_deploy_cleanup EXIT HUP INT TERM

    ux_header "sync-to-deploy"
    ux_info "${_sync_to_deploy_internal_remote}/${_sync_to_deploy_branch} + ${_sync_to_deploy_external_remote}/${_sync_to_deploy_branch} -> ${_sync_to_deploy_internal_remote}/${_sync_to_deploy_deploy_branch}"

    ux_step 1 "Fetch internal branch"
    if ! git fetch "$_sync_to_deploy_internal_remote" "$_sync_to_deploy_branch"; then
        ux_error "Failed to fetch ${_sync_to_deploy_internal_remote}/${_sync_to_deploy_branch}."
        return 1
    fi

    ux_step 2 "Fetch external branch"
    if ! git fetch "$_sync_to_deploy_external_remote" "$_sync_to_deploy_branch"; then
        ux_error "Failed to fetch ${_sync_to_deploy_external_remote}/${_sync_to_deploy_branch}."
        return 1
    fi

    ux_step 3 "Create temporary branch"
    if ! git checkout -B "$_sync_to_deploy_tmp_branch" "${_sync_to_deploy_internal_remote}/${_sync_to_deploy_branch}" >/dev/null 2>&1; then
        ux_error "Failed to create temporary branch from ${_sync_to_deploy_internal_remote}/${_sync_to_deploy_branch}."
        return 1
    fi

    ux_step 4 "Merge external branch"
    if ! git merge --no-edit "${_sync_to_deploy_external_remote}/${_sync_to_deploy_branch}"; then
        _sync_to_deploy_conflict=1
        ux_error "Merge conflict while merging ${_sync_to_deploy_external_remote}/${_sync_to_deploy_branch}."
        ux_warning "Temporary branch preserved: $_sync_to_deploy_tmp_branch"
        ux_section "Manual recovery"
        ux_bullet "Resolve conflicts, then: git add <files> && git commit"
        ux_bullet "Push manually: git push $_sync_to_deploy_internal_remote $_sync_to_deploy_tmp_branch:$_sync_to_deploy_deploy_branch --force-with-lease=$_sync_to_deploy_deploy_branch"
        ux_bullet "Clean up: git checkout $_sync_to_deploy_original_ref && git branch -D $_sync_to_deploy_tmp_branch"
        ux_bullet "Cancel: git merge --abort && git checkout $_sync_to_deploy_original_ref && git branch -D $_sync_to_deploy_tmp_branch"
        return 1
    fi

    ux_step 5 "Push deploy branch"
    _sync_to_deploy_lease="--force-with-lease=${_sync_to_deploy_deploy_branch}"
    if _sync_to_deploy_ref_exists "refs/remotes/${_sync_to_deploy_internal_remote}/${_sync_to_deploy_deploy_branch}"; then
        _sync_to_deploy_lease="--force-with-lease=${_sync_to_deploy_deploy_branch}:refs/remotes/${_sync_to_deploy_internal_remote}/${_sync_to_deploy_deploy_branch}"
    fi

    if ! git push "$_sync_to_deploy_internal_remote" "${_sync_to_deploy_tmp_branch}:${_sync_to_deploy_deploy_branch}" "$_sync_to_deploy_lease"; then
        ux_error "Push failed. ${_sync_to_deploy_deploy_branch} may have changed since fetch."
        return 1
    fi

    ux_success "${_sync_to_deploy_internal_remote}/${_sync_to_deploy_deploy_branch} updated."
    ux_info "Returning to $_sync_to_deploy_original_ref and removing $_sync_to_deploy_tmp_branch."
)

alias sync-to-deploy='sync_to_deploy'
