#!/usr/bin/env bats
# tests/bats/tools/avatar_tab_teardown.bats
# avatar_tab_teardown.sh (#2320): close finished iw/mt/mv herdr tabs and,
# opt-in, their worktrees. herdr and gh are fake shims (no live server, no
# GitHub call); git is real, so `gwt remove` runs against real worktrees.
#
# Fixture: one workspace `dotfiles`; each row of ${FIX}/tabs.tsv is
#   <tab_id> <label> <agent name | - (no agent) | ~ (unnamed agent)> <status> <cwd>

load '../test_helper'

SCRIPT="${DOTFILES_ROOT}/shell-common/tools/custom/avatar_tab_teardown.sh"

setup() {
    setup_isolated_home
    unset HERDR_PANE_ID HERDR_DOWN
    FIX="${HOME}/fix"
    BIN="${HOME}/bin"
    mkdir -p "${FIX}" "${BIN}"
    : >"${FIX}/tabs.tsv"
    export FIX
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

    cat >"${BIN}/herdr" <<'EOF'
#!/bin/sh
[ -z "${HERDR_DOWN-}" ] || exit 1
rows() { jq -Rn "[inputs | split(\"\t\") | $1]" <"${FIX}/tabs.tsv"; }
case "$1 $2" in
"workspace list") printf '%s\n' '{"result":{"workspaces":[{"workspace_id":"w1","label":"dotfiles"}]}}' ;;
"tab list") printf '{"result":{"tabs":%s}}\n' "$(rows '{tab_id: .[0], workspace_id: "w1", label: .[1]}')" ;;
"agent list") printf '{"result":{"agents":%s}}\n' "$(rows 'select(.[2] != "-") | {tab_id: .[0], agent_status: .[3], cwd: .[4]} + (if .[2] == "~" then {} else {name: .[2]} end)')" ;;
"pane list") printf '{"result":{"panes":%s}}\n' "$(rows '{tab_id: .[0], cwd: .[4]}')" ;;
"pane get") printf '{"result":{"pane":{"tab_id":"%s"}}}\n' "${SELF_TAB-}" ;;
"tab close") printf '%s\n' "$3" >>"${FIX}/closed.log" ;;
*) exit 1 ;;
esac
EOF
    # gh: `issue view N` / `pr view N` answer ${FIX}/issue-N / pr-N (missing:
    # failure); `pr list` answers ${FIX}/prlist (default 0 merged PRs).
    cat >"${BIN}/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
"issue view") cat "${FIX}/issue-$3" 2>/dev/null || exit 1 ;;
"pr view") cat "${FIX}/pr-$3" 2>/dev/null || exit 1 ;;
"pr list") cat "${FIX}/prlist" 2>/dev/null || printf '0\n' ;;
*) exit 1 ;;
esac
EOF
    chmod +x "${BIN}/herdr" "${BIN}/gh"
    export PATH="${BIN}:${PATH}"

    # A real main checkout with an origin, watched as acme/dotfiles.
    MAIN="${HOME}/src/dotfiles"
    git init -q --bare "${HOME}/origin.git"
    git clone -q "${HOME}/origin.git" "${MAIN}" 2>/dev/null
    git -C "${MAIN}" commit -q --allow-empty -m init
    git -C "${MAIN}" push -q origin HEAD 2>/dev/null
    export IW_WATCHED_REPOS="${HOME}/watched.json"
    printf '[{"repo":"acme/dotfiles","path":"%s","host":"github.com"}]\n' "${MAIN}" >"${IW_WATCHED_REPOS}"
}

teardown() {
    teardown_isolated_home
}

_tab() { printf '%s\t%s\t%s\t%s\t%s\n' "$@" >>"${FIX}/tabs.tsv"; }
_closed() { cat "${FIX}/closed.log" 2>/dev/null; }

# _iw_worktree <N> — a wt/issue-<N>/1 worktree, echo its path.
_iw_worktree() {
    local wt="${HOME}/src/dotfiles-issue-$1-1"
    git -C "${MAIN}" worktree add -q -b "wt/issue-$1/1" "${wt}" 2>/dev/null
    printf '%s' "${wt}"
}

@test "avatar_tab_teardown: no args is a dry run that closes nothing" {
    printf 'CLOSED\n' >"${FIX}/issue-11"
    _tab t1 iw-dotfiles-issue-11 iw-dotfiles-issue-11 idle "${MAIN}"
    run bash "$SCRIPT"
    assert_success
    assert_output --partial "[CLOSABLE] dotfiles/iw-dotfiles-issue-11 iw acme/dotfiles#11 (dry-run)"
    assert_output --partial "Next: avatar-tab-teardown --yes"
    [ -z "$(_closed)" ]
}

