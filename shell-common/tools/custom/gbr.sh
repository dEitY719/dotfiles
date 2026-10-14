#!/bin/bash
# shell-common/tools/custom/gbr.sh
# gbr — git feature-branch dispatcher (gbr teardown).
#
# PATH executable since #2195 (~/.local/bin/gbr via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'gbr'` resolve it too. The logic
# stays in functions/git_branch.sh (kept with its helpers; #2154 moves
# libraries out); its `gbr` function is now a thin wrapper around this file.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1
# shellcheck source=/dev/null
DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/gh_host.sh" || exit 1 # _gh_host_from_url
# shellcheck source=/dev/null
DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/git_branch.sh" || exit 1

main() {
    _gbr_main "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
