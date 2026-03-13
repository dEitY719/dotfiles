#!/bin/sh
# shell-common/functions/git_help.sh
# gitHelp - shared between bash and zsh

git_help() {
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
    ux_table_row "grs" "git restore" "Discard changes in file"
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
    ux_table_row "gl" "git-log" "Graph log (default 11)"
    ux_table_row "gl1" "log --oneline" "One-line graph log"
    ux_table_row "gl2" "git-log2" "Alternative log format"
    ux_table_row "glref" "log ref/main" "Ref log for main"
    echo ""

    ux_section "Upstream"
    ux_table_row "gupa" "remote add upstream" "Add upstream remote"
    ux_table_row "gupdel" "gupdel <remote>" "Remove remote"
    ux_table_row "glum" "git-log-upstream" "Upstream main log"
    ux_table_row "glub" "glub [branch]" "Upstream branch log"
    echo ""

    ux_section "Branch Configuration"
    ux_table_row "gset-main" "set-upstream main" "Track origin/main"
    ux_table_row "gset-dev" "set-upstream dev" "Track origin/dev"
    ux_table_row "gset" "gset [branch]" "Track origin/[branch]"
    ux_table_row "gprune" "git-prune-remote <remote>" "Delete all branches except main"
    ux_table_row "git-clean-local" "git_clean_local" "Delete local branches (keeps: main + current)"
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

    ux_section "SSH & Authentication"
    ux_table_row "git_ssh_check" "Test GitHub SSH" "Verify GitHub SSH connection"
    ux_table_row "git_ssh_setup" "Setup SSH" "Manual SSH configuration guide"
    echo ""
}

# Alias for git-help format (using dash instead of underscore)
alias git-help='git_help'
