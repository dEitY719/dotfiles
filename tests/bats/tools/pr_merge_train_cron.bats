#!/usr/bin/env bats
# tests/bats/tools/pr_merge_train_cron.bats
# Tests for pr_merge_train_cron.sh — the merge-train cron dispatcher (#1470).
#
# The dispatcher is deliberately thin: it answers three questions and then
# hands the whole train over to a claude session (D-8). So this suite covers
# exactly those three responsibilities and nothing more —
#
#   NF-1  a train already running (this tick's lock, or a live train agent
#         left by a previous tick) must not earn a second train
#   F-1/F-8/D-7  are there PRs worth waking a session for at all
#   D-8   the herdr workspace -> tab -> agent -> prompt launch
#
# The train's own behaviour (the D-1 routing table, the D-2 ordering, the
# per-PR attempt cap, the approval gate, the report format) is skill-prompt
# text, not shell, and is deliberately NOT asserted here — a shell test of it
# would only be testing a fixture of the prompt.
#
# Two PATH stubs stand in for the outside world and log every invocation to
# ${_LOG} so the tests can assert on *which* calls were made:
#
#   gh     `pr list` only — canned and steerable per test. Every other
#          subcommand is logged and refused: the dispatcher never writes to
#          GitHub, and this is what makes that a test rather than a claim.
#   herdr  workspace/tab/agent, with canned JSON matching the shapes
#          issue_watcher_cron.bats measured on a live herdr server.

load '../test_helper'

SCRIPT="${DOTFILES_ROOT}/shell-common/tools/custom/pr_merge_train_cron.sh"

setup() {
    setup_isolated_home
    _WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pr-merge-train-test.XXXXXX")"
    _BIN_DIR="${_WORK_DIR}/bin"
    _STATE_HOME="${_WORK_DIR}/state"
    _STATE_DIR="${_STATE_HOME}/pr-merge-train"
    _LOCK_FILE="${_STATE_DIR}/.lock"
    _LOG="${_WORK_DIR}/calls.log"
    _REPO_DIR="${_WORK_DIR}/dotfiles"
    _LOCK_HOLDER_PID=""
    mkdir -p "${_BIN_DIR}"
    : >"${_LOG}"

    # CLAUDE_CONFIG_DIR account routing (#1393): the tick resolves the claude
    # account dir before it opens the pane, so the default account has to
    # exist inside the isolated $HOME. Pinned rather than inherited so the
    # developer's own shell env cannot steer the tests.
    export CLAUDE_ENABLED_ACCOUNTS="personal"
    unset CLAUDE_DEFAULT_ACCOUNT
    _make_account "${HOME}/.claude-personal"

    _make_repo
    # One target PR, comfortably outside the quiet period, is the default —
    # every launch test starts from "there is work to do".
    _set_prs "[$(_pr_json 11 30)]"
    _install_stubs
}

teardown() {
    if [ -n "${_LOCK_HOLDER_PID}" ]; then
        kill "${_LOCK_HOLDER_PID}" 2>/dev/null || true
        wait "${_LOCK_HOLDER_PID}" 2>/dev/null || true
    fi
    rm -rf "${_WORK_DIR}"
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# A real git repo with a real `origin`. The dispatcher resolves owner/repo and
# the host from that remote URL (the #1403 binding), so mocking `git remote`
# away would test the mock rather than the resolution.
_make_repo() {
    mkdir -p "${_REPO_DIR}"
    git -C "${_REPO_DIR}" init -q
    git -C "${_REPO_DIR}" config user.email "test@example.com"
    git -C "${_REPO_DIR}" config user.name "test"
    git -C "${_REPO_DIR}" remote add origin "https://github.com/acme/dotfiles.git"
    printf 'seed\n' >"${_REPO_DIR}/README.md"
    git -C "${_REPO_DIR}" add -A
    git -C "${_REPO_DIR}" commit -qm "seed"
}

# `_epoch_to_iso` is shared via test_helper.bash (`load '../test_helper'`
# above already pulls it in) — every suite that builds `gh pr list` fixtures
# uses the one GNU/BSD/python3 cascade rather than its own copy.

# One `gh pr list --json` element: PR <1>, last updated <2> minutes ago,
# optionally a draft (<3>, default `false`) — a draft is never mergeable, so
# never a reason to wake a session.
_pr_json() {
    local _stamp
    _stamp=$(_epoch_to_iso "$(($(date +%s) - $2 * 60))") || fail "cannot format a timestamp on this platform"
    printf '{"number":%s,"updatedAt":"%s","isDraft":%s}' "$1" "${_stamp}" "${3:-false}"
}

# A `gh pr list --json` element whose `updatedAt` cannot be read — the raw JSON
# value <2> is spliced in verbatim (`null`, a quoted garbage string, …).
_pr_json_raw_stamp() {
    printf '{"number":%s,"updatedAt":%s,"isDraft":false}' "$1" "$2"
}

# The array `gh pr list` answers with.
_set_prs() {
    printf '%s\n' "$1" >"${_WORK_DIR}/prs.json"
}

# `_make_account` — a logged-in claude account directory. Lives in
# ../test_helper.bash; issue_watcher_cron.bats fixtures the same rule.

# ---------------------------------------------------------------------------
# Stubs
# ---------------------------------------------------------------------------

# gh: `pr list` is the only call the dispatcher makes. Anything else is logged
# and fails — the dispatcher is read-only on GitHub by contract.
#
#   GH_PR_LIST_FAIL=1   `pr list` errors (the "never merge without knowing
#                       state" path)
_install_gh_stub() {
    cat >"${_BIN_DIR}/gh" <<'EOF'
#!/bin/sh
printf 'gh %s\n' "$*" >>"${CALL_LOG}"

case "$1 $2" in
"pr list")
    [ "${GH_PR_LIST_FAIL:-0}" = "1" ] && exit 1
    cat "${GH_PRS_FILE}"
    exit 0
    ;;
esac
exit 1
EOF
    chmod +x "${_BIN_DIR}/gh"
}