@test "avatar_tab_teardown: an iw tab whose number is a MERGED PR is closable, an open one is not (#2328)" {
    # `gh issue view <PR number>` answers the PR's state: MERGED or OPEN.
    printf 'MERGED\n' >"${FIX}/issue-85"
    printf 'OPEN\n' >"${FIX}/issue-86"
    _tab t1 iw-dotfiles-issue-85 iw-dotfiles-issue-85 idle "${MAIN}"
    _tab t2 iw-dotfiles-issue-86 iw-dotfiles-issue-86 idle "${MAIN}"
    run bash "$SCRIPT"
    assert_success
    assert_output --partial "[CLOSABLE] dotfiles/iw-dotfiles-issue-85 iw acme/dotfiles#85 (dry-run)"
    assert_output --partial "[SKIP] dotfiles/iw-dotfiles-issue-86 acme/dotfiles#86 is OPEN"
    [ -z "$(_closed)" ]
}

@test "avatar_tab_teardown: tabs without an ownership signal are never candidates" {
    _tab t1 issue-12 - - "${MAIN}"
    _tab t2 pr-12 ~ idle "${MAIN}"
    _tab t3 null - - "${MAIN}"
    _tab t4 1 - - "${MAIN}"
    run bash "$SCRIPT" --yes --force
    assert_success
    refute_output --partial "issue-12"
    refute_output --partial "pr-12"
    assert_output --partial "closed 0 / skipped 0"
    [ -z "$(_closed)" ]
}

