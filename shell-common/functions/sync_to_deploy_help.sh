#!/bin/sh
# shell-common/functions/sync_to_deploy_help.sh

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

sync_to_deploy_help() {
    ux_header "sync-to-deploy"

    ux_section "Usage"
    ux_bullet "sync-to-deploy <deploy-branch>"

    ux_section "Examples"
    ux_bullet "sync-to-deploy dev-server"
    ux_bullet "sync-to-deploy prod-server"

    ux_section "What it does"
    ux_bullet "Fetches origin/main and upstream/main by default"
    ux_bullet "Creates a temporary branch from the internal main branch"
    ux_bullet "Merges the external main branch into that temporary branch"
    ux_bullet "Pushes the merge result to the deploy branch with force-with-lease"
    ux_bullet "Returns to the original branch and removes the temporary branch on success"

    ux_section "Environment overrides"
    ux_table_header "Variable" "Default" "Purpose"
    ux_table_row "SYNC_INTERNAL_REMOTE" "origin" "Remote that receives deploy branch"
    ux_table_row "SYNC_EXTERNAL_REMOTE" "upstream" "Remote merged into internal main"
    ux_table_row "SYNC_BRANCH" "main" "Source branch on both remotes"
    ux_table_row "SYNC_DEPLOY_WHITELIST" "" "Optional allowed deploy branches"
    ux_table_row "SYNC_TMP_BRANCH" "sync-to-deploy-tmp" "Temporary merge branch"

    ux_section "Safety"
    ux_bullet "Stops when the worktree has uncommitted changes"
    ux_bullet "Preserves the temporary branch on merge conflict"
    ux_bullet "Uses force-with-lease instead of plain force push"
}

alias sync-to-deploy-help='sync_to_deploy_help'

# Help registry (#2135): skipped when sourced without util/help_registry.sh.
command -v _register_help >/dev/null 2>&1 || return 0
_register_help sync_to_deploy_help "[DevOps] Merge internal/external main branches and push a deploy branch" devops
