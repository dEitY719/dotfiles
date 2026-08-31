#!/usr/bin/env bats
# tests/bats/functions/herdr_agent_lookup.bats
# Coverage for shell-common/functions/herdr_agent_lookup.sh (issue #1569).
#
# "Is a herdr agent sitting on this worktree?" was asked in four places with
# four hand-copied answers, and they had already drifted into three different
# predicates: the newest copy (gh:pr-merge's idle-tab hint) matched `.cwd` by
# plain string equality, so it missed an agent that had `cd`-ed inside its
# worktree and a worktree reached through a symlink, while the other three
# matched `.cwd` OR `.foreground_cwd` on a path boundary against the physical
# path. This suite pins the one predicate all four now share.
#
# L1-L4   herdr_agent_physical_path — symlink resolution and the fallback.
# L5-L9   herdr_agent_path_under    — the boundary, and the empty-base guard.
# L10-L17 herdr_agent_match_for_cwd / herdr_agent_tab_for_cwd — the dual-field
#         boundary match and the 3-way rc split (0 found / 1 herdr unreachable
#         / 3 herdr answered but nothing matched).
# L18-L21 the [status-filter] argument, including `first`-then-filter.
# L26     the loader reaches this file.

load '../test_helper'

setup() {
    setup_isolated_home
}

teardown() {
    teardown_isolated_home
}

