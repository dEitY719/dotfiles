#!/bin/bash
# shell-common/tools/custom/del_file.sh
# del-file / clean-home — interactive cleanup of backup/original/cache files.
#
# PATH executable since #2195 (~/.local/bin/del-file via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'del-file'` resolve it too. The logic
# stays in functions/file_cleanup.sh (kept with its helpers; #2154 moves
# libraries out); its `del_file` function is now a thin wrapper around this file.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1
# shellcheck source=/dev/null
DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/file_cleanup.sh" || exit 1

main() {
    _del_file_main "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
