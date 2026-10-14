#!/bin/sh
# shell-common/util/local_env.sh — machine-local env override loader (#2158).
#
# Guard-free pure lib, no output: env/*.sh source it when readable (hooks
# and one-shot scripts source env files without the loader) and call
#   _dotfiles_source_local <topic> [shell-common root]
# which sources <root>/env/<topic>.local.sh (gitignored) when it exists,
# unless DOTFILES_SKIP_LOCAL_ENV is set (#2031, test isolation). Runs in
# function scope: a local file must not rely on `local`/`typeset` at top level.

_dotfiles_source_local() {
    _dsl_file="${2:-${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}}/env/${1:?topic}.local.sh"
    if [ -z "${DOTFILES_SKIP_LOCAL_ENV-}" ] && [ -f "$_dsl_file" ]; then
        # shellcheck source=/dev/null
        . "$_dsl_file"
    fi
    unset _dsl_file
}
