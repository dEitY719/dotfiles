#!/bin/sh
# shell-common/functions/git_help.sh

_git_help_summary() {
    ux_info "Usage: git-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "basic: gs | ga | gc | gca | gp | gpl | gco | gd | grs | gb | grmc"
    ux_bullet_sub "sync: gf | gfu | gfa | gsw | gr"
    ux_bullet_sub "logs: gl | gl1 | gl2 | glref"
    ux_bullet_sub "upstream: gupa | gupdel | glum | glub"
    ux_bullet_sub "branch: gset-main | gset-dev | gset | gprune | git-clean-local"
    ux_bullet_sub "stash: git stash list | show -p | pop | apply | drop"
    ux_bullet_sub "pick: gcp | gcp_theirs | gcp_ours | gcp_author | gcp_scan"
    ux_bullet_sub "special: gpf_dev_server | gpfu"
    ux_bullet_sub "lfs: git_lfs_install | glfs"
    ux_bullet_sub "ssh: git_ssh_check | git_ssh_setup"
    ux_bullet_sub "details: git-help <section>  (example: git-help stash)"
}

_git_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "basic"
    ux_bullet_sub "sync"
    ux_bullet_sub "logs"
    ux_bullet_sub "upstream"
    ux_bullet_sub "branch"
    ux_bullet_sub "stash"
    ux_bullet_sub "pick"
    ux_bullet_sub "special"
    ux_bullet_sub "lfs"
    ux_bullet_sub "ssh"
}

_git_help_rows_basic() {
    ux_table_row "gs" "git status -sb" "Short status"
    ux_table_row "ga" "git add ." "Stage all changes"
    ux_table_row "gc" "git commit -m" "Commit with message"
    ux_table_row "gca" "git commit --amend" "Amend last commit"
    ux_table_row "gp" "git push" "Push to remote"
    ux_table_row "gpl" "git pull" "Pull from remote"
    ux_table_row "gco" "git checkout" "Checkout branch/commit"
    ux_table_row "gd" "git diff" "Show changes"
    ux_table_row "grs" "git restore" "Discard changes in file"
    ux_table_row "gb" "git branch" "List branches"
    ux_table_row "grmc" "git rm --cached" "Unstage, keep file"
}

_git_help_rows_sync() {
    ux_table_row "gf [remote]" "gf / gf u / gf <name>" "Fetch & prune (default: origin, u=upstream)"
    ux_table_row "gfu" "git fetch upstream" "Fetch upstream"
    ux_table_row "gfa" "git fetch --all" "Fetch all & prune"
    ux_table_row "gsw" "git switch -c" "Switch to remote branch"
    ux_table_row "gr" "git remote -v" "List remotes"
}

_git_help_rows_logs() {
    ux_table_row "gl" "git-log" "Graph log (default 11)"
    ux_table_row "gl1" "log --oneline" "One-line graph log"
    ux_table_row "gl2" "git-log2" "Alternative log format"
    ux_table_row "glref" "log ref/main" "Ref log for main"
}

_git_help_rows_upstream() {
    ux_table_row "gupa" "remote add upstream" "Add upstream remote"
    ux_table_row "gupdel" "gupdel <remote>" "Remove remote"
    ux_table_row "glum" "git-log-upstream" "Upstream main log"
    ux_table_row "glub" "glub [branch]" "Upstream branch log"
}

_git_help_rows_branch() {
    ux_table_row "gset-main" "set-upstream main" "Track origin/main"
    ux_table_row "gset-dev" "set-upstream dev" "Track origin/dev"
    ux_table_row "gset" "gset [branch]" "Track origin/[branch]"
    ux_table_row "gprune" "git-prune-remote <remote>" "Delete all branches except main"
    ux_table_row "git-clean-local" "git_clean_local" "Delete local branches (keeps: main + current)"
}

