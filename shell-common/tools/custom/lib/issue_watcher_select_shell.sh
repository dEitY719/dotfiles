#!/bin/sh
# shell-common/tools/custom/lib/issue_watcher_select_shell.sh
# Legacy jq/awk implementation of the issue watcher's candidate-selection ops,
# kept for one release as the IW_SELECT_IMPL=shell rollback (#2157). The default
# is the Python port, dotfiles_tools.issue_watcher.select — same ops, same
# stdin/stdout/exit contract; tests/py/test_issue_watcher_select.py proves the
# two agree. Delete this file together with the IW_SELECT_IMPL switch.
#
# Usage: _iw_sel_shell <op> [arg] < input   (ops: see select.py's docstring)
# Pure: reads stdin, writes stdout, no ux_lib, no network — sourceable alone.

_iw_sel_shell() {
    local _open

    case "$1" in
    search-rows)
        jq -r '
            .[]?
            | [ .repository.nameWithOwner,
                (.number | tostring),
                ([ .labels[]?.name ] | join("")) ]
            | @tsv
        ' 2>/dev/null || return 2
        ;;
    pr-count)
        jq -r 'length' 2>/dev/null || return 2
        ;;
    handled-by-pr)
        # How many open PRs close issue $2. The `\b` after the number is
        # load-bearing: without it `#14` would match a body that closes `#145`.
        jq -r --arg n "$2" '
            [ .[]?
              | select(
                  ((.headRefName // "") | test("^wt/issue-" + $n + "/"))
                  or ((.body // "")
                      | test("\\b(close[sd]?|fix(e[sd])?|resolve[sd]?):?\\s+(\\S+)?#" + $n + "\\b"; "i"))
                )
            ] | length
        ' 2>/dev/null || return 2
        ;;
    open-blockers)
        _open=$(jq -r '
            [ .data.repository.issue.blockedBy.nodes[]?
              | select(.state == "OPEN") | .number ] | join(",")
        ' 2>/dev/null) || _open=""
        printf '%s\n' "${_open}"
        [ -n "${_open}" ]
        ;;
    repo-order)
        awk -F "$(printf '\t')" -v last="$2" '
            { r[NR] = $1 }
            END {
                if (NR == 0) exit
                start = 1
                if (last != "") {
                    for (i = 1; i <= NR; i++) if (r[i] == last) { start = i + 1; break }
                }
                for (k = 0; k < NR; k++) print r[((start - 1 + k) % NR) + 1]
            }
        '
        ;;
    *) return 2 ;;
    esac
}
