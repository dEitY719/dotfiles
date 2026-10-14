#!/bin/sh
# shell-common/tools/custom/lib/merge_train_queue_shell.sh
# Legacy jq/shell implementation of the merge-train dispatcher's queue ops,
# kept for one release as the PMT_QUEUE_IMPL=shell rollback (#2174). The default
# is the Python port, dotfiles_tools.merge_train.queue — same ops, same
# stdin/stdout/exit contract; tests/py/test_merge_train_queue.py proves the two
# agree. Delete this file together with the PMT_QUEUE_IMPL switch (#2210).
#
# Usage: _pmt_q_shell <op> [arg...] < input   (ops: see queue.py's docstring)
# Pure: reads stdin, writes stdout, no ux_lib, no network — sourceable alone.

_pmt_q_shell() {
    local _fp _max _window=0 _remaining=0 _prev=""

    case "$1" in
    count)
        jq -r 'length' 2>/dev/null || return 2
        ;;
    fingerprint)
        jq -r '
            [ .[]?
              | [ (.number // "?" | tostring),
                  (.headRefOid // ""),
                  (.mergeStateStatus // ""),
                  (.mergeable // ""),
                  ([ .labels[]?.name?
                     | select(. == "review-passed" or . == "review-blocked"
                              or . == "reply-pending") ] | sort | join(","))
                ] | join(":")
            ] | sort | join(";")
        ' 2>/dev/null || return 2
        ;;
    backoff-next)
        [ "$#" -eq 3 ] || return 2
        _max="$2"
        _fp="$3"
        IFS=' ' read -r _window _remaining _prev || :
        # No fingerprint is no evidence: run, and record nothing.
        if [ -z "${_fp}" ]; then
            printf 'run\n'
            return 0
        fi
        # A truncated or hand-edited state line reads as "no window open".
        case "${_window}" in '' | *[!0-9]*) _window=0 ;; esac
        case "${_remaining}" in '' | *[!0-9]*) _remaining=0 ;; esac
        if [ "${_fp}" != "${_prev}" ]; then
            printf 'run 1 1\n'
        elif [ "${_remaining}" -gt 0 ]; then
            printf 'skip %s %s\n' "${_window}" "$((_remaining - 1))"
        else
            _window=$((_window * 2))
            [ "${_window}" -ge 1 ] || _window=1
            [ "${_window}" -le "${_max}" ] || _window="${_max}"
            printf 'run %s %s\n' "${_window}" "${_window}"
        fi
        ;;
    *) return 2 ;;
    esac
}
