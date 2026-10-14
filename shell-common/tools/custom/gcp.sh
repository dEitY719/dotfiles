#!/bin/bash
# shell-common/tools/custom/gcp.sh
# gcp — git cherry-pick family dispatcher (scan / theirs / ours / author / pick).
#
# PATH executable since #2195 (~/.local/bin/gcp via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'gcp'` resolve it too. The logic
# stays in functions/gcp.sh (kept with its helpers; #2154 moves
# libraries out); its `gcp` function is now a thin wrapper around this file.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1
# shellcheck source=/dev/null
DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/gcp_scan.sh" || exit 1 # _gcp_scan
# shellcheck source=/dev/null
DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/gcp.sh" || exit 1

main() {
    _gcp_main "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
