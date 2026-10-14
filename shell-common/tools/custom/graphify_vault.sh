#!/bin/bash
# shell-common/tools/custom/graphify_vault.sh
# graphify-vault: export the current repo's graph as an Obsidian vault at ~/vaults/<repo>-graph.
#
# PATH executable since #2195 (~/.local/bin/graphify-vault via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'graphify-vault'` resolves it.
# functions/graphify_vault.sh keeps the `graphify_vault` / `graphify-vault` names as a thin wrapper.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1

_graphify_vault_help() {
    ux_usage "graphify-vault" "" "Export the repo's graphify graph as an Obsidian vault"
    ux_bullet "Target: \${GRAPHIFY_VAULT_ROOT:-~/vaults}/<repo>-graph"
    ux_bullet "Needs graphify-out/graph.json (run '/graphify .' first)"
}

graphify_vault() {
    case "${1-}" in -h | --help | help)
        _graphify_vault_help
        return 0
        ;;
    esac
    _gv_root=$(git rev-parse --show-toplevel 2>/dev/null) || _gv_root=$PWD
    _gv_dir="${GRAPHIFY_VAULT_ROOT:-$HOME/vaults}/$(basename "$_gv_root")-graph"

    if ! command -v graphify >/dev/null 2>&1; then
        ux_error "graphify not found (pip install graphifyy)"
        return 1
    fi
    if [ ! -f "$_gv_root/graphify-out/graph.json" ]; then
        ux_error "graphify-out/graph.json not found in $_gv_root"
        ux_info "Run '/graphify .' in Claude Code first"
        return 1
    fi

    ux_info "Exporting to $_gv_dir"
    (cd "$_gv_root" && graphify export obsidian --dir "$_gv_dir") || return 1
    ux_success "Open $_gv_dir as a vault in Obsidian"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    graphify_vault "$@"
fi