@test "avatar_tab_teardown: mv is found by agent name or scratch cwd despite its pr-<N> label" {
    printf 'MERGED\n' >"${FIX}/pr-7"
    printf 'MERGED\n' >"${FIX}/pr-8"
    scratch="${MAIN}/.git/pr-post-merge-verify/pr-8"
    git -C "${MAIN}" worktree add -q --detach "${scratch}" 2>/dev/null
    _tab t1 pr-7 mv-dotfiles-pr-7 done "${MAIN}"
    _tab t2 pr-8 ~ idle "${scratch}"
    run bash "$SCRIPT" --yes --worktree
    assert_success
    assert_output --partial "[CLOSED] dotfiles/pr-7 mv acme/dotfiles#7"
    assert_output --partial "[CLOSED] dotfiles/pr-8 mv acme/dotfiles#8"
    [ "$(_closed)" = "t1
t2" ]
    [ ! -d "${scratch}" ]
}

@test "avatar_tab_teardown: an idle mt tab closes and --worktree leaves the main checkout alone" {
    _tab t2 mt-dotfiles mt-dotfiles unknown "${MAIN}"
    run bash "$SCRIPT" --yes --worktree
    assert_success
    [ "$(_closed)" = "t2" ]
    [ -d "${MAIN}/.git" ]
    assert_output --partial "worktrees removed 0"
}

@test "avatar_tab_teardown: a -STUCK mt tab is kept for a human unless --force" {
    _tab t1 mt-dotfiles-STUCK - - "${MAIN}"
    run bash "$SCRIPT" --yes
    assert_success
    assert_output --partial "[SKIP] dotfiles/mt-dotfiles-STUCK merge train STUCK"
    [ -z "$(_closed)" ]
    run bash "$SCRIPT" --yes --force
    assert_success
    [ "$(_closed)" = "t1" ]
}

@test "avatar_tab_teardown: ambiguous slug, mismatched mt checkout and an unmatched --repo close nothing" {
    printf '[{"repo":"acme/dotfiles","path":"%s"},{"repo":"other/dotfiles","path":"/srv/x"}]\n' "${MAIN}" >"${IW_WATCHED_REPOS}"
    printf 'CLOSED\n' >"${FIX}/issue-11"
    _tab t1 iw-dotfiles-issue-11 iw-dotfiles-issue-11 idle "${MAIN}"
    # MAIN's origin is ${HOME}/origin.git -> slug "origin", not "notes".
    _tab t2 mt-notes mt-notes idle "${MAIN}"
    run bash "$SCRIPT" --yes
    assert_success
    assert_output --partial "[SKIP] dotfiles/iw-dotfiles-issue-11 ambiguous repo dotfiles"
    assert_output --partial "[SKIP] dotfiles/mt-notes unknown repo notes"
    run bash "$SCRIPT" --yes --force --repo acme/elsewhere
    assert_success
    assert_output --partial "closed 0 / skipped 0"
    [ -z "$(_closed)" ]
}

@test "avatar_tab_teardown: a working or blocked mt tab stays open" {
    _tab t1 mt-dotfiles mt-dotfiles working "${MAIN}"
    _tab t2 mt-other mt-other blocked "${MAIN}"
    run bash "$SCRIPT" --yes
    assert_success
    assert_output --partial "[SKIP] dotfiles/mt-dotfiles agent working/blocked"
    [ -z "$(_closed)" ]
}

@test "avatar_tab_teardown: open issue or busy agent stays open unless --force" {
    printf 'OPEN\n' >"${FIX}/issue-11"
    printf 'CLOSED\n' >"${FIX}/issue-12"
    _tab t1 iw-dotfiles-issue-11 iw-dotfiles-issue-11 idle "${MAIN}"
    _tab t2 iw-dotfiles-issue-12 iw-dotfiles-issue-12 working "${MAIN}"
    run bash "$SCRIPT" --yes
    assert_success
    assert_output --partial "[SKIP] dotfiles/iw-dotfiles-issue-11 acme/dotfiles#11 is OPEN"
    assert_output --partial "[SKIP] dotfiles/iw-dotfiles-issue-12 agent working/blocked"
    [ -z "$(_closed)" ]
    run bash "$SCRIPT" --yes --force
    assert_success
    [ "$(_closed)" = "t1
t2" ]
}

@test "avatar_tab_teardown: a tab with no agent is skipped unless --force (#2322)" {
    printf 'CLOSED\n' >"${FIX}/issue-11"
    printf 'MERGED\n' >"${FIX}/pr-8"
    scratch="${MAIN}/.git/pr-post-merge-verify/pr-8"
    git -C "${MAIN}" worktree add -q --detach "${scratch}" 2>/dev/null
    _tab t1 iw-dotfiles-issue-11 - - "${MAIN}"
    _tab t2 mt-dotfiles - - "${MAIN}"
    # mv found only by its scratch cwd (no agent name to read).
    _tab t3 pr-8 - - "${scratch}"
    run bash "$SCRIPT"
    assert_success
    assert_output --partial "[SKIP] dotfiles/iw-dotfiles-issue-11 no agent (can't confirm finished)"
    assert_output --partial "[SKIP] dotfiles/mt-dotfiles no agent (can't confirm finished)"
    assert_output --partial "[SKIP] dotfiles/pr-8 no agent (can't confirm finished)"
    refute_output --partial "[CLOSABLE]"
    run bash "$SCRIPT" --yes
    assert_success
    [ -z "$(_closed)" ]
    run bash "$SCRIPT" --force
    assert_success
    assert_output --partial "[CLOSABLE] dotfiles/iw-dotfiles-issue-11 iw acme/dotfiles#11 (dry-run)"
    assert_output --partial "[CLOSABLE] dotfiles/mt-dotfiles mt acme/dotfiles (dry-run)"
    assert_output --partial "[CLOSABLE] dotfiles/pr-8 mv acme/dotfiles#8 (dry-run)"
    [ -z "$(_closed)" ]
    run bash "$SCRIPT" --yes --force
    assert_success
    [ "$(_closed)" = "t1
t2
t3" ]
}

@test "avatar_tab_teardown: the calling pane's tab survives --force --yes" {
    _tab t1 iw-dotfiles-issue-11 iw-dotfiles-issue-11 working "${MAIN}"
    _tab t2 iw-dotfiles-issue-12 iw-dotfiles-issue-12 idle "${MAIN}"
    printf 'CLOSED\n' >"${FIX}/issue-12"
    HERDR_PANE_ID=p1 SELF_TAB=t1 run bash "$SCRIPT" --yes --force
    assert_success
    assert_output --partial "[SKIP] dotfiles/iw-dotfiles-issue-11 current tab"
    [ "$(_closed)" = "t2" ]
}

@test "avatar_tab_teardown: --yes closes only the closable tabs, scoped by --repo/--issue" {
    printf 'CLOSED\n' >"${FIX}/issue-11"
    printf 'CLOSED\n' >"${FIX}/issue-12"
    printf 'OPEN\n' >"${FIX}/issue-13"
    _tab t1 iw-dotfiles-issue-11 iw-dotfiles-issue-11 idle "${MAIN}"
    _tab t2 iw-dotfiles-issue-12 iw-dotfiles-issue-12 done "${MAIN}"
    _tab t3 iw-dotfiles-issue-13 iw-dotfiles-issue-13 idle "${MAIN}"
    run bash "$SCRIPT" --yes --repo acme/dotfiles --issue 12
    assert_success
    [ "$(_closed)" = "t2" ]
    run bash "$SCRIPT" --yes
    assert_success
    [ "$(_closed)" = "t2
t1
t2" ]
}

@test "avatar_tab_teardown: --worktree keeps dirty or unpushed worktrees, removes a clean pushed one" {
    for n in 11 12 13; do printf 'CLOSED\n' >"${FIX}/issue-${n}"; done
    dirty=$(_iw_worktree 11)
    : >"${dirty}/scratch.txt"
    unpushed=$(_iw_worktree 12)
    git -C "${unpushed}" commit -q --allow-empty -m wip
    pushed=$(_iw_worktree 13)
    git -C "${pushed}" push -q -u origin wt/issue-13/1 2>/dev/null
    _tab t1 iw-dotfiles-issue-11 iw-dotfiles-issue-11 idle "${dirty}"
    _tab t2 iw-dotfiles-issue-12 iw-dotfiles-issue-12 idle "${unpushed}"
    _tab t3 iw-dotfiles-issue-13 iw-dotfiles-issue-13 idle "${pushed}"
    run bash "$SCRIPT" --yes --worktree
    assert_success
    assert_output --partial "worktree kept (not clean)"
    assert_output --partial "worktree kept (branch wt/issue-12/1 neither pushed nor merged)"
    assert_output --partial "worktrees removed 1"
    [ -d "${dirty}" ] && [ -d "${unpushed}" ] && [ ! -d "${pushed}" ]
    # A merged PR is enough for the unpushed branch.
    printf '1\n' >"${FIX}/prlist"
    : >"${FIX}/tabs.tsv"
    _tab t2 iw-dotfiles-issue-12 iw-dotfiles-issue-12 idle "${unpushed}"
    run bash "$SCRIPT" --yes --worktree
    assert_success
    [ ! -d "${unpushed}" ]
}

@test "avatar_tab_teardown: --worktree keeps an unpushed worktree when the merge lookup fails, and matches a symlinked watch path" {
    printf 'CLOSED\n' >"${FIX}/issue-14"
    ln -s "${MAIN}" "${HOME}/link"
    printf '[{"repo":"acme/dotfiles","path":"%s/"}]\n' "${HOME}/link" >"${IW_WATCHED_REPOS}"
    wt=$(_iw_worktree 14)
    git -C "${wt}" commit -q --allow-empty -m wip
    printf '#!/bin/sh\ncase "$1 $2" in "issue view") cat "${FIX}/issue-$3" ;; *) exit 1 ;; esac\n' >"${BIN}/gh"
    _tab t1 iw-dotfiles-issue-14 iw-dotfiles-issue-14 idle "${wt}"
    run bash "$SCRIPT" --yes --worktree
    assert_success
    assert_output --partial "[CLOSED] dotfiles/iw-dotfiles-issue-14"
    assert_output --partial "merge state of wt/issue-14/1 unknown"
    [ -d "${wt}" ]
}

@test "avatar_tab_teardown: missing herdr or an unresponsive server exits 0 with a warning" {
    noh="${HOME}/noherdr"
    mkdir -p "${noh}"
    run env PATH="${noh}:/usr/bin:/bin" bash "$SCRIPT" --yes
    assert_success
    assert_output --partial "herdr not installed"
    HERDR_DOWN=1 run bash "$SCRIPT" --yes
    assert_success
    assert_output --partial "herdr server not responding"
}

@test "avatar_tab_teardown: an unwatched repo slug is skipped, a failed gh read is a WARN" {
    _tab t1 iw-nowhere-issue-5 iw-nowhere-issue-5 idle /tmp
    _tab t2 iw-dotfiles-issue-6 iw-dotfiles-issue-6 idle "${MAIN}"
    run bash "$SCRIPT" --yes
    assert_success
    assert_output --partial "[SKIP] dotfiles/iw-nowhere-issue-5 unknown repo nowhere"
    assert_output --partial "[WARN] dotfiles/iw-dotfiles-issue-6 state unknown"
    [ -z "$(_closed)" ]
}

@test "avatar_tab_teardown: a failed tab close is a FAIL and the rest still runs" {
    printf 'CLOSED\n' >"${FIX}/issue-11"
    printf 'CLOSED\n' >"${FIX}/issue-12"
    _tab t1 iw-dotfiles-issue-11 iw-dotfiles-issue-11 idle "${MAIN}"
    _tab t2 iw-dotfiles-issue-12 iw-dotfiles-issue-12 idle "${MAIN}"
    sed -i 's|^"tab close").*|"tab close") [ "$3" != t1 ] \|\| exit 1; printf "%s\\n" "$3" >>"${FIX}/closed.log" ;;|' "${BIN}/herdr"
    run bash "$SCRIPT" --yes
    assert_failure
    assert_output --partial "[FAIL] dotfiles/iw-dotfiles-issue-11 herdr tab close t1 failed"
    [ "$(_closed)" = "t2" ]
}

@test "avatar_tab_teardown: help is registered and bad options are refused" {
    run bash "$SCRIPT" --help
    assert_success
    assert_output --partial "Usage: avatar-tab-teardown"
    run bash "$SCRIPT" --issue abc
    [ "$status" -eq 2 ]
    run_in_bash 'avatar_tab_teardown_help rules >/dev/null && echo ok'
    assert_output --partial "ok"
}
