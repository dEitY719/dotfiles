#!/usr/bin/env bash
# shell-common/tools/custom/devx.sh
# mytool entrypoint for the devx command router
# Usage: devx.sh <command>

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
SHELL_COMMON="${SHELL_COMMON:-$(cd "${script_dir}/.." && pwd)}"

# Load UX helpers when available for consistent messaging
if ! command -v ux_error >/dev/null 2>&1 && [ -f "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
    # shellcheck source=/dev/null
    . "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
fi

devx_functions="${SHELL_COMMON}/functions/devx.sh"
if [ ! -f "$devx_functions" ]; then
    if command -v ux_error >/dev/null 2>&1; then
        ux_error "devx functions file missing: ${devx_functions}"
    else
        printf 'devx: missing %s\n' "$devx_functions" >&2
    fi
    exit 1
fi

exec "$devx_functions" "$@"
