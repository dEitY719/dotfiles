#!/bin/sh
# shell-common/functions/graphify_vault.sh
# graphify-vault: export the current repo's graph as an Obsidian vault at ~/vaults/<repo>-graph.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

graphify_vault() {
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

alias graphify-vault='graphify_vault'
