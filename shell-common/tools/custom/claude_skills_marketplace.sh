#!/bin/bash
# shell-common/tools/custom/claude_skills_marketplace.sh
# claude-skills-marketplace (csm) — browse / search the cached marketplace skills manifest.
#
# PATH executable since #2195 (~/.local/bin/claude-skills-marketplace via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'claude-skills-marketplace'` resolve it too. The logic
# stays in functions/marketplace.sh (kept with its helpers; #2154 moves
# libraries out); its `claude_skills_marketplace` function is now a thin wrapper around this file.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1
# shellcheck source=/dev/null
DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/marketplace.sh" || exit 1

main() {
    case "${1-}" in
    -h | --help)
        shift
        claude_skills_marketplace_help "$@"
        return 0
        ;;
    esac
    _claude_skills_marketplace_main "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
