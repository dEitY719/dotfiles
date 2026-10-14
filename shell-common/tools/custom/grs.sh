#!/bin/bash
# shell-common/tools/custom/grs.sh
# grs — friendly `git restore` wrapper (preflight Verdict + Next-action).
#
# PATH executable since #2195 (~/.local/bin/grs via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'grs'` resolve it too. The logic
# stays in functions/git_restore.sh (kept with its helpers; #2154 moves
# libraries out); its `grs` function is now a thin wrapper around this file.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1
# shellcheck source=/dev/null
DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/git_restore.sh" || exit 1

main() {
    _grs_main "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
