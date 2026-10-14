#!/bin/bash
# shell-common/tools/custom/gh_flow.sh
# gh-flow — fire-and-forget N-parallel GitHub issue -> PR automation.
#
# PATH executable since #2195 (~/.local/bin/gh-flow via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'gh-flow ...'` resolve it. The logic
# stays in functions/gh_flow.sh (also a helper library, #2154); this sources it and
# calls _gh_flow_main. functions/gh_flow.sh keeps the `gh_flow` / `gh-flow` names as a
# thin wrapper.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1

# Dispatcher preconditions the interactive shell used to provide: _have (from
# projects/*.sh), _claude_resolve_account (--user), gwt / git_worktree_teardown
# (precondition check, prune --force). Detached workers source ~/.bashrc.
command -v _have >/dev/null 2>&1 || _have() { command -v "$1" >/dev/null 2>&1; }
# shellcheck source=/dev/null
. "${SHELL_COMMON}/tools/custom/lib/claude_accounts_auth.sh" || exit 1
for _lib in git_worktree git_worktree_spawn; do
    # shellcheck source=/dev/null
    DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/${_lib}.sh" || exit 1
done
unset _lib
# shellcheck source=/dev/null
DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/gh_flow.sh" || exit 1

main() {
    _gh_flow_main "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
