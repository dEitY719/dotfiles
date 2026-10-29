#!/bin/bash
# shell-common/tools/custom/avatar_tab_teardown.sh
# avatar-tab-teardown (#2320): close the herdr tabs the unattended pipelines
# opened once their session is over, and optionally remove their worktrees.
#
#   iw  avatar_issue_watcher.sh tick   agent iw-<repo>-issue-<N>, label = name
#   mt  pr_merge_train_cron.sh         agent mt-<repo>, label = name (or -STUCK)
#   mv  gh-verify:post-merge-verify    agent mv-<repo>-pr-<N>, label pr-<N>,
#                                      cwd <git-common-dir>/pr-post-merge-verify/pr-<N>
#
# Ownership is read from the agent name first (shell-common/lib/
# herdr_agent_name.sh herdr_agent_parse_name), then the tab label, then the mv
# scratch cwd. A tab with none of those signals (a hand-made `issue-<N>` or
# `pr-<N>` tab) is never a candidate.
#
# A candidate closes only when it has an agent (#2322: an agent-less tab may
# hold a human's shell, so "finished" cannot be confirmed), none of its agents
# is working/blocked AND (iw) its issue is CLOSED / (mv) its PR is MERGED; mt
# needs nothing more. --force bypasses all of these, so the label and mv
# scratch-cwd fallbacks below only yield a closable agent-less tab under it.
# No zombie grace: the human running this is the second observation. The
# calling pane's own tab is always skipped, --force included. Default is a
# dry run.
#
# Only `herdr tab close` and `gwt remove` mutate anything — no pane, workspace
# or session is closed and nothing is deleted with rm.
#
# Usage: avatar-tab-teardown [--yes] [--worktree] [--force] [--repo <slug>]
#                            [--issue <N>] [-h|--help]

# readlink -f: resolve a ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1
# shellcheck source=/dev/null
. "${SHELL_COMMON}/lib/herdr_agent_name.sh" || exit 1
# shellcheck source=/dev/null
. "${SHELL_COMMON}/lib/herdr_agent_lookup.sh" || exit 1

_ATT_US=$'\x1f' # field separator: unlike TAB it keeps empty fields under `read`
_ATT_WATCH=""   # `<owner/repo>\t<path>\t<host>` per watched entry

