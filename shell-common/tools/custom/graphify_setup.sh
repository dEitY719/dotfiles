#!/bin/bash
# shell-common/tools/custom/graphify_setup.sh
# One-click, idempotent graphify onboarding for a project directory.
#
# Machine-wide steps (CLI, skill + account links) are skipped once done; the
# per-project steps (.gitignore, CLAUDE.md + hook, first graph) run in [dir].
#
# Usage: graphify_setup.sh [dir]   (alias: graphify-setup)

SHELL_COMMON="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../.." && pwd)"
source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

main() {
    local _gs_dir
    _gs_dir=$(cd "${1:-.}" 2>/dev/null && pwd) || {
        ux_error "No such directory: $1"
        return 1
    }
    ux_header "graphify setup: $_gs_dir"

    # 1. CLI (package graphifyy, command graphify)
    if command -v graphify >/dev/null 2>&1; then
        ux_success "CLI already installed"
    else
        ux_info "pip install graphifyy"
        pip install graphifyy && hash -r
        if ! command -v graphify >/dev/null 2>&1; then
            ux_error "graphify CLI still not on PATH after pip install graphifyy"
            return 1
        fi
    fi

    # 2. Skill + per-account links (graphify install --platform claude)
    bash "${SHELL_COMMON%/shell-common}/graphify/setup.sh"

    # 3. .gitignore
    if ! git -C "$_gs_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        ux_info "Not a git repo — .gitignore skipped"
    elif git -C "$_gs_dir" check-ignore -q graphify-out/; then
        ux_success "graphify-out/ already ignored"
    else
        # Keep the entry on its own line when the file lacks a trailing newline.
        [ -s "$_gs_dir/.gitignore" ] && [ -n "$(tail -c1 "$_gs_dir/.gitignore")" ] &&
            printf '\n' >>"$_gs_dir/.gitignore"
        printf 'graphify-out/\n' >>"$_gs_dir/.gitignore"
        ux_success "Added graphify-out/ to .gitignore"
    fi

    # 4. CLAUDE.md section + PreToolUse hook (.claude/settings.json)
    (cd "$_gs_dir" && graphify claude install) || ux_warning "graphify claude install failed"

    # 5. First graph: AST only, no LLM cost
    if [ -f "$_gs_dir/graphify-out/graph.json" ]; then
        ux_success "Graph already built (refresh: graphify update .)"
    else
        (cd "$_gs_dir" && graphify update .) || ux_warning "graphify update failed"
    fi

    ux_info "Next: run '/graphify .' in Claude Code for semantic (docs/images) extraction"
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    main "$@"
fi
