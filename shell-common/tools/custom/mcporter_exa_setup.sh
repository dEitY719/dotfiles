#!/bin/bash
# shell-common/tools/custom/mcporter_exa_setup.sh
# mcporter-exa-setup — point mcporter's exa server at ${EXA_API_KEY:-} from .enc.env.
#
# PATH executable since #2195 (~/.local/bin/mcporter-exa-setup via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'mcporter-exa-setup'` resolve it too. The logic
# stays in functions/secret_run.sh (kept with its helpers; #2154 moves
# libraries out); its `mcporter_exa_setup` function is now a thin wrapper around this file.

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
        ux_usage "mcporter-exa-setup" "" "Rewrite ~/.mcporter/mcporter.json exa URL to read EXA_API_KEY at run time"
        ux_info "Details: sops-help secrets"
        return 0
        ;;
    esac
    _mcporter_exa_setup_main "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