# Load the issue-watcher watch list (same file and shapes avatar-issue-watcher reads).
_att_load_watch_list() {
    local _file="${IW_WATCHED_REPOS:-${HOME}/.avatars/issue-watcher/watched-repos.json}"
    [ -f "${_file}" ] || return 0
    _ATT_WATCH=$(jq -r '
        (if type == "array" then . else (.repos // []) end) | .[]?
        | select(type == "object" and (.repo // "") != "" and (.path // "") != "")
        | [.repo, .path, (.host // "github.com")] | @tsv' "${_file}" 2>/dev/null |
        while IFS=$'\t' read -r _r _p _h; do printf '%s\t%s\t%s\n' "${_r}" "$(_att_phys "${_p}")" "${_h}"; done)
}

# Echo the physical path of directory <1> (symlinks, trailing `/` resolved), or
# <1> itself when it is not a directory: herdr cwds and `pwd -P` are physical,
# a hand-written watch list or a worktree registration may not be.
_att_phys() {
    (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"
}

# Echo the watch-list row whose repo normalizes to slug <1>. rc 1 none, 3 ambiguous.
_att_repo_for_slug() {
    local _repo _path _host _hits="" _n=0
    while IFS=$'\t' read -r _repo _path _host; do
        [ -n "${_repo}" ] || continue
        [ "$(herdr_agent_repo_slug "${_repo}")" = "$1" ] || continue
        _hits="${_repo}"$'\t'"${_path}"$'\t'"${_host}"
        _n=$((_n + 1))
    done <<EOF
${_ATT_WATCH}
EOF
    [ "${_n}" -eq 1 ] && { printf '%s' "${_hits}"; return 0; }
    [ "${_n}" -eq 0 ] && return 1
    return 3
}

# Echo the main checkout owning the git checkout at <1>.
_att_main_checkout() {
    local _c
    _c=$(cd "$1" 2>/dev/null && _g=$(git rev-parse --git-common-dir 2>/dev/null) && cd "${_g}" && pwd -P) || return 1
    case "${_c}" in */.git) dirname "${_c}" ;; *) return 1 ;; esac
}

# Echo `<owner/repo>\t<path>\t<host>` for a checkout the watch list does not
# name (mt fallback): owner/repo from its origin URL.
_att_repo_from_checkout() {
    local _main _url _slug
    _main=$(_att_main_checkout "$1") || return 1
    _url=$(git -C "${_main}" remote get-url origin 2>/dev/null) || return 1
    _slug=$(printf '%s' "${_url%.git}" | sed -n 's#.*[:/]\([^/:]*/[^/:]*\)$#\1#p')
    [ -n "${_slug}" ] || return 1
    printf '%s\t%s\t%s' "${_slug}" "${_main}" "github.com"
}

# Classify one tab: echo `<kind>US<slug>US<number>` or rc 1 (not ours).
_att_classify() {
    local _names="$1" _label="$2" _cwd="$3" _n _p
    local IFS=','
    for _n in ${_names}; do
        _p=$(herdr_agent_parse_name "${_n}") && break
        _p=""
    done
    unset IFS
    # Agent released: the label (mt may carry the -STUCK rename).
    [ -n "${_p}" ] || _p=$(herdr_agent_parse_name "${_label%-STUCK}") || _p=""
    if [ -n "${_p}" ]; then
        printf '%s' "${_p//$'\t'/${_ATT_US}}"
        return 0
    fi
    # mv scratch cwd: the slug comes from the repo owning it (resolved later).
    case "${_cwd}" in
    */pr-post-merge-verify/pr-[0-9]*)
        _n="${_cwd##*/pr-}"
        case "${_n}" in *[!0-9]*) return 1 ;; esac
        printf 'mv%s%s%s' "${_ATT_US}" "${_ATT_US}" "${_n}"
        return 0
        ;;
    esac
    return 1
}

# Echo the worktree to remove for a closed candidate, or nothing.
_att_find_worktree() {
    local _kind="$1" _main="$2" _n="$3" _cwd="$4"
    if [ "${_kind}" = mv ]; then
        case "${_cwd}" in */pr-post-merge-verify/pr-"${_n}") [ -d "${_cwd}" ] && printf '%s' "${_cwd}" ;; esac
        return 0
    fi
    # iw: a wt/issue-<N>/* worktree the tab's cwd sits in (trailing / keeps 11 off 110).
    local _w _pw
    [ -n "${_cwd}" ] || return 0
    while IFS= read -r _w; do
        _pw=$(_att_phys "${_w}")
        case "${_cwd}" in "${_pw}" | "${_pw}"/*)
            printf '%s' "${_w}"
            return 0
            ;;
        esac
    done <<EOF
$(git -C "${_main}" worktree list --porcelain 2>/dev/null | awk -v p="refs/heads/wt/issue-${_n}/" '
        /^worktree / { wt = substr($0, 10) }
        /^branch / && index(substr($0, 8), p) == 1 { print wt }')
EOF
}

# Pre-checks + gwt remove for one closed candidate. rc 0 removed, 1 kept.
_att_remove_worktree() {
    local _kind="$1" _repo="$2" _main="$3" _host="$4" _n="$5" _cwd="$6" _where="$7" _wt _br _merged
    _wt=$(_att_find_worktree "${_kind}" "${_main}" "${_n}" "${_cwd}")
    if [ -z "${_wt}" ]; then
        ux_info "[SKIP] ${_where} no worktree"
        return 1
    fi
    if [ "${_ATT_FORCE}" != 1 ]; then
        if [ -n "$(git -C "${_wt}" status --porcelain 2>/dev/null)" ] || ! git -C "${_wt}" rev-parse --git-dir >/dev/null 2>&1; then
            ux_warning "[WARN] ${_where} worktree kept (not clean): ${_wt}"
            return 1
        fi
        # mv's PR is already known MERGED (F-3); iw needs pushed or merged.
        if [ "${_kind}" = iw ]; then
            _br=$(git -C "${_wt}" rev-parse --abbrev-ref HEAD 2>/dev/null)
            if ! git -C "${_wt}" rev-parse --verify -q '@{u}' >/dev/null 2>&1 ||
                [ "$(git -C "${_wt}" rev-list --count '@{u}..HEAD' 2>/dev/null)" != 0 ]; then
                _merged=$(GH_HOST="${_host}" gh pr list --repo "${_repo}" --head "${_br}" --state merged \
                    --json number -q length </dev/null 2>/dev/null) || _merged="?"
                case "${_merged}" in '' | '?' | *[!0-9]*)
                    ux_warning "[WARN] ${_where} worktree kept (merge state of ${_br} unknown: gh lookup failed): ${_wt}"
                    return 1
                    ;;
                0)
                    ux_warning "[WARN] ${_where} worktree kept (branch ${_br} neither pushed nor merged): ${_wt}"
                    return 1
                    ;;
                esac
            fi
        fi
    fi
    set -- "${_wt}"
    [ "${_ATT_FORCE}" != 1 ] || set -- "$@" --force
    if (
        set +u
        export DOTFILES_FORCE_INIT=1
        cd "${_main}" || exit 1
        # shellcheck source=/dev/null
        . "${SHELL_COMMON}/functions/git_worktree.sh" || exit 1
        gwt remove "$@"
    ) </dev/null; then
        return 0
    fi
    ux_warning "[WARN] ${_where} gwt remove failed: ${_wt}"
    return 1
}

# The herdr join: one `<tab_id>US<ws label>US<tab label>US<agent names>US<busy>US<cwd>`
# line per tab. busy=1 when any agent in the tab is working/blocked, `none`
# when the tab has no agent at all (#2322), else 0.
_att_tab_rows() {
    jq -rs '
        .[0].result.workspaces as $ws | .[1].result.tabs as $tabs
        | .[2].result.agents as $agents | ((.[3] // {}).result.panes // []) as $panes
        | if ([$ws, $tabs, $agents] | all(type == "array")) | not then error("no herdr list") else . end
        | $tabs[] | .tab_id as $t | .workspace_id as $w
        | [ $agents[] | select(.tab_id == $t) ] as $a
        | [ $t,
            ([ $ws[] | select(.workspace_id == $w) | (.label // "") ] | first // $w // ""),
            ((.label // "") | tostring),
            ([ $a[] | .name // empty ] | join(",")),
            (if ($a | length) == 0 then "none"
             elif any($a[]; .agent_status == "working" or .agent_status == "blocked") then "1" else "0" end),
            (([ $a[] | .cwd // empty ] + [ $panes[] | select(.tab_id == $t) | .cwd // empty ]) | first // "") ]
        | join("\u001f")'
}

avatar_tab_teardown_main() {
    local _yes=0 _wt=0 _repo_f="" _issue_f="" _want=""
    _ATT_FORCE=0
    while [ $# -gt 0 ]; do
        case "$1" in
        -h | --help | help)
            # shellcheck source=/dev/null
            DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/avatar_tab_teardown_help.sh"
            avatar_tab_teardown_help
            return 0
            ;;
        --yes | -y) _yes=1 ;;
        --worktree) _wt=1 ;;
        --force) _ATT_FORCE=1 ;;
        --repo | --issue)
            # A missing value must not silently widen the scope to every tab.
            if [ $# -lt 2 ] || [ -z "$2" ]; then
                ux_error "$1 needs a value (see --help)"
                return 2
            fi
            if [ "$1" = --repo ]; then _repo_f="$2"; else _issue_f="$2"; fi
            shift
            ;;
        *)
            ux_error "unknown option: $1 (see --help)"
            return 2
            ;;
        esac
        shift
    done
    case "${_issue_f}" in *[!0-9]*)
        ux_error "--issue needs a number: ${_issue_f}"
        return 2
        ;;
    esac
    if [ -n "${_repo_f}" ]; then
        _want=$(herdr_agent_repo_slug "${_repo_f}") || {
            ux_error "--repo is not a usable repo name: ${_repo_f}"
            return 2
        }
    fi

    # NF-1: no herdr, or a server that does not answer, is "nothing to tear down".
    if ! command -v herdr >/dev/null 2>&1; then
        ux_warning "herdr not installed — nothing to tear down"
        return 0
    fi
    local _wss _tabs _agents _panes _rows _self=""
    if ! _wss=$(herdr workspace list 2>/dev/null) || ! _tabs=$(herdr tab list 2>/dev/null) ||
        ! _agents=$(herdr_agent_list_json) || [ -z "${_wss}" ] || [ -z "${_tabs}" ]; then
        ux_warning "herdr server not responding — nothing to tear down"
        return 0
    fi
    _panes=$(herdr pane list 2>/dev/null) || _panes=""
    if ! _rows=$(printf '%s\n%s\n%s\n%s\n' "${_wss}" "${_tabs}" "${_agents}" "${_panes}" | _att_tab_rows 2>/dev/null); then
        ux_warning "herdr answered in an unexpected shape — nothing torn down"
        return 0
    fi
    # F-4: the calling pane's own tab.
    [ -z "${HERDR_PANE_ID-}" ] ||
        _self=$(herdr pane get "${HERDR_PANE_ID}" 2>/dev/null | jq -r '.result.pane.tab_id // empty' 2>/dev/null)
    # Fail closed: a set pane id we cannot resolve would let --yes close our own tab.
    if [ "${_yes}" = 1 ] && [ -n "${HERDR_PANE_ID-}" ] && [ -z "${_self}" ]; then
        ux_warning "cannot resolve the current tab (herdr pane get ${HERDR_PANE_ID}) — nothing torn down"
        return 1
    fi
    _att_load_watch_list

    local _tid _ws _label _names _busy _cwd _cls _kind _slug _num _row _rrepo _rpath _rhost _where _state _rc
    local _closable=0 _closed=0 _skipped=0 _removed=0 _failed=0
    while IFS="${_ATT_US}" read -r -u 3 _tid _ws _label _names _busy _cwd; do
        [ -n "${_tid}" ] || continue
        _cls=$(_att_classify "${_names}" "${_label}" "${_cwd}") || continue
        IFS="${_ATT_US}" read -r _kind _slug _num <<EOF
${_cls}
EOF
        _where="${_ws}/${_label}"
        # A physical cwd, so it compares with `pwd -P` and the normalized watch list.
        [ -z "${_cwd}" ] || _cwd=$(_att_phys "${_cwd}")

        # F-2: repo. mv found by cwd carries no slug: its main checkout names it.
        _row="" _rc=0
        if [ -z "${_slug}" ]; then
            _rpath=$(_att_main_checkout "${_cwd}") &&
                _row=$(printf '%s\n' "${_ATT_WATCH}" | awk -F '\t' -v p="${_rpath}" '$2 == p { print; exit }')
            [ -z "${_row}" ] || _slug=$(herdr_agent_repo_slug "${_row%%$'\t'*}")
        else
            _row=$(_att_repo_for_slug "${_slug}") || _rc=$?
            if [ -z "${_row}" ] && [ "${_kind}" = mt ] && [ -n "${_cwd}" ]; then
                _row=$(_att_repo_from_checkout "${_cwd}") || _row=""
                # The checkout must be the repo the agent name claims, else any
                # hand-made `mt-*` tab in some checkout would qualify.
                [ -z "${_row}" ] || [ "$(herdr_agent_repo_slug "${_row%%$'\t'*}")" = "${_slug}" ] || _row=""
            fi
        fi
        # Scope filters drop a row silently: it was not asked about.
        [ -z "${_want}" ] || [ "${_slug}" = "${_want}" ] || continue
        [ -z "${_issue_f}" ] || [ "${_num}" = "${_issue_f}" ] || continue

        if [ -n "${_self}" ] && [ "${_tid}" = "${_self}" ]; then
            ux_info "[SKIP] ${_where} current tab"
            _skipped=$((_skipped + 1))
            continue
        fi
        if [ -z "${_row}" ]; then
            if [ "${_rc}" -eq 3 ]; then
                ux_info "[SKIP] ${_where} ambiguous repo ${_slug} (several watched repos share it)"
            else
                ux_info "[SKIP] ${_where} unknown repo ${_slug:-?}"
            fi
            _skipped=$((_skipped + 1))
            continue
        fi
        IFS=$'\t' read -r _rrepo _rpath _rhost <<EOF
${_row}
EOF
        # F-3 (bypassed by --force).
        if [ "${_ATT_FORCE}" != 1 ]; then
            # The -STUCK rename is merge-train's "a human must look" signal:
            # closing it would erase the evidence, so only --force does.
            if [ "${_kind}" = mt ] && [ "${_label%-STUCK}" != "${_label}" ]; then
                ux_warning "[SKIP] ${_where} merge train STUCK — inspect it; --force closes it"
                _skipped=$((_skipped + 1))
                continue
            fi
            if [ "${_busy}" = 1 ]; then
                ux_info "[SKIP] ${_where} agent working/blocked"
                _skipped=$((_skipped + 1))
                continue
            fi
            # #2322: no agent may mean a human's shell, not a finished session.
            if [ "${_busy}" = none ]; then
                ux_info "[SKIP] ${_where} no agent (can't confirm finished)"
                _skipped=$((_skipped + 1))
                continue
            fi
            _state=""
            case "${_kind}" in
            iw) _state=$(GH_HOST="${_rhost}" gh issue view "${_num}" --repo "${_rrepo}" --json state -q .state </dev/null 2>/dev/null) || _state="?" ;;
            mv) _state=$(GH_HOST="${_rhost}" gh pr view "${_num}" --repo "${_rrepo}" --json state -q .state </dev/null 2>/dev/null) || _state="?" ;;
            esac
            if [ "${_state}" = "?" ] || { [ "${_kind}" != mt ] && [ -z "${_state}" ]; }; then
                ux_warning "[WARN] ${_where} state unknown (${_rrepo}#${_num}) — not closed"
                _skipped=$((_skipped + 1))
                continue
            fi
            if { [ "${_kind}" = iw ] && [ "${_state}" != CLOSED ]; } || { [ "${_kind}" = mv ] && [ "${_state}" != MERGED ]; }; then
                ux_info "[SKIP] ${_where} ${_rrepo}#${_num} is ${_state}"
                _skipped=$((_skipped + 1))
                continue
            fi
        fi

        _closable=$((_closable + 1))
        if [ "${_yes}" != 1 ]; then
            ux_info "[CLOSABLE] ${_where} ${_kind} ${_rrepo}${_num:+#${_num}} (dry-run)"
            continue
        fi
        if ! herdr tab close "${_tid}" </dev/null >/dev/null 2>&1; then
            ux_error "[FAIL] ${_where} herdr tab close ${_tid} failed"
            _failed=$((_failed + 1))
            continue
        fi
        ux_success "[CLOSED] ${_where} ${_kind} ${_rrepo}${_num:+#${_num}}"
        _closed=$((_closed + 1))
        # F-6: never mt — it runs in the repo's main checkout.
        if [ "${_wt}" = 1 ] && [ "${_kind}" != mt ] &&
            _att_remove_worktree "${_kind}" "${_rrepo}" "${_rpath}" "${_rhost}" "${_num}" "${_cwd}" "${_where}"; then
            _removed=$((_removed + 1))
        fi
    done 3<<EOF
${_rows}
EOF

    if [ "${_yes}" != 1 ]; then
        ux_info "closable ${_closable} / skipped ${_skipped} (dry-run, nothing closed)"
        if [ "${_closable}" -gt 0 ]; then
            ux_info "Next: avatar-tab-teardown --yes [--worktree]"
        else
            ux_info "Next: nothing to close"
        fi
        return 0
    fi
    ux_info "closed ${_closed} / skipped ${_skipped} / failed ${_failed} / worktrees removed ${_removed}"
    if [ "${_failed}" -gt 0 ]; then
        ux_info "Next: re-run avatar-tab-teardown --yes after checking the herdr server"
        return 1
    fi
    ux_info "Next: avatar-tab-teardown (dry-run) to confirm nothing is left"
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    avatar_tab_teardown_main "$@"
fi
