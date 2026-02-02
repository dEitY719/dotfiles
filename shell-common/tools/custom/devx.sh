#!/bin/bash
# devx.sh - Executable wrapper for the `devx` function
#
# This script exists so `devx` can be run as a standalone command without relying
# on shell initialization auto-sourcing `shell-common/functions/devx.sh`.

_devx_load_ux_lib() {
    if command -v ux_info >/dev/null 2>&1; then
        return 0
    fi

    if [ -n "${SHELL_COMMON:-}" ] && [ -f "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
        # shellcheck source=/dev/null
        source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
        return 0
    fi

    return 0
}

main() {
    local script_dir dotfiles_root

    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
    dotfiles_root="$(cd "${script_dir}/../../.." >/dev/null 2>&1 && pwd)"

    export DOTFILES_ROOT="${DOTFILES_ROOT:-$dotfiles_root}"
    export SHELL_COMMON="${SHELL_COMMON:-${DOTFILES_ROOT}/shell-common}"

    _devx_load_ux_lib || true

    if [ ! -f "${SHELL_COMMON}/functions/devx.sh" ]; then
        if command -v ux_error >/dev/null 2>&1; then
            ux_error "Missing: ${SHELL_COMMON}/functions/devx.sh"
        else
            echo "Missing: ${SHELL_COMMON}/functions/devx.sh" >&2
        fi
        return 1
    fi

    # shellcheck source=/dev/null
    source "${SHELL_COMMON}/functions/devx.sh"

    devx "$@"
}

# shellcheck disable=SC2128
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