# Run <shell code> against the helper alone, with a `herdr` stand-in bound to
# $AGENT_JSON / $AGENT_RC. Same rationale as herdr_agent_name.bats' run_han:
# `run_in_bash` would source the whole loader per test to reach one file.
#
# The stand-in is a shell function, which is exactly how the three fixture
# mirrors drive this helper — that seam only exists because the file invokes
# `herdr` by name rather than through a resolved path.
run_hal() {
    run bash --noprofile --norc -c "
        . '${_BATS_REAL_DOTFILES_ROOT}/shell-common/functions/herdr_agent_lookup.sh'
        herdr() {
            printf 'herdr %s\n' \"\$*\" >>\"\${HERDR_LOG:-/dev/null}\"
            [ \"\$1\" = agent ] && [ \"\$2\" = list ] || return 1
            [ \"\${AGENT_RC:-0}\" -eq 0 ] || return \"\$AGENT_RC\"
            printf '%s' \"\${AGENT_JSON-}\"
        }
        $1
    "
}

# One agent record from `cwd|foreground_cwd|tab_id|status|workspace_id`.
_agent() {
    local cwd fg tab st ws
    IFS='|' read -r cwd fg tab st ws <<<"$1"
    printf '{"cwd":"%s","foreground_cwd":"%s","tab_id":"%s","agent_status":"%s","workspace_id":"%s"}' \
        "$cwd" "$fg" "$tab" "$st" "$ws"
}

_agents_json() {
    local spec sep="" out=""
    for spec in "$@"; do
        out="${out}${sep}$(_agent "$spec")"
        sep=","
    done
    printf '{"result":{"agents":[%s]}}' "$out"
}

WT="/w/wt-issue-1569"

# ---------------------------------------------------------------------------
# L1-L4: herdr_agent_physical_path
# ---------------------------------------------------------------------------

@test "L1: a symlinked path resolves to its physical target" {
    local real="${TEST_TEMP_HOME}/real/wt" link="${TEST_TEMP_HOME}/link"
    mkdir -p "$real"
    ln -sfn "$real" "$link"
    run_hal "herdr_agent_physical_path '$link'"
    assert_success
    assert_output "$(cd -P "$real" && pwd -P)"
}

@test "L2: a path that cannot be entered falls back to the literal string" {
    # The fallback is the load-bearing half: degrading to an empty string would
    # make the boundary match every agent instead of none.
    run_hal "herdr_agent_physical_path '/no/such/path-1569'"
    assert_success
    assert_output "/no/such/path-1569"
}

@test "L3: an existing directory answers itself" {
    run_hal "herdr_agent_physical_path '${TEST_TEMP_HOME}'"
    assert_success
    assert_output "$(cd -P "$TEST_TEMP_HOME" && pwd -P)"
}

@test "L4: both branches end in exactly one trailing newline" {
    # `pwd -P` emits one; the fallback must match it, or a caller comparing
    # two paths without `$( )` would see them differ.
    run_hal "herdr_agent_physical_path '/no/such/path-1569' | od -c | tail -2"
    assert_success
    assert_output --partial '\n'
}

# ---------------------------------------------------------------------------
# L5-L9: herdr_agent_path_under — the boundary predicate
# ---------------------------------------------------------------------------

@test "L5: the path itself is under itself" {
    run_hal "herdr_agent_path_under '$WT' '$WT' && echo yes"
    assert_success
    assert_output "yes"
}

@test "L6: a subdirectory is under the base" {
    run_hal "herdr_agent_path_under '$WT/docs/.ssot' '$WT' && echo yes"
    assert_success
    assert_output "yes"
}

@test "L7: a sibling sharing the prefix is NOT under the base" {
    # `/work/repo-1` must never swallow `/work/repo-11` — this is the whole
    # reason the predicate appends a slash instead of matching bare.
    run_hal "herdr_agent_path_under '${WT}0' '$WT' || echo no"
    assert_success
    assert_output "no"
}

@test "L8: an empty base matches nothing, not everything" {
    run_hal "herdr_agent_path_under '$WT' '' || echo no"
    assert_success
    assert_output "no"
}

@test "L9: glob characters in the base are matched literally" {
    run_hal "herdr_agent_path_under '/w/abc' '/w/a?c' || echo no"
    assert_success
    assert_output "no"
}

# ---------------------------------------------------------------------------
# L10-L17: the single-path lookup and its three return codes
# ---------------------------------------------------------------------------

@test "L10: an agent whose cwd is the path is matched, rc 0" {
    run_hal "AGENT_JSON='$(_agents_json "${WT}|${WT}|tab-7|idle|ws-1")'
             herdr_agent_tab_for_cwd '$WT'; echo \" rc=\$?\""
    assert_success
    assert_output "tab-7 rc=0"
}

@test "L11: foreground_cwd alone is enough to match" {
    # The pane was opened on the main checkout and its shell walked into the
    # worktree. Matching only `.cwd` loses exactly this session.
    run_hal "AGENT_JSON='$(_agents_json "/w/main|${WT}/tests|tab-7|idle|ws-1")'
             herdr_agent_tab_for_cwd '$WT'"
    assert_success
    assert_output "tab-7"
}

@test "L12: a pane opened inside the worktree still matches on the boundary" {
    run_hal "AGENT_JSON='$(_agents_json "${WT}/claude/skills|${WT}/claude/skills|tab-7|idle|ws-1")'
             herdr_agent_tab_for_cwd '$WT'"
    assert_success
    assert_output "tab-7"
}

@test "L13: a sibling checkout sharing the prefix is not matched, rc 3" {
    run_hal "AGENT_JSON='$(_agents_json "${WT}0|${WT}0|tab-sib|idle|ws-1")'
             herdr_agent_tab_for_cwd '$WT'; echo \"rc=\$?\""
    assert_success
    assert_output "rc=3"
}

@test "L14: herdr answering an empty agent set is rc 3, not rc 1" {
    run_hal "AGENT_JSON='{\"result\":{\"agents\":[]}}'
             herdr_agent_tab_for_cwd '$WT'; echo \"rc=\$?\""
    assert_success
    assert_output "rc=3"
}

@test "L15: a failed herdr call is rc 1 — unknown, never 'nothing running'" {
    # The one mistake this signal cannot afford: rc 1 read as rc 3 lifts
    # issue-watcher's concurrency cap exactly when herdr is unhealthy.
    run_hal "AGENT_RC=7 AGENT_JSON='$(_agents_json "${WT}|${WT}|tab-7|idle|ws-1")'
             herdr_agent_tab_for_cwd '$WT'; echo \"rc=\$?\""
    assert_success
    assert_output "rc=1"
}

@test "L16: an empty answer and non-JSON garbage are both rc 1" {
    run_hal "AGENT_JSON='' herdr_agent_tab_for_cwd '$WT'; echo \"rc=\$?\""
    assert_success
    assert_output "rc=1"

    run_hal "AGENT_JSON='not json at all' herdr_agent_tab_for_cwd '$WT'; echo \"rc=\$?\""
    assert_success
    assert_output "rc=1"
}

@test "L17: an empty path is rc 3 without ever asking herdr" {
    local log="${TEST_TEMP_HOME}/herdr.log"
    : >"$log"
    run_hal "HERDR_LOG='$log' AGENT_JSON='$(_agents_json "${WT}|${WT}|tab-7|idle|ws-1")'
             herdr_agent_tab_for_cwd ''; echo \"rc=\$?\""
    assert_success
    assert_output "rc=3"
    run cat "$log"
    assert_output ""
}

@test "L17b: the match form answers tab_id, agent_status and workspace_id" {
    run_hal "AGENT_JSON='$(_agents_json "${WT}|${WT}|tab-7|idle|ws-1")'
             herdr_agent_match_for_cwd '$WT' | cat -A"
    assert_success
    # Tab-separated, and NO trailing newline — the callers read it through
    # `$( )` and split on the tabs.
    assert_output 'tab-7^Iidle^Iws-1'
}

@test "L17c: two agents on one worktree — the first wins, silently" {
    run_hal "AGENT_JSON='$(_agents_json "${WT}|${WT}|tab-first|idle|ws-1" "${WT}|${WT}|tab-second|idle|ws-2")'
             herdr_agent_tab_for_cwd '$WT'"
    assert_success
    assert_output "tab-first"
}

# ---------------------------------------------------------------------------
# L18-L21: the optional status filter
# ---------------------------------------------------------------------------

@test "L18: a matching status filter passes the agent through" {
    run_hal "AGENT_JSON='$(_agents_json "${WT}|${WT}|tab-7|idle|ws-1")'
             herdr_agent_tab_for_cwd '$WT' idle"
    assert_success
    assert_output "tab-7"
}

@test "L19: a non-matching status is rc 3 — a working session is never named" {
    run_hal "AGENT_JSON='$(_agents_json "${WT}|${WT}|tab-7|working|ws-1")'
             herdr_agent_tab_for_cwd '$WT' idle; echo \"rc=\$?\""
    assert_success
    assert_output "rc=3"
}

@test "L20: an absent agent_status never satisfies a filter" {
    run_hal "AGENT_JSON='{\"result\":{\"agents\":[{\"cwd\":\"${WT}\",\"tab_id\":\"tab-7\"}]}}'
             herdr_agent_tab_for_cwd '$WT' idle; echo \"rc=\$?\""
    assert_success
    assert_output "rc=3"
}

@test "L21: the filter judges the FIRST match, it does not choose among them" {
    # Two agents on one worktree is abnormal, and every call site's documented
    # rule is take-the-first. Filtering before picking would turn that into
    # "find me an idle one" and close a tab whose sibling pane still works.
    run_hal "AGENT_JSON='$(_agents_json "${WT}|${WT}|tab-first|working|ws-1" "${WT}|${WT}|tab-second|idle|ws-2")'
             herdr_agent_tab_for_cwd '$WT' idle; echo \"rc=\$?\""
    assert_success
    assert_output "rc=3"
}

# ---------------------------------------------------------------------------
# L26: the loader reaches this file
# ---------------------------------------------------------------------------

@test "L26: bash/main.bash auto-sources the helper" {
    run_in_bash 'command -v herdr_agent_tab_for_cwd >/dev/null && command -v herdr_agent_path_under >/dev/null && echo sourced'
    assert_success
    assert_output --partial "sourced"
}