_git_help_rows_stash() {
    ux_table_row "git stash list" "git stash list" "List saved stashes"
    ux_table_row "git stash show -p" "git stash show -p [stash]" "Show stashed patch (default: latest)"
    ux_table_row "git stash pop" "git stash pop [stash]" "Apply stash and remove it"
    ux_table_row "git stash apply" "git stash apply [stash]" "Apply stash and keep it"
    ux_table_row "git stash drop" "git stash drop [stash]" "Delete a stash entry"
}

_git_help_rows_pick() {
    ux_table_row "gcp" "gcp <commit>..." "Cherry-pick commits"
    ux_table_row "gcp_theirs" "gcp_theirs <commit>..." "Cherry-pick with -X theirs (incoming)"
    ux_table_row "gcp_ours" "gcp_ours <commit>..." "Cherry-pick with -X ours (current)"
    ux_table_row "gcp_author" "gcp_author <range> [author]" "Cherry-pick by author"
    ux_table_row "gcp_scan" "gcp_scan [base] [src] [--author=<name|all>]" "Compare & pick missing (default: main <- upstream/main, author=dEitY719)"
}

_git_help_rows_special() {
    ux_table_row "gpf_dev_server" "push force dev" "Force push dev-server"
    ux_table_row "gpfu" "push --force-with-lease" "Force push main"
}

_git_help_rows_lfs() {
    ux_table_row "git_lfs_install" "Install LFS" "Ubuntu setup"
    ux_table_row "glfs" "track <pattern>" "Track files with LFS"
}

_git_help_rows_ssh() {
    ux_table_row "git_ssh_check" "Test GitHub SSH" "Verify GitHub SSH connection"
    ux_table_row "git_ssh_setup" "Setup SSH" "Manual SSH configuration guide"
}

_git_help_notes_pick_strategy() {
    ux_bullet "gcp_theirs: ${UX_ERROR}Conflict${UX_RESET} 발생시 ${UX_WARNING}incoming(cherry-pick되는 커밋의 변경)${UX_RESET} 선택"
    ux_bullet "gcp_ours: ${UX_ERROR}Conflict${UX_RESET} 발생시 ${UX_SUCCESS}current branch(현재 브랜치의 변경)${UX_RESET} 선택"
}

_git_help_render_section() {
    ux_section "$1"
    "$2"
}

_git_help_section_rows() {
    case "$1" in
        basic)
            _git_help_rows_basic
            ;;
        sync|fetch)
            _git_help_rows_sync
            ;;
        logs|log)
            _git_help_rows_logs
            ;;
        upstream)
            _git_help_rows_upstream
            ;;
        branch|branches)
            _git_help_rows_branch
            ;;
        stash)
            _git_help_rows_stash
            ;;
        pick|cherrypick|cherry-pick)
            _git_help_rows_pick
            ;;
        special)
            _git_help_rows_special
            ;;
        lfs)
            _git_help_rows_lfs
            ;;
        ssh|auth)
            _git_help_rows_ssh
            ;;
        *)
            ux_error "Unknown git-help section: $1"
            ux_info "Try: git-help --list"
            return 1
            ;;
    esac
}

_git_help_full() {
    ux_header "Git Quick Commands"

    _git_help_render_section "Basic Commands" _git_help_rows_basic
    _git_help_render_section "Fetch & Sync" _git_help_rows_sync
    _git_help_render_section "Logs" _git_help_rows_logs
    _git_help_render_section "Upstream" _git_help_rows_upstream
    _git_help_render_section "Branch Configuration" _git_help_rows_branch
    _git_help_render_section "Stash" _git_help_rows_stash
    _git_help_render_section "Cherry-pick" _git_help_rows_pick
    _git_help_render_section "Cherry-pick -X (Merge Strategy)" _git_help_notes_pick_strategy
    _git_help_render_section "Special" _git_help_rows_special
    _git_help_render_section "Git LFS" _git_help_rows_lfs
    _git_help_render_section "SSH & Authentication" _git_help_rows_ssh
}

git_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _git_help_summary
            ;;
        --list|list|section|sections)
            _git_help_list_sections
            ;;
        --all|all)
            _git_help_full
            ;;
        *)
            _git_help_section_rows "$1"
            ;;
    esac
}

alias git-help='git_help'