# herdr: the launch pipeline plus the liveness probe.
#
#   PMT_AGENT_STATUS      status `agent get` reports for the train agent.
#                         Unset (default) = no such agent, i.e. no train has
#                         ever run — `agent get` exits 1 with agent_not_found.
#   HERDR_WORKSPACE_EXISTS=1  `workspace list` already carries the label
#   HERDR_TAB_FAIL=1      `tab create` errors
#   HERDR_START_FAIL=1    `agent start` errors, saying nothing at all — the
#                         unexplained failure, with no parsable error code
#   HERDR_START_NAME_TAKEN=1  `agent start` refuses because a live agent still
#                         holds the name (herdr's real `agent_name_taken`)
#   HERDR_START_PANE_BUSY=N   the first N `agent start` calls lose the #1512
#                         race (`agent_pane_busy`), the rest succeed; a number
#                         above the attempt budget loses it every time.
#                         Counted in a file, not an env var: the stub is a
#                         fresh process per call, so nothing it exports
#                         survives. The counter is per-test — `${CALL_LOG}`
#                         lives in a `mktemp -d` made fresh by `setup()`.
#   HERDR_TAB_CLOSE_FAIL=1  `tab close` errors — the cleanup of an orphaned tab
#                         is best effort and must not become a second failure
#   HERDR_TAB_RENAME_FAIL=1  `tab rename` errors during prompt-stall escalation
#   HERDR_NOTIFY_FAIL=1      `notification show` errors during prompt-stall escalation
#   HERDR_PROMPT_FAIL=1   `agent prompt` errors with `agent_not_found` on
#                         stdout — a real failure, not a #1551 timeout
#   HERDR_PROMPT_CODE=X   `agent prompt` errors with code X on **stderr** —
#                         where herdr really answers a prompt failure
#                         (#1551), same as `agent start`'s agent_pane_busy
#                         below
#
# The `agent_pane_busy` document goes to **stderr**, which is not decoration:
# that is where herdr really put it, and a dispatcher that redirects the stream
# to /dev/null sees an unexplained failure instead of a named race (#1512).
_install_herdr_stub() {
    cat >"${_BIN_DIR}/herdr" <<'EOF'
#!/bin/sh
printf 'herdr %s\n' "$*" >>"${CALL_LOG}"

case "$1 $2" in
"agent get")
    if [ -z "${PMT_AGENT_STATUS:-}" ]; then
        printf '%s\n' '{"error":{"code":"agent_not_found","message":"agent target not found"},"id":"cli:agent:get"}'
        exit 1
    fi
    printf '{"id":"cli:agent:get","result":{"agent":{"agent_status":"%s","state_change_seq":1}}}\n' \
        "${PMT_AGENT_STATUS}"
    ;;
"workspace list")
    if [ "${HERDR_WORKSPACE_EXISTS:-0}" = "1" ]; then
        printf '{"id":"cli:workspace:list","result":{"workspaces":[{"label":"%s","workspace_id":"ws-existing"}]}}\n' \
            "${HERDR_WORKSPACE_LABEL:-mt-dotfiles}"
    else
        printf '%s\n' '{"id":"cli:workspace:list","result":{"workspaces":[]}}'
    fi
    ;;
"workspace create")
    printf '%s\n' '{"id":"cli:workspace:create","result":{"workspace":{"workspace_id":"ws-test-1"},"root_pane":{"pane_id":"ws-test-1:p1"}}}'
    ;;
"tab create")
    [ "${HERDR_TAB_FAIL:-0}" = "1" ] && exit 1
    printf '%s\n' '{"id":"cli:tab:create","result":{"tab":{"tab_id":"ws-test-1:t9"},"pane":{"pane_id":"ws-test-1:p9"}}}'
    ;;
"agent start")
    [ "${HERDR_START_FAIL:-0}" = "1" ] && exit 1
    if [ "${HERDR_START_NAME_TAKEN:-0}" = "1" ]; then
        printf '%s\n' '{"error":{"code":"agent_name_taken","message":"agent name is already used; candidates: status=Idle"},"id":"cli:agent:start"}'
        exit 1
    fi
    if [ "${HERDR_START_PANE_BUSY:-0}" != "0" ]; then
        _seen_file="${CALL_LOG}.start-attempts"
        _seen=$(cat "${_seen_file}" 2>/dev/null) || _seen=0
        _seen=$((_seen + 1))
        printf '%s\n' "${_seen}" >"${_seen_file}"
        if [ "${_seen}" -le "${HERDR_START_PANE_BUSY}" ]; then
            printf '%s\n' '{"error":{"code":"agent_pane_busy","message":"agent target pane ws-test-1:p9 is not an available shell"},"id":"cli:agent:start"}' >&2
            exit 1
        fi
    fi
    printf '%s\n' '{"id":"cli:agent:start","result":{"agent":{"agent_status":"idle","pane_id":"ws-test-1:p9"}}}'
    ;;
"tab close")
    [ "${HERDR_TAB_CLOSE_FAIL:-0}" = "1" ] && exit 1
    printf '%s\n' '{"id":"cli:tab:close","result":{"ok":true}}'
    ;;
"tab rename")
    [ "${HERDR_TAB_RENAME_FAIL:-0}" = "1" ] && exit 1
    printf '%s\n' '{"id":"cli:tab:rename","result":{"ok":true}}'
    ;;
"notification show")
    [ "${HERDR_NOTIFY_FAIL:-0}" = "1" ] && exit 1
    printf '%s\n' '{"id":"cli:notification:show","result":{"ok":true}}'
    ;;
"agent read")
    # The settle-readiness poll (#1570) — this dispatcher's only pane read.
    # `--format text` gives plain lines; herdr answers its error document as
    # JSON on stdout with exit 0 when the target is gone, which the caller has
    # to recognise and skip.
    #
    # HERDR_SETTLE_READ_SEQUENCE=A|B answers A then B on successive calls and
    # holds the last entry once the list runs out; `~` is an empty read.
    if [ "${HERDR_READ_MODE:-ok}" = "missing" ]; then
        printf '%s\n' '{"error":{"code":"agent_not_found","message":"agent target not found"},"id":"cli:agent:read"}'
        exit 0
    fi
    _seq="${HERDR_SETTLE_READ_SEQUENCE:-> claude ready}"
    _seen_file="${CALL_LOG}.settleread"
    _seen=$(cat "${_seen_file}" 2>/dev/null) || _seen=0
    _seen=$((_seen + 1))
    printf '%s\n' "${_seen}" >"${_seen_file}"
    _body=$(printf '%s' "${_seq}" | cut -d'|' -f"${_seen}")
    [ -n "${_body}" ] || _body="${_seq##*|}"
    [ "${_body}" = "~" ] || printf '%s\n' "${_body}"
    ;;
