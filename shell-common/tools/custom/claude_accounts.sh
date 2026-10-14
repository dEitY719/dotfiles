#!/bin/bash
# shell-common/tools/custom/claude_accounts.sh
# Claude Code multi-account management (claude-accounts): status, setup, migrate, rollback, repair, link, unlink.
#
# The `claude_accounts` function in tools/integrations/claude.sh delegates
# here (#2146): the subcommands never change the parent shell's state
# (docs/.ssot/command-delivery-model.md §3), so their bodies need not be
# parsed at every interactive shell start. Bodies live in
# lib/claude_accounts_{auth,lifecycle,skills}.sh, which claude/setup.sh also
# sources directly.
#
# Usage: claude_accounts.sh [status|list|setup|migrate|rollback|repair|link|unlink|-h|--help]

# Keep the caller's DOTFILES_ROOT: an interactive shell has already
# canonicalized it to the main worktree (#589), and the setup/repair links are
# built from it. init.sh would otherwise reset it to this script's checkout.
_ca_caller_root="${DOTFILES_ROOT-}"
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/init.sh" || exit 1
[ -n "$_ca_caller_root" ] && DOTFILES_ROOT="$_ca_caller_root"
unset _ca_caller_root

# Account defaults only when the caller did not export them (direct exec
# outside an initialized shell); a live shell's values, including ad-hoc
# overrides, win.
if [ -z "${CLAUDE_ENABLED_ACCOUNTS+x}" ]; then
    # shellcheck source=/dev/null
    . "${SHELL_COMMON}/env/claude.sh"
fi
# _is_mounted / _skill_workspace_root: pure functions, loadable non-interactively.
# shellcheck source=/dev/null
. "${SHELL_COMMON}/functions/mount.sh" || exit 1
# shellcheck source=/dev/null
. "${SHELL_COMMON}/functions/skill_sources.sh" || exit 1
for _ca_lib in claude_accounts_auth claude_accounts_lifecycle claude_accounts_skills; do
    # shellcheck source=/dev/null
    . "${SHELL_COMMON}/tools/custom/lib/${_ca_lib}.sh" || exit 1
done
unset _ca_lib

main() {
    case "${1:-status}" in
        status)         claude_accounts_status ;;
        list)           _claude_resolve_account --list ;;
        setup)          claude_accounts_init ;;
        migrate)        claude_accounts_migrate ;;
        rollback)       shift; claude_accounts_rollback "$@" ;;
        repair)         shift; claude_accounts_repair "$@" ;;
        link)           shift; claude_accounts_link "$@" ;;
        unlink)         shift; claude_accounts_unlink "$@" ;;
        -h|--help|help) _claude_accounts_help ;;
        *)              ux_error "Unknown subcommand: $1"; _claude_accounts_help; return 1 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
