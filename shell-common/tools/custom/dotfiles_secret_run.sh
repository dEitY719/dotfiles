#!/bin/bash
# shell-common/tools/custom/dotfiles_secret_run.sh
# secret-run — run one command with the repo .enc.env values injected.
#
# PATH executable since #2195 (~/.local/bin/secret-run via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'secret-run'` resolve it too. The logic
# stays in functions/secret_run.sh (kept with its helpers; #2154 moves
# libraries out); its `dotfiles_secret_run` function is now a thin wrapper around this file.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1
# shellcheck source=/dev/null
DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/tools/integrations/sops.sh" || exit 1 # _senv_*
# shellcheck source=/dev/null
DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/secret_run.sh" || exit 1

main() {
    case "${1-}" in
    -h | --help)
        ux_usage "secret-run" "[-k KEY]... <cmd...>" "Run a command with the repo .enc.env secrets injected"
        ux_info "Details: sops-help secrets"
        return 0
        ;;
    esac
    _dotfiles_secret_run_main "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