"agent prompt")
    if [ -n "${HERDR_PROMPT_CODE:-}" ]; then
        printf '{"error":{"code":"%s","message":"%s"},"id":"cli:agent:prompt"}\n' \
            "${HERDR_PROMPT_CODE}" "${HERDR_PROMPT_MESSAGE:-stub prompt error}" >&2
        exit 1
    fi
    if [ "${HERDR_PROMPT_FAIL:-0}" = "1" ]; then
        printf '%s\n' '{"error":{"code":"agent_not_found","message":"agent target not found"},"id":"cli:agent:prompt"}'
        exit 1
    fi
    printf '%s\n' '{"id":"cli:agent:prompt","result":{"ok":true}}'
    ;;
esac
exit 0
EOF
    chmod +x "${_BIN_DIR}/herdr"
}

# `_install_sleep_stub` — the #1560 settle-wait stub. Lives in
# ../test_helper.bash; issue_watcher_cron.bats installs the same one.

_install_stubs() {
    _install_gh_stub
    _install_herdr_stub
    _install_sleep_stub
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Run one tick with the stubs on PATH and an isolated XDG_STATE_HOME.
#
#   _run_tick [VAR=VALUE ...] [-- script-flag ...]
#
# `env` applies assignments left to right, so a test can override any of the
# defaults (PATH included) without restating the whole sandbox.
_run_tick() {
    local _env=()
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
        _env+=("$1")
        shift
    done
    [ "$#" -eq 0 ] || shift

    run env \
        "PATH=${_BIN_DIR}:${PATH}" \
        "CALL_LOG=${_LOG}" \
        "GH_PRS_FILE=${_WORK_DIR}/prs.json" \
        "XDG_STATE_HOME=${_STATE_HOME}" \
        "PMT_IDLE_POLL_SLEEP=0" \
        "PMT_START_RETRY_SLEEP=0" \
        "${_env[@]}" \
        bash "${SCRIPT}" --cwd "${_REPO_DIR}" "$@"
}

# Call-log assertions that leave `$output` and `$status` alone — tests pair
# these with `assert_output` on the tick's own output, and a `run grep` here
# would overwrite both.
_assert_logged() {
    grep -qF -- "$1" "${_LOG}" || fail "expected in call log: $1"
}

_refute_logged() {
    ! grep -qF -- "$1" "${_LOG}" || fail "unexpected in call log: $1"
}

# The tick started no train: it neither opened a new pane nor prompted an
# existing one. Both refutes matter — checking only the prompt would pass for a
# tick that opened a tab and then failed to use it.
_refute_train_started() {
    _refute_logged "herdr tab create"
    _refute_logged "herdr agent prompt"
}

_log_count() {
    grep -c -- "$1" "${_LOG}" 2>/dev/null || true
}

# The value passed to the first `--label` flag in the call log. Field-position
# lookup, not a fixed column, so it survives flag reordering upstream.
_pmt_logged_label() {
    awk '{for (i = 1; i <= NF; i++) if ($i == "--label") { print $(i + 1); exit }}' "${_LOG}"
}

# A PATH that carries only the stub dir plus symlinks to the system binaries
# the tick needs — minus the ones named as arguments. Deleting a stub is not
# enough to make a binary missing: `command -v` keeps walking the inherited
# PATH and finds the real one.
_path_without() {
    local _d="${_WORK_DIR}/sysbin" _b _p _skip
    rm -rf "${_d}"
    mkdir -p "${_d}"

    for _b in sh bash env git jq awk sed grep head tail cat cut tr sort \
        uniq date mkdir rmdir rm ln basename dirname sleep mktemp flock tput \
        uname wc chmod find id stty locale; do
        _skip=0
        for _p in "$@"; do
            [ "${_b}" != "${_p}" ] || _skip=1
        done
        [ "${_skip}" -eq 0 ] || continue
        _p=$(command -v "${_b}" 2>/dev/null) || continue
        ln -sf "${_p}" "${_d}/${_b}" 2>/dev/null || true
    done

    printf '%s:%s' "${_BIN_DIR}" "${_d}"
}

# Hold an exclusive flock on the tick's lock file in a background process
# until teardown kills it, so the script under test sees a contended lock.
# Blocks until the holder has actually acquired the lock.
_hold_lock() {
    local _ready="${_WORK_DIR}/lock-held"
    mkdir -p "${_STATE_DIR}"
    flock -x "${_LOCK_FILE}" \
        sh -c "printf held >'${_ready}'; sleep 30" >/dev/null 2>&1 &
    _LOCK_HOLDER_PID=$!

    local _i=0
    while [ ! -s "${_ready}" ] && [ "${_i}" -lt 200 ]; do
        sleep 0.05
        _i=$((_i + 1))
    done
    [ -s "${_ready}" ]
}

# ---------------------------------------------------------------------------
# Syntax & help
# ---------------------------------------------------------------------------

@test "pr_merge_train_cron: bash syntax check" {
    run bash -n "${SCRIPT}"
    assert_success
}

@test "pr_merge_train_cron: --help exits 0 and prints usage" {
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "Usage: pr_merge_train_cron.sh"
    assert_output --partial "--cwd"
    assert_output --partial "--dry-run"
}

@test "pr_merge_train_cron: --help makes no gh or herdr calls" {
    run env "PATH=${_BIN_DIR}:${PATH}" "CALL_LOG=${_LOG}" \
        bash "${SCRIPT}" --help
    assert_success
    _refute_logged "gh "
    _refute_logged "herdr "
}

@test "pr_merge_train_cron: --help documents the crontab registration example" {
    # #1586: the example must match the shipped cron-jobs.json cadence
    # (*/2), or a reader following --help literally installs a cron entry
    # running 2.5x slower than the manifest's own default — the same drift
    # class #1579/#1580 caught for issue-watcher's own --help example.
    run bash "${SCRIPT}" --help
    assert_success
    assert_output --partial "*/2 * * * *"
    assert_output --partial "pr_merge_train_cron.sh"
    assert_output --partial "cron.log"
}

# ---------------------------------------------------------------------------
# Target-PR precondition (F-1, D-6, D-7)
# ---------------------------------------------------------------------------

@test "pr_merge_train_cron: no target PR launches no session and exits 0" {
    _set_prs '[]'
    _run_tick
    assert_success
    assert_output --partial "No target PR"
    _refute_train_started
}

# Exit 0 on a real tick is deliberate: cron must not treat a transient GitHub
# failure as a hard error. `--dry-run` is the opposite (see its section below).
@test "pr_merge_train_cron: a failing gh pr list does not start a train" {
    _run_tick GH_PR_LIST_FAIL=1
    assert_success
    assert_output --partial "gh pr list failed"
    _refute_train_started
}

@test "pr_merge_train_cron: the PR query is scoped to the author's own PRs" {
    _run_tick
    assert_success
    _assert_logged "--author @me"
}

@test "pr_merge_train_cron: the PR query is host-pinned and repo-scoped" {
    _run_tick
    assert_success
    _assert_logged "--repo acme/dotfiles"
}

@test "pr_merge_train_cron: a PR updated inside the quiet period is not a target" {
    _set_prs "[$(_pr_json 11 2)]"
    _run_tick
    assert_success
    assert_output --partial "No target PR"
    _refute_train_started
}

@test "pr_merge_train_cron: a PR updated outside the quiet period is a target" {
    _set_prs "[$(_pr_json 11 30)]"
    _run_tick
    assert_success
    _assert_logged "herdr agent prompt"
}

@test "pr_merge_train_cron: a quiet-period PR does not mask an older sibling" {
    _set_prs "[$(_pr_json 11 2),$(_pr_json 12 30)]"
    _run_tick
    assert_success
    _assert_logged "herdr agent prompt"
}

@test "pr_merge_train_cron: a draft PR is not a target" {
    _set_prs "[$(_pr_json 11 30 true)]"
    _run_tick
    assert_success
    assert_output --partial "No target PR"
    _refute_train_started
}

# The quiet period fails *closed*: a timestamp the filter cannot read must not
# count as a target. The `outside the quiet period` test above is the positive
# control — the same code path with a readable stamp does wake a session.
@test "pr_merge_train_cron: a PR with a null updatedAt is not a target" {
    _set_prs "[$(_pr_json_raw_stamp 11 null)]"
    _run_tick
    assert_success
    assert_output --partial "No target PR"
    _refute_train_started
}

@test "pr_merge_train_cron: a PR with an unparseable updatedAt is not a target" {
    _set_prs "[$(_pr_json_raw_stamp 11 '"not-a-timestamp"')]"
    _run_tick
    assert_success
    assert_output --partial "No target PR"
    _refute_train_started
}

@test "pr_merge_train_cron: an unreadable updatedAt does not mask a real target" {
    _set_prs "[$(_pr_json_raw_stamp 11 null),$(_pr_json 12 30)]"
    _run_tick
    assert_success
    _assert_logged "herdr agent prompt"
}

# ---------------------------------------------------------------------------
# NF-1 — one train at a time
# ---------------------------------------------------------------------------

@test "pr_merge_train_cron: a tick is skipped while another instance holds the lock" {
    _hold_lock
    _run_tick
    assert_success
    assert_output --partial "already running"
    _refute_train_started
}

@test "pr_merge_train_cron: the lock is released so the next tick runs" {
    _run_tick
    assert_success
    _run_tick
    assert_success
    _assert_logged "herdr agent prompt"
}

@test "pr_merge_train_cron: a working train agent from a previous tick blocks a new train" {
    _run_tick PMT_AGENT_STATUS=working
    assert_success
    assert_output --partial "train is already running"
    _refute_train_started
}

@test "pr_merge_train_cron: a blocked train agent also blocks a new train" {
    _run_tick PMT_AGENT_STATUS=blocked
    assert_success
    assert_output --partial "train is already running"
    _refute_train_started
}

@test "pr_merge_train_cron: an idle train agent is reused rather than blocking" {
    _run_tick PMT_AGENT_STATUS=idle
    assert_success
    _assert_logged "herdr agent prompt"
    _refute_logged "herdr tab create"
}

# `done`, and anything else herdr answers with, still means the *name resolves*
# — the pane is open and holding it. Opening a second pane under the same name
# would be refused with agent_name_taken on this tick and on every later one.
@test "pr_merge_train_cron: a done train agent is prompted in place, not re-created" {
    _run_tick PMT_AGENT_STATUS=done
    assert_success
    _assert_logged "herdr agent prompt"
    _refute_logged "herdr tab create"
}

@test "pr_merge_train_cron: an unrecognised agent status is prompted in place too" {
    _run_tick PMT_AGENT_STATUS=some-future-status
    assert_success
    _assert_logged "herdr agent prompt"
    _refute_logged "herdr tab create"
}

# The race the status probe cannot close: the name is claimed between the probe
# and the start. The tick must still make progress rather than dying here every
# period — the holder is by definition an agent that can be prompted.
@test "pr_merge_train_cron: an agent_name_taken start falls back to prompting the holder" {
    _run_tick HERDR_START_NAME_TAKEN=1
    assert_success
    assert_output --partial "already registered"
    _assert_logged "herdr agent prompt"
}

@test "pr_merge_train_cron: missing flock degrades to a warning, not a failure" {
    _run_tick "PATH=$(_path_without flock)"
    assert_success
    assert_output --partial "without single-instance protection"
    _assert_logged "herdr agent prompt"
}

# ---------------------------------------------------------------------------
# D-8 — the launch pipeline
# ---------------------------------------------------------------------------

@test "pr_merge_train_cron: the happy path creates a workspace, a tab and an agent" {
    _run_tick
    assert_success
    _assert_logged "herdr workspace create"
    _assert_logged "herdr tab create"
    _assert_logged "herdr agent start"
}

@test "pr_merge_train_cron: an existing workspace is reused" {
    _run_tick HERDR_WORKSPACE_EXISTS=1
    assert_success
    _refute_logged "herdr workspace create"
    _assert_logged "herdr tab create"
}

@test "pr_merge_train_cron: the session is prompted with the train slash command once" {
    _run_tick
    assert_success
    _assert_logged "/gh-pr-merge-train acme/dotfiles"
    [ "$(_log_count 'herdr agent prompt')" -eq 1 ]
}

@test "pr_merge_train_cron: the pane runs claude with permissions skipped" {
    _run_tick
    assert_success
    _assert_logged "--dangerously-skip-permissions"
}

# ---------------------------------------------------------------------------
# Settle wait after agent start (issue #1560)
# ---------------------------------------------------------------------------
#
# `herdr agent start` answers `"agent_status":"idle"` straight away, so
# _pmt_wait_for_idle returns on its first poll and ~0s pass before the prompt —
# which is why raising _PMT_IDLE_POLL_MAX fixes nothing. These pin the wait that
# does, and pin that the reuse path does not pay it.
#
# Since #1570 that wait polls the pane's own text instead of sleeping flat: 13
# is the cap, a pane that reads stable leaves early, and a pane that never does
# still warns and still prompts — the pre-#1570 behaviour, kept reachable.

@test "pr_merge_train_cron: a pane that reads stable is prompted before the cap" {
    _run_tick
    assert_success
    _assert_logged "herdr agent prompt"
    [ "$(_log_count '^sleep 1$')" -eq 1 ]
    refute_output --partial "never settled"
}

@test "pr_merge_train_cron: the settle poll reads the pane" {
    _run_tick
    assert_success
    _assert_logged "herdr agent read mt-dotfiles --lines 3 --format text"
}

@test "pr_merge_train_cron: the settle poll happens after the idle check, not before" {
    _run_tick
    assert_success
    _start_line=$(grep -n "herdr agent start" "${_LOG}" | head -1 | cut -d: -f1)
    _settle_line=$(grep -n "herdr agent read mt-dotfiles --lines 3" "${_LOG}" | head -1 | cut -d: -f1)
    _prompt_line=$(grep -n "herdr agent prompt" "${_LOG}" | head -1 | cut -d: -f1)
    [ "${_start_line}" -lt "${_settle_line}" ]
    [ "${_settle_line}" -lt "${_prompt_line}" ]
}

@test "pr_merge_train_cron: a pane that never settles still warns and prompts at the cap" {
    _run_tick "HERDR_SETTLE_READ_SEQUENCE=~"
    assert_success
    assert_output --partial "never settled within 13s"
    _assert_logged "herdr agent prompt"
    [ "$(_log_count '^sleep 1$')" -eq 12 ]
}

@test "pr_merge_train_cron: a stable 'Not logged in' pane is not read as ready" {
    _run_tick "HERDR_SETTLE_READ_SEQUENCE=Not logged in"
    assert_success
    assert_output --partial "never settled within 13s"
    _assert_logged "herdr agent prompt"
}

@test "pr_merge_train_cron: an unreadable pane degrades to not-ready, never aborts" {
    _run_tick HERDR_READ_MODE=missing
    assert_success
    assert_output --partial "never settled within 13s"
    _assert_logged "herdr agent prompt"
}

@test "pr_merge_train_cron: PMT_SETTLE_SECONDS=0 removes the settle wait entirely" {
    _run_tick PMT_SETTLE_SECONDS=0
    assert_success
    _assert_logged "herdr agent prompt"
    _refute_logged "sleep "
    _refute_logged "herdr agent read"
}

@test "pr_merge_train_cron: PMT_SETTLE_SECONDS caps the poll, not one flat sleep" {
    _run_tick PMT_SETTLE_SECONDS=7 "HERDR_SETTLE_READ_SEQUENCE=~"
    assert_success
    assert_output --partial "never settled within 7s"
    [ "$(_log_count '^sleep 1$')" -eq 6 ]
    _refute_logged "sleep 7"
}

# A fractional override predates the poll and cannot bound a poll count, so it
# still means the flat wait it always meant.
@test "pr_merge_train_cron: a fractional settle cap stays a flat wait" {
    _run_tick PMT_SETTLE_SECONDS=0.5
    assert_success
    _assert_logged "sleep 0.5"
    _assert_logged "herdr agent prompt"
    _refute_logged "herdr agent read"
}

@test "pr_merge_train_cron: the settle poll interval is overridable" {
    _run_tick PMT_SETTLE_POLL_SLEEP=4 "HERDR_SETTLE_READ_SEQUENCE=~"
    assert_success
    [ "$(_log_count '^sleep 4$')" -eq 12 ]
    [ "$(_log_count '^sleep 1$')" -eq 0 ]
}

@test "pr_merge_train_cron: PMT_SETTLE_POLL_SLEEP=0 polls without sleeping at all" {
    _run_tick PMT_SETTLE_POLL_SLEEP=0 "HERDR_SETTLE_READ_SEQUENCE=~"
    assert_success
    _refute_logged "sleep "
    assert_output --partial "never settled within 13s"
    _assert_logged "herdr agent prompt"
}

# The reuse path is the common case once a train pane is open — one tick every
# cron period, each prompting a session that has been warm for minutes. A settle
# there would be 13 wasted seconds per PR, so it must not run (#1560 D-3).
@test "pr_merge_train_cron: reusing a live session skips the settle wait" {
    _run_tick PMT_AGENT_STATUS=idle
    assert_success
    _assert_logged "herdr agent prompt"
    _refute_logged "herdr tab create"
    _refute_logged "sleep "
    # Not one poll either — _pmt_settle is called from _pmt_launch_fresh only.
    _refute_logged "herdr agent read"
}

@test "pr_merge_train_cron: a done session is also prompted without settling" {
    _run_tick PMT_AGENT_STATUS=done
    assert_success
    _assert_logged "herdr agent prompt"
    _refute_logged "sleep "
    _refute_logged "herdr agent read"
}

# The `agent_name_taken` fallback prompts a session someone else already
# started — warm by definition, so it takes the reuse rule, not the fresh one.
@test "pr_merge_train_cron: the agent_name_taken fallback does not settle" {
    _run_tick HERDR_START_NAME_TAKEN=1
    assert_success
    _assert_logged "herdr agent prompt"
    _refute_logged "sleep "
    _refute_logged "herdr agent read"
}

@test "pr_merge_train_cron: a tick that never starts an agent never settles" {
    _run_tick HERDR_TAB_FAIL=1
    assert_failure
    _refute_logged "sleep "
    _refute_logged "herdr agent read"
}

@test "pr_merge_train_cron: a herdr tab failure ends the tick without a prompt" {
    _run_tick HERDR_TAB_FAIL=1
    assert_failure
    _assert_logged "herdr tab create"
    _refute_logged "herdr agent start"
    _refute_logged "herdr agent prompt"
}

@test "pr_merge_train_cron: a herdr agent start failure ends the tick without a prompt" {
    _run_tick HERDR_START_FAIL=1
    assert_failure
    _assert_logged "herdr agent start"
    _refute_logged "herdr agent prompt"
}

# ---------------------------------------------------------------------------
# #1512 — the `agent_pane_busy` race on a pane that was just created
# ---------------------------------------------------------------------------
#
# A tab's shell is not interactive the instant `tab create` answers, so
# `agent start` on it can be refused with `agent_pane_busy` and return
# immediately. In cron that lost every single tick for weeks. It is a timing
# race, not a defect in the pane, so the second attempt is the fix — the pane
# is fine a moment later.

@test "pr_merge_train_cron: a transient agent_pane_busy is retried and the train still starts" {
    _run_tick HERDR_START_PANE_BUSY=1
    assert_success
    [ "$(_log_count 'herdr agent start')" -eq 2 ]
    _assert_logged "/gh-pr-merge-train acme/dotfiles"
}

# The gap itself is 13s since #1571, not the 2s this shipped with: `tab create`
# answering before the pane's shell is interactive is the *same* class of race
# as the settle wait above, and 2s was shorter than the 5s already measured to
# fail. Unlike the settle wait it is still a flat sleep — #1570 turned only the
# settle into a poll, because only the settle has a pane to read. Asserted
# through the message rather than a `sleep` line, which is what tells the two
# waits apart in the call log.
@test "pr_merge_train_cron: the start retry gap defaults to 13s" {
    # An empty assignment beats _run_tick's own `PMT_START_RETRY_SLEEP=0` and
    # still lets `${PMT_START_RETRY_SLEEP:-13}` fall through to the default.
    _run_tick HERDR_START_PANE_BUSY=1 "PMT_START_RETRY_SLEEP="
    assert_success
    assert_output --partial "retrying in 13s"
}

@test "pr_merge_train_cron: the start retry gap stays env-overridable" {
    _run_tick HERDR_START_PANE_BUSY=1 "PMT_START_RETRY_SLEEP=4"
    assert_success
    assert_output --partial "retrying in 4s"
    refute_output --partial "retrying in 13s"
}

# The SSOT lines themselves, so a change that only moves a default out of the
# ${VAR:-13} form (and with it the `0` escape the suite depends on) is caught
# here rather than as a mysteriously slow suite.
@test "pr_merge_train_cron: both herdr wait constants are 13 and overridable" {
    run grep -qF -- '_PMT_SETTLE_SECONDS="${PMT_SETTLE_SECONDS:-13}"' "${SCRIPT}"
    assert_success
    run grep -qF -- '_PMT_START_RETRY_SLEEP="${PMT_START_RETRY_SLEEP:-13}"' "${SCRIPT}"
    assert_success
}

# #1530/#1549 and #1560/#1571 were both "two of the three dispatchers were
# fixed". The comment naming the other two is the guard against a third round.
@test "pr_merge_train_cron: the wait comments name the other two dispatchers" {
    run grep -qF -- '_IW_SETTLE_SECONDS' "${SCRIPT}"
    assert_success
    run grep -qF -- 'PMV_SETTLE_SECONDS' "${SCRIPT}"
    assert_success
}

# The twin of the issue-watcher pin: the shared "no signal from herdr" excuse
# for a flat sleep is gone from both dispatchers (#1570).
@test "pr_merge_train_cron: the settle comment no longer claims herdr exposes no signal" {
    run grep -qF -- 'herdr exposes no signal' "${SCRIPT}"
    assert_failure
}

# The retrying is bounded, and the bound is the whole point: cron re-runs every
# few minutes anyway, so a tick that kept trying would only hold the lock
# while the *next* tick is the thing that should be deciding. Three *attempts*
# — one initial plus two retries — is what _PMT_START_ATTEMPT_MAX names.
@test "pr_merge_train_cron: a permanent agent_pane_busy stops after the attempt budget" {
    _run_tick HERDR_START_PANE_BUSY=99
    assert_failure
    [ "$(_log_count 'herdr agent start')" -eq 3 ]
    _refute_logged "herdr agent prompt"
}

# The tab was opened by this tick and now holds nothing. Leaving it behind is
# what filled the merge-train workspace with 40+ dead tabs, one per cron
# period — the failure was invisible, but its litter was not.
@test "pr_merge_train_cron: a start that never succeeds closes the tab it opened" {
    _run_tick HERDR_START_PANE_BUSY=99
    assert_failure
    _assert_logged "herdr tab close ws-test-1:t9"
}

# The #1458 regression guard. herdr names this race precisely, on stderr; the
# dispatcher used to throw that stream away and report a generic failure, so
# the log said only "start failed" for weeks. Restoring `2>/dev/null` to
# _pmt_agent_start must make this test red.
@test "pr_merge_train_cron: a failed start reports the cause herdr gave on stderr" {
    _run_tick HERDR_START_PANE_BUSY=99
    assert_failure
    assert_output --partial "agent_pane_busy"
    assert_output --partial "원인:"
    assert_output --partial "is not an available shell"
}

# What herdr writes to stderr is a JSON document, so dumping its first line
# verbatim buries the sentence inside braces exactly where a cron log is read
# in a hurry. The cause line carries `.error.message` alone; the raw document
# must not reach the log (PR #1517 review, codex).
@test "pr_merge_train_cron: the cause line carries the message, not the raw JSON" {
    _run_tick HERDR_START_PANE_BUSY=99
    assert_failure
    refute_output --partial '{"error"'
}

# The name-taken path hands the tick to a *live* agent, and the fresh tab is
# the one this tick just opened, on which no agent was ever placed. The holder
# we go on to prompt lives on some *other* pane, so this tab
# is orphan state of exactly the kind #1512 exists to stop leaking — one per
# probe/start race, on a job that ticks every few minutes. Prompting the holder
# and closing the tab are independent acts; doing only the first is the leak.
@test "pr_merge_train_cron: an agent_name_taken start closes the tab it opened" {
    _run_tick HERDR_START_NAME_TAKEN=1
    assert_success
    _assert_logged "herdr tab close ws-test-1:t9"
    _assert_logged "herdr agent prompt"
}

# Order matters, and only in one direction: the close precedes the prompt so a
# prompt that fails cannot strand the tab behind it. Asserted as a failed tick
# that still cleaned up, which is the case the ordering exists for.
@test "pr_merge_train_cron: a name_taken tab is closed even when the prompt fails" {
    _run_tick HERDR_START_NAME_TAKEN=1 HERDR_PROMPT_FAIL=1
    assert_failure
    _assert_logged "herdr tab close ws-test-1:t9"
}

# Only the one known race is retried. An `agent start` that fails without
# naming itself is not a race we understand, and ending the tick immediately —
# the contract since #1470 — keeps it that way. It still gets the cleanup.
@test "pr_merge_train_cron: an unexplained start failure is not retried but is cleaned up" {
    _run_tick HERDR_START_FAIL=1
    assert_failure
    [ "$(_log_count 'herdr agent start')" -eq 1 ]
    _assert_logged "herdr tab close ws-test-1:t9"
}

# Cleanup is best effort by design: the tick has already failed, and a herdr
# that cannot close the tab is not a second, different verdict to report.
@test "pr_merge_train_cron: a failing tab close does not change the tick's verdict" {
    _run_tick HERDR_START_PANE_BUSY=99 HERDR_TAB_CLOSE_FAIL=1
    assert_failure
    _assert_logged "herdr tab close ws-test-1:t9"
    assert_output --partial "agent_pane_busy"
}

@test "pr_merge_train_cron: a failed prompt is reported as a failed tick" {
    _run_tick HERDR_PROMPT_FAIL=1
    assert_failure
    assert_output --partial "prompt failed"
}

# #1551: `--wait` only bounds the *observation* of a state change after
# submission — a `timeout` here means the prompt landed and only the wait
# window expired, not that dispatch failed. Counting it as a failure is what
# kept #1531's `Tick complete` acceptance criterion from ever firing on a
# train that was actually running.
@test "pr_merge_train_cron: a prompt timeout is retried and eventually fails the tick" {
    _run_tick HERDR_PROMPT_CODE=timeout
    assert_failure
    [ "$(_log_count 'herdr agent prompt')" -eq 3 ]
    assert_output --partial "retrying after 13s settle (1/3)"
    assert_output --partial "retrying after 13s settle (2/3)"
    assert_output --partial "prompt failed"
}

@test "pr_merge_train_cron: a stalled prompt is retried and also fails the tick" {
    _run_tick HERDR_PROMPT_CODE=agent_prompt_stalled
    assert_failure
    [ "$(_log_count 'herdr agent prompt')" -eq 3 ]
    assert_output --partial "prompt failed"
}

# The same defect this fixes also swallowed the error *cause* (#1551's other
# half): `2>/dev/null` threw away herdr's error document, so every failure —
# timeout included — logged as "(unknown)". This pins that the code now
# reads from stderr, where herdr actually answers.
@test "pr_merge_train_cron: a prompt timeout names the code, not 'unknown'" {
    _run_tick HERDR_PROMPT_CODE=timeout
    assert_failure
    assert_output --partial "(timeout)"
    refute_output --partial "(unknown)"
}

@test "pr_merge_train_cron: a prompt timeout renames the tab and shows a notification" {
    _run_tick HERDR_PROMPT_CODE=timeout
    assert_failure
    _assert_logged "herdr tab rename ws-test-1:t9 mt-dotfiles-STUCK"
    _assert_logged "herdr notification show merge-train prompt stalled --body acme/dotfiles merge-train prompt failed repeatedly — herdr agent attach mt-dotfiles --sound request"
}

@test "pr_merge_train_cron: a non-timeout prompt error on stderr still fails the tick" {
    _run_tick HERDR_PROMPT_CODE=agent_not_found
    assert_failure
    assert_output --partial "prompt failed"
    assert_output --partial "(agent_not_found)"
}

# PR #1572 review (codex): the test above pins the *code* but not herdr's own
# sentence about the failure — a regression that dropped the `원인:` message
# while keeping the code intact would slip through unnoticed. This pins both.
@test "pr_merge_train_cron: a non-timeout prompt error preserves herdr's own message" {
    _run_tick HERDR_PROMPT_CODE=agent_not_found HERDR_PROMPT_MESSAGE="agent target not found for real"
    assert_failure
    assert_output --partial "원인:"
    assert_output --partial "agent target not found for real"
}

# herdr refuses `agent start` unless the name matches
# `^[a-z][a-z0-9_-]{0,31}$`. The pre-#1530 name (`pmt-github.com-acme-dotfiles`)
# carried both a dot and, on a real owner like `dEitY719`, uppercase — so every
# tick's start was rejected and the train never ran once. This pins the shape
# herdr actually accepts.
@test "pr_merge_train_cron: the train agent's name satisfies herdr's rule" {
    _run_tick
    assert_success
    _assert_logged "herdr agent get mt-dotfiles"
    _assert_logged "herdr agent start mt-dotfiles"
    _refute_logged "pmt-github.com-acme-dotfiles"

    local _name
    _name=$(awk '$2 == "agent" && $3 == "start" { print $4; exit }' "${_LOG}")
    assert_valid_herdr_name "${_name}"
}

# The agent name is the NF-1 singleton lock: `_pmt_train_state` asks herdr
# whether an agent by this exact name is still working, so two ticks against
# the same repo must compute the same string. A per-tick discriminator (a PR
# number, a timestamp) would make every tick miss the running train and start
# a second one merging onto the same base.
@test "pr_merge_train_cron: the train agent's name is stable across ticks" {
    _run_tick
    assert_success
    _assert_logged "herdr agent get mt-dotfiles"

    : >"${_LOG}"
    _run_tick
    assert_success
    _assert_logged "herdr agent get mt-dotfiles"
}

# The workspace label equals the agent name (#1549): a train findable as
# `mt-dotfiles` under `herdr agent get` but `mt-github.com-acme-dotfiles` under
# `herdr workspace list` is the observability gap #1549 closes. The second half
# pins host-invariance — re-introducing a host-qualified fold must fail here.
@test "pr_merge_train_cron: the workspace label matches the agent name" {
    _run_tick
    assert_success
    _assert_logged "--label mt-dotfiles"
    _refute_logged "--label mt-github.com-acme-dotfiles"

    # `_assert_logged` is a substring match, so it would also pass on a label
    # that merely starts with `mt-dotfiles`. Pin the whole field instead — the
    # property under test is "label == agent name", not herdr's agent-name
    # regex, which does not constrain labels at all. Checked on *both* ticks
    # below (github.com and GHES), not only the last one — each host gets its
    # own log, so neither exact match can hide behind the other's pass (#1556
    # review, agy).
    assert_equal "$(_pmt_logged_label)" "mt-dotfiles"

    local _ghe="${_WORK_DIR}/ghe-dotfiles"
    mkdir -p "${_ghe}"
    git -C "${_ghe}" init -q
    git -C "${_ghe}" remote add origin "https://github.samsungds.net/acme/dotfiles.git"
    _REPO_DIR="${_ghe}"
    : >"${_LOG}"

    _run_tick
    assert_success
    _assert_logged "--label mt-dotfiles"
    _refute_logged "--label mt-github.samsungds.net-acme-dotfiles"
    assert_equal "$(_pmt_logged_label)" "mt-dotfiles"
}

@test "pr_merge_train_cron: the dispatcher never writes to GitHub" {
    _run_tick
    assert_success
    _refute_logged "gh pr merge"
    _refute_logged "gh pr edit"
    _refute_logged "gh pr comment"
    _refute_logged "gh api"
}

# ---------------------------------------------------------------------------
# CLAUDE_CONFIG_DIR routing (issue #1393, #1561)
# ---------------------------------------------------------------------------

@test "pr_merge_train_cron: the pane is routed at the default account" {
    _run_tick
    assert_success
    _assert_logged "--env CLAUDE_CONFIG_DIR=${HOME}/.claude-personal"
}

@test "pr_merge_train_cron: a missing account directory fails fast before the pane" {
    rm -rf "${HOME}/.claude-personal"
    _run_tick
    assert_failure
    assert_output --partial "Claude account directory missing"
    _refute_train_started
}

# Issue #1561. The directory check above is not enough: `claude-accounts setup`
# creates the directory, only a completed login fills it. A logged-out pane
# opens on `Not logged in`, drops every keystroke, and the tick reports
# `agent_prompt_stalled` — a symptom that names neither the account nor the
# cause. These pin the failure at the routing step instead.
@test "pr_merge_train_cron: an account with no credentials fails fast before the pane" {
    rm -f "${HOME}/.claude-personal/.credentials.json"
    _run_tick
    assert_failure
    assert_output --partial "not logged in"
    _refute_train_started
}

@test "pr_merge_train_cron: an empty credentials file fails fast the same way" {
    : >"${HOME}/.claude-personal/.credentials.json"
    _run_tick
    assert_failure
    assert_output --partial "not logged in"
    _refute_train_started
}

# PR #1566 codex review. Non-empty is not parseable: a login killed mid-write
# leaves a truncated file that clears `-s` and still opens the pane on
# `Not logged in` — the exact stall this check exists to name. `jq -e` is the
# whole of the extra test; no key of the credential format is read.
@test "pr_merge_train_cron: a truncated credentials file fails fast the same way" {
    printf '%s' '{"claudeAiOauth":{"accessToken":"te' \
        >"${HOME}/.claude-personal/.credentials.json"
    _run_tick
    assert_failure
    assert_output --partial "not logged in"
    _refute_train_started
}

@test "pr_merge_train_cron: a credentials file that is not JSON at all fails fast" {
    printf 'not json\n' >"${HOME}/.claude-personal/.credentials.json"
    _run_tick
    assert_failure
    assert_output --partial "not logged in"
    _refute_train_started
}

@test "pr_merge_train_cron: the credentials check names the file it looked at" {
    rm -f "${HOME}/.claude-personal/.credentials.json"
    _run_tick
    assert_failure
    assert_output --partial "${HOME}/.claude-personal/.credentials.json"
}

# The reuse path never resolves an account — the pane already carries the one
# it was opened with — so a logged-out *default* account cannot end a tick that
# was not going to open a pane anyway.
@test "pr_merge_train_cron: the reuse path is not blocked by the credentials check" {
    rm -f "${HOME}/.claude-personal/.credentials.json"
    _run_tick PMT_AGENT_STATUS=idle
    assert_success
    _assert_logged "herdr agent prompt"
}

# ---------------------------------------------------------------------------
# --dry-run
# ---------------------------------------------------------------------------

@test "pr_merge_train_cron: --dry-run reports the target count and launches nothing" {
    _run_tick -- --dry-run
    assert_success
    assert_output --partial "Dry run"
    _refute_train_started
}

@test "pr_merge_train_cron: --dry-run does not take the tick lock" {
    _hold_lock
    _run_tick -- --dry-run
    assert_success
    assert_output --partial "Dry run"
}

# A human asked "what does the train see?". Exiting 0 on a query that could not
# be answered would tell them everything is fine — the real tick's exit 0 is a
# cron accommodation and does not apply to a hand-run probe.
@test "pr_merge_train_cron: --dry-run reports a failing gh pr list as a failed probe" {
    _run_tick GH_PR_LIST_FAIL=1 -- --dry-run
    assert_failure
    assert_output --partial "gh pr list failed"
    _refute_train_started
}

@test "pr_merge_train_cron: --dry-run leaves no state behind" {
    _run_tick -- --dry-run
    assert_success
    [ ! -e "${_LOCK_FILE}" ]
}

# ---------------------------------------------------------------------------
# Argument handling
# ---------------------------------------------------------------------------

@test "pr_merge_train_cron: an unknown option fails with a usage pointer" {
    run bash "${SCRIPT}" --nope
    assert_failure
    assert_output --partial "Unknown option"
}

@test "pr_merge_train_cron: --cwd without a path fails" {
    run bash "${SCRIPT}" --cwd
    assert_failure
    assert_output --partial "--cwd requires"
}

@test "pr_merge_train_cron: a checkout with no origin remote fails with a reason" {
    git -C "${_REPO_DIR}" remote remove origin
    _run_tick
    assert_failure
    assert_output --partial "No 'origin' remote"
    assert_output --partial "--cwd"
    _refute_logged "gh pr list"
}

@test "pr_merge_train_cron: an unreachable --cwd fails" {
    run bash "${SCRIPT}" --cwd "${_WORK_DIR}/nowhere"
    assert_failure
    assert_output --partial "Cannot cd"
}
