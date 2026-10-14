#!/bin/bash
# shell-common/tools/custom/mount_add.sh
# mount-add — bind-mount <source> onto <target> (sudo mount --bind).
#
# PATH executable since #2195 (~/.local/bin/mount-add via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'mount-add'` resolve it too. The logic
# stays in functions/mount.sh (kept with its helpers; #2154 moves
# libraries out); its `mount_add` function is now a thin wrapper around this file.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1
# shellcheck source=/dev/null
DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/mount.sh" || exit 1

main() {
    case "${1-}" in
    -h | --help)
        _mount_add_help
        return 0
        ;;
    esac
    _mount_add_main "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
