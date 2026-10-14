#!/bin/bash
# shell-common/tools/custom/gcp_scan.sh
#
# Cherry-pick scanner — finds the commits missing from <base> and picks them.
#
# PATH executable since #2155 (~/.local/bin/gcp-scan via config/symlinks.conf):
# a scan never changes the parent shell's state (cwd / env / alias —
# docs/.ssot/command-delivery-model.md §3), so AI agents' non-interactive
# `bash -c 'gcp-scan ...'` resolve it too. `gcp scan` (functions/gcp.sh) reaches
# it through the `_gcp_scan` wrapper in functions/gcp_scan.sh. This file only
# routes; the logic lives in lib/gcp_scan_{probe,conflict,lists,run}.sh.
# Settings reach it only as exported env (GCP_SCAN_*).
#
#   gcp-scan [base] [src] [--show-skip-list|--show-skip-paths|--show-deferred]
#            [--stop-on-conflict] [-h|--help]
#
# Running as bash (never sourced into an interactive zsh) also retires the
# parse-time alias imprint of #1663: no `cp -i` alias exists in this process.
#
# Note: git cherry marks commits as:
#   '+' = present in source, missing in base (will be cherry-picked)
#   '-' = already merged in base
#
# Redundant-commit handling (issue #913, supersedes #903/#907/#908/#910;
# UX improved by issue #961): each candidate is probed with
# `_gcp_scan_preflight_is_noop` (Stage-2) during the Analysis phase, BEFORE
# displaying the commit list. Noop commits are excluded from the display and
# the cherry-pick count so users never see a commit that will immediately be
# skipped. The execution loop reuses the Stage-2 result (noop_list) to avoid
# a double-probe. The probe uses git's own merge engine (`cherry-pick -n`) so
# it is immune to context-drift failures (comment rewrites, refactors) that
# broke earlier file-compare / reverse-patch heuristics.
#

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
_gcp_scan_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# shellcheck source=/dev/null
. "${_gcp_scan_dir}/init.sh" || exit 1
for _gcp_scan_lib in probe conflict lists run; do
    # shellcheck source=/dev/null
    . "${_gcp_scan_dir}/lib/gcp_scan_${_gcp_scan_lib}.sh" || exit 1
done
unset _gcp_scan_dir _gcp_scan_lib

main() {
    case "${1-}" in
    -h | --help)
        # gcp_help (functions/gcp.sh) owns the `scan` help section.
        # shellcheck source=/dev/null
        DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/gcp.sh"
        gcp_help scan
        return 0
        ;;
    esac
    _gcp_scan_run "$@"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
