#!/bin/bash

# mcporter/setup.sh: point mcporter's exa server at ${EXA_API_KEY:-} (issue #2106)
#
# PURPOSE: Run mcporter_exa_setup so ~/.mcporter/mcporter.json holds the
#          placeholder instead of a plaintext Exa key.
# WHEN TO RUN: Via ./setup.sh (idempotent; safe to re-run)
#
# Never fails the parent setup (it runs under `set -e`): every problem is a
# ux_warning + exit 0. Skips when mcporter or jq is absent, when the config is
# already converted, and warns when .enc.env has no readable EXA_API_KEY yet.

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_ROOT="$(cd "${_SCRIPT_DIR}/.." && pwd)"
SHELL_COMMON="${DOTFILES_ROOT}/shell-common"

source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
# Both files are interactive-guarded; mcporter_exa_setup needs the .enc.env reader.
DOTFILES_FORCE_INIT=1 source "${SHELL_COMMON}/tools/integrations/sops.sh"
DOTFILES_FORCE_INIT=1 source "${SHELL_COMMON}/functions/secret_run.sh"

MCPORTER_CFG="${HOME}/.mcporter/mcporter.json"
# Single quotes on purpose: mcporter expands the placeholder, not the shell.
# shellcheck disable=SC2016
MCPORTER_EXA_URL='https://mcp.exa.ai/mcp?exaApiKey=${EXA_API_KEY:-}'

main() {
    if ! command -v mcporter >/dev/null 2>&1; then
        ux_info "mcporter not installed; skipping exa setup"
        return 0
    fi
    if ! command -v jq >/dev/null 2>&1; then
        ux_warning "jq not installed; exa setup skipped (install jq, then re-run ./mcporter/setup.sh)"
        return 0
    fi
    if [ -f "$MCPORTER_CFG" ] && jq -e --arg u "$MCPORTER_EXA_URL" \
        '.mcpServers.exa.baseUrl == $u and (.mcpServers.exa | has("url") | not)' \
        "$MCPORTER_CFG" >/dev/null 2>&1; then
        ux_info "mcporter exa already uses EXA_API_KEY placeholder"
        return 0
    fi
    if ! mcporter_exa_setup; then
        ux_warning "mcporter exa setup incomplete; see the message above, fix it, then re-run ./mcporter/setup.sh"
    fi
    return 0
}

main "$@"
