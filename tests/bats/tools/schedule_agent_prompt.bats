#!/usr/bin/env bats
# tests/bats/tools/schedule_agent_prompt.bats
# Tests for schedule_agent_prompt.sh — the one-shot herdr prompt scheduler
# (issue #1768).
#
# The job this tool does has exactly one failure mode worth designing against:
# a call that is accepted but has no effect. The 2026-09-05 recovery this issue
# generalises typed a `/restart` into a pane and never sent Enter, so the suite
# is organised around proving the *effect*, not the call:
#
#   A1  --dry-run   validates and prints, creates no job, mutates no herdr
#   A2  default     the registered job submits exactly `/restart`
#   A3  custom      `abc def ~~~` reaches herdr as one unmodified argument
#   A4  multi       targets are independent — one failure never skips the rest
#   A5  ambiguity   zero or 2+ exact `cwd` matches refuse to inject, silently
#                   never guessing which pane was meant
#   A6  state       --status reports pending/completed/failed, --cancel stops a
#                   pending job from ever dispatching
#   A7  wait        a `--wait` that times out is a failure for that target, and
#                   is recorded as one
#   A8  packaging   the PATH symlink is registered; bash and zsh both parse the
#                   script
#
# `herdr` is a shell function exported into the script's environment (the
# convention tests/bats/functions/herdr_agent_lookup.bats established), driven
# by env vars and appending every call to a log file. Each logged line is the
# argument vector bracketed per argument — `[agent][prompt][w1N:pH][/restart]…`
# — so an assertion can pin argument *boundaries*, which is the whole point
# when the payload is a prompt containing spaces.

load '../test_helper'

SCRIPT="${DOTFILES_ROOT}/shell-common/tools/custom/schedule_agent_prompt.sh"

setup() {
    setup_isolated_home

    _WORK="$(mktemp -d "${TMPDIR:-/tmp}/sap-test.XXXXXX")"
    _LOG="${_WORK}/herdr.log"
    _STATE_HOME="${_WORK}/state"
    _STATE_DIR="${_STATE_HOME}/dotfiles/schedule-agent-prompt"
    _A="${_WORK}/repo-a"
    _B="${_WORK}/repo-b"
    mkdir -p "${_A}" "${_B}"
    : >"${_LOG}"

    export XDG_STATE_HOME="${_STATE_HOME}"
    export HERDR_LOG="${_LOG}"
    export AGENT_JSON=""
    export AGENT_RC=0

    _write_stub
}

teardown() {
    _reap_jobs
    rm -rf "${_WORK}"
    teardown_isolated_home
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# The herdr stand-in. Written to a file and sourced by the run wrapper rather
# than defined inline, so the same text drives the script, the detached
# dispatcher it spawns, and any subshell in between.
_write_stub() {
    cat >"${_WORK}/stub.sh" <<'STUB'
herdr() {
    { printf '[%s]' "$@"; printf '\n'; } >>"${HERDR_LOG}"
    case "$1 $2" in
    "agent list")
        [ "${AGENT_RC:-0}" -eq 0 ] || return "${AGENT_RC}"
        printf '%s' "${AGENT_JSON-}"
        ;;
    "agent prompt")
        if [ -n "${FAIL_PANE-}" ] && [ "${FAIL_PANE}" = "$3" ]; then
            printf '%s' "${FAIL_OUT:-herdr: agent_prompt_stalled}"
            return "${FAIL_RC:-1}"
        fi
        printf '%s' "${PROMPT_OUT:-{\"result\":{\"agent_status\":\"idle\"}}}"
        ;;
    *)
        return 1
        ;;
    esac
}
export -f herdr

# A BSD/macOS `date`, on demand: `-d` is the daylight-savings flag there, not
# "parse this date string", so it never yields an epoch. `-j -f` is the form
# that does. Inert unless BSD_DATE is set, so every other test still runs
# against the real thing.
date() {
    if [ -n "${BSD_DATE-}" ]; then
        case "$1" in
        -d) return 1 ;;
        -j)
            command date -d "$4" '+%s'
            return $?
            ;;
        esac
    fi
    command date "$@"
}
export -f date
STUB
}

# One agent record from `cwd|pane_id[|foreground_cwd]`.
_agent() {
    local cwd pane fg
    IFS='|' read -r cwd pane fg <<<"$1"
    printf '{"cwd":"%s","foreground_cwd":"%s","pane_id":"%s","tab_id":"t-1","agent_status":"idle"}' \
        "$cwd" "${fg:-$cwd}" "$pane"
}

_set_agents() {
    local spec sep="" out=""
    for spec in "$@"; do
        out="${out}${sep}$(_agent "$spec")"
        sep=","
    done
    export AGENT_JSON="{\"result\":{\"agents\":[${out}]}}"
}

# Run the script with the herdr stand-in in scope.
sap() {
    run bash --noprofile --norc -c '. "$1" || exit 99; shift; "$@"' sap \
        "${_WORK}/stub.sh" "${SCRIPT}" "$@"
}

# A local HH:MM a few minutes out. Skips rather than guesses when "a few
# minutes out" lands on tomorrow: the tool rejects a past time by design, so a
# midnight-crossing run would be testing the clock, not the tool.
_future_hhmm() {
    local now_day later_day
    now_day="$(date '+%d')"
    later_day="$(date -d '+5 minutes' '+%d')"
    if [ "${now_day}" != "${later_day}" ]; then
        skip "now + 5 minutes crosses midnight"
    fi
    date -d '+5 minutes' '+%H:%M'
}

_job_file() {
    local f
    for f in "${_STATE_DIR}"/*.json; do
        [ -f "$f" ] && printf '%s\n' "$f" && return 0
    done
    return 1
}

_job_field() {
    jq -r "$1" "$(_job_file)"
}

# Stop the detached waiter and move its wake-up into the past, so the
# dispatcher half can be exercised without waiting five real minutes.
_expire_job() {
    local f pid tmp
    f="$(_job_file)"
    pid="$(jq -r '.pid // empty' "$f")"
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    tmp="${f}.t"
    jq '.at_epoch = 1' "$f" >"$tmp" && mv "$tmp" "$f"
}

_dispatch_job() {
    sap --dispatch "$(_job_file)"
}

_reap_jobs() {
    local f pid
    for f in "${_STATE_DIR}"/*.json; do
        [ -f "$f" ] || continue
        pid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
        [ -n "$pid" ] && kill "$pid" 2>/dev/null
    done
    return 0
}

_prompt_calls() {
    grep -c '^\[agent\]\[prompt\]' "${_LOG}" || true
}

# ---------------------------------------------------------------------------
# A1 — --dry-run
# ---------------------------------------------------------------------------

@test "A1: --dry-run validates and prints the planned default /restart injection" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}" --dry-run
    assert_success
    assert_output --partial "/restart"
    assert_output --partial "${_A}"
    assert_output --partial "w1N:pH"
}

@test "A1b: --dry-run creates no job state and calls no herdr mutation" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}" --dry-run
    assert_success

    run _job_file
    assert_failure

    run grep -c '^\[agent\]\[list\]' "${_LOG}"
    assert_success
    run _prompt_calls
    assert_output "0"
}

# ---------------------------------------------------------------------------
# A2 — the default prompt
# ---------------------------------------------------------------------------

@test "A2: with no --prompt the registered job submits exactly /restart" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_success
    run _job_field '.prompt'
    assert_output "/restart"

    _expire_job
    : >"${_LOG}"
    _dispatch_job
    assert_success
    run cat "${_LOG}"
    # No `--until`: herdr's own default already matches idle/done/blocked, and
    # pinning one of the three turned the other two into false failures.
    assert_output --partial '[agent][prompt][w1N:pH][/restart][--wait][--timeout]'
    refute_output --partial '[--until]'
}

@test "A2c: SCHEDULE_AGENT_PROMPT_UNTIL pins --wait back to one state" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_success
    _expire_job
    : >"${_LOG}"
    export SCHEDULE_AGENT_PROMPT_UNTIL=blocked
    _dispatch_job
    assert_success
    run cat "${_LOG}"
    assert_output --partial '[--wait][--until][blocked][--timeout]'
}

@test "A2b: a registered job starts pending, records its targets and detaches" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_success

    run _job_field '.status'
    assert_output "pending"
    run _job_field '.targets[0]'
    assert_output "${_A}"

    # The waiter outlives the invoking shell: it is a live process of its own,
    # not a job of the shell that registered it.
    local pid
    pid="$(_job_field '.pid')"
    run kill -0 "$pid"
    assert_success
}

# ---------------------------------------------------------------------------
# A3 — a custom prompt reaches herdr unmodified
# ---------------------------------------------------------------------------

@test "A3: --prompt 'abc def ~~~' is passed as one literal TEXT argument" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}" --prompt "abc def ~~~"
    assert_success
    _expire_job
    : >"${_LOG}"
    _dispatch_job
    assert_success

    # Bracketed per argument: the spaces and tildes stayed inside ONE argument
    # rather than being split, globbed or expanded on the way through.
    run cat "${_LOG}"
    assert_output --partial '[agent][prompt][w1N:pH][abc def ~~~][--wait]'
}

# ---------------------------------------------------------------------------
# A4 — independent targets
# ---------------------------------------------------------------------------

@test "A4: one target failing to inject does not skip the others" {
    _set_agents "${_A}|w1N:pH" "${_B}|w2N:pQ"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}" --agent-cwd "${_B}"
    assert_success
    _expire_job
    : >"${_LOG}"

    export FAIL_PANE="w1N:pH"
    export FAIL_RC=4
    _dispatch_job
    assert_failure

    run cat "${_LOG}"
    assert_output --partial '[agent][prompt][w1N:pH]'
    assert_output --partial '[agent][prompt][w2N:pQ]'

    run _job_field '.results[] | select(.cwd == "'"${_B}"'") | .outcome'
    assert_output "submitted"
    run _job_field '.status'
    assert_output "failed"
}

@test "A4b: a target that stops resolving at dispatch time does not stop the rest" {
    _set_agents "${_A}|w1N:pH" "${_B}|w2N:pQ"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}" --agent-cwd "${_B}"
    assert_success
    _expire_job
    : >"${_LOG}"

    # The pane that was there at registration is gone by dispatch time.
    _set_agents "${_B}|w2N:pQ"
    _dispatch_job
    assert_failure

    run _job_field '.results[] | select(.cwd == "'"${_A}"'") | .outcome'
    assert_output "unresolved"
    run _job_field '.results[] | select(.cwd == "'"${_B}"'") | .outcome'
    assert_output "submitted"
    run cat "${_LOG}"
    refute_output --partial '[agent][prompt][w1N:pH]'
}

# ---------------------------------------------------------------------------
# A5 — ambiguity is refused, never guessed
# ---------------------------------------------------------------------------

@test "A5: a cwd matching no agent is refused at registration" {
    _set_agents "${_B}|w2N:pQ"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_failure
    assert_output --partial "${_A}"
    run _job_file
    assert_failure
    run _prompt_calls
    assert_output "0"
}

@test "A5b: two agents on one cwd are refused — no pane is typed into" {
    _set_agents "${_A}|w1N:pH" "${_A}|w9N:pZ"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_failure
    assert_output --partial "2"
    run _job_file
    assert_failure
    run _prompt_calls
    assert_output "0"
}

@test "A5c: ambiguity discovered at dispatch time injects nothing for that target" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_success
    _expire_job
    : >"${_LOG}"

    _set_agents "${_A}|w1N:pH" "${_A}|w9N:pZ"
    _dispatch_job
    assert_failure
    run _prompt_calls
    assert_output "0"
    run _job_field '.results[0].outcome'
    assert_output "unresolved"
}

@test "A5d: matching is exact on cwd — a sibling sharing the prefix is not a match" {
    # Deliberately NOT herdr_agent_match_for_cwd's boundary rule: that helper
    # answers "is any agent working under this tree", which is the wrong
    # question when the answer decides where a keystroke lands.
    mkdir -p "${_A}-2"
    _set_agents "${_A}-2|w2N:pQ"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_failure
    run _prompt_calls
    assert_output "0"
}

@test "A5e: foreground_cwd alone is not a match" {
    # foreground_cwd tracks the pane's live shell and drifts after a `cd`;
    # only the launch-time cwd is restart-stable identity.
    _set_agents "/elsewhere|w2N:pQ|${_A}"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_failure
    run _prompt_calls
    assert_output "0"
}

@test "A5f: a symlinked --agent-cwd matches the agent's physical cwd" {
    ln -sfn "${_A}" "${_WORK}/link-a"
    _set_agents "$(cd -P "${_A}" && pwd -P)|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_WORK}/link-a" --dry-run
    assert_success
    assert_output --partial "w1N:pH"
}

@test "A5g: an unreachable herdr is refused — never read as 'no agents'" {
    export AGENT_RC=7
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_failure
    assert_output --partial "herdr"
    run _job_file
    assert_failure
}

# ---------------------------------------------------------------------------
# A6 — --status and --cancel
# ---------------------------------------------------------------------------

@test "A6: --status reports a pending job, then its completed outcome" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_success

    sap --status
    assert_success
    assert_output --partial "pending"
    assert_output --partial "${_A}"

    _expire_job
    _dispatch_job
    assert_success

    sap --status
    assert_success
    assert_output --partial "completed"
    assert_output --partial "submitted"
}

@test "A6b: --status with no jobs says so instead of failing" {
    sap --status
    assert_success
    assert_output --partial "No"
}

@test "A6c: --cancel stops a pending job from ever dispatching" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_success
    local pid
    pid="$(_job_field '.pid')"

    sap --cancel
    assert_success
    run _job_field '.status'
    assert_output "cancelled"

    # The waiting process is gone, and a dispatch forced by hand still refuses.
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
    done
    run kill -0 "$pid"
    assert_failure

    # Even forced past its wake-up by hand, the job refuses: the dispatcher
    # re-reads the status rather than trusting the copy it slept on.
    : >"${_LOG}"
    _expire_job
    _dispatch_job
    assert_success
    run _prompt_calls
    assert_output "0"
}

@test "A6e: --cancel refuses to signal a pid the job no longer owns" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_success

    # The waiter died and its pid was recycled: the number in the job file now
    # belongs to a stranger, and a bare `kill` would signal it.
    local f victim
    f="$(_job_file)"
    kill "$(jq -r '.pid' "$f")" 2>/dev/null || true
    sleep 60 &
    victim=$!
    jq --argjson p "${victim}" '.pid = $p' "$f" >"${f}.t" && mv "${f}.t" "$f"

    sap --cancel
    assert_success

    run kill -0 "${victim}"
    assert_success
    kill "${victim}" 2>/dev/null || true

    # The status flip is what actually cancels; the kill is only cleanup.
    run jq -r '.status' "$f"
    assert_output "cancelled"
}

@test "A6d: --cancel takes a job id and leaves the other job pending" {
    _set_agents "${_A}|w1N:pH" "${_B}|w2N:pQ"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_success
    local first
    first="$(jq -r '.id' "$(_job_file)")"

    sap --at "$(_future_hhmm)" --agent-cwd "${_B}"
    assert_success

    sap --cancel "${first}"
    assert_success

    run jq -r '.status' "${_STATE_DIR}/${first}.json"
    assert_output "cancelled"

    local f other=""
    for f in "${_STATE_DIR}"/*.json; do
        case "$f" in *"${first}.json") continue ;; esac
        other="$f"
    done
    run jq -r '.status' "${other}"
    assert_output "pending"
}

@test "A6f: --cancel <id> refuses a job that already completed" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_success
    local id
    id="$(_job_field '.id')"

    _expire_job
    _dispatch_job
    assert_success
    run _job_field '.status'
    assert_output "completed"

    sap --cancel "${id}"
    assert_failure
    assert_output --partial "already completed"

    run _job_field '.status'
    assert_output "completed"
}

@test "A6g: --cancel <id> refuses a job that already failed" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_success
    local id
    id="$(_job_field '.id')"
    _expire_job

    export FAIL_PANE="w1N:pH"
    export FAIL_RC=1
    export FAIL_OUT="herdr: agent_prompt_stalled"
    _dispatch_job
    assert_failure
    run _job_field '.status'
    assert_output "failed"

    sap --cancel "${id}"
    assert_failure
    assert_output --partial "already failed"

    run _job_field '.status'
    assert_output "failed"
}

@test "A6h: --cancel <id> on a job with an unparseable status names it 'unknown'" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_success
    local id f
    id="$(_job_field '.id')"
    f="$(_job_file)"
    jq 'del(.status)' "$f" >"${f}.t" && mv "${f}.t" "$f"

    sap --cancel "${id}"
    assert_failure
    assert_output --partial "already unknown"

    run jq -r '.status' "$f"
    assert_output "null"
}

# ---------------------------------------------------------------------------
# A7 — a --wait that never settles
# ---------------------------------------------------------------------------

@test "A7: a stalled prompt is recorded as a failure for that target" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_success
    _expire_job

    # herdr's own word for "the agent never left its pre-submission state" —
    # the 2026-09-05 shape, the one outcome that really is a lost prompt.
    export FAIL_PANE="w1N:pH"
    export FAIL_RC=1
    export FAIL_OUT="herdr: agent_prompt_stalled"
    _dispatch_job
    assert_failure
    assert_output --partial "stalled"

    run _job_field '.results[0].outcome'
    assert_output "stalled"
    run _job_field '.status'
    assert_output "failed"
}

@test "A7a: a timeout after submission is delivery, not failure" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_success
    _expire_job

    # The state change already happened (otherwise herdr would have said
    # `agent_prompt_stalled`), so the prompt landed — the turn is simply still
    # running when the bound elapses. Reporting that as a failed injection
    # tells the user to re-send a prompt the agent is already working on.
    export FAIL_PANE="w1N:pH"
    export FAIL_RC=1
    export FAIL_OUT="herdr: timeout waiting for settled state"
    _dispatch_job
    assert_success

    run _job_field '.results[0].outcome'
    assert_output "submitted-working"
    run _job_field '.status'
    assert_output "completed"
}

@test "A7b: a refused herdr call is recorded as errored, not stalled" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_success
    _expire_job

    export FAIL_PANE="w1N:pH"
    export FAIL_RC=2
    export FAIL_OUT="herdr: no such pane"
    _dispatch_job
    assert_failure
    run _job_field '.results[0].outcome'
    assert_output "errored"
}

@test "A7c: a submitted target records the state herdr settled into" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_success
    _expire_job
    _dispatch_job
    assert_success
    run _job_field '.results[0].state'
    assert_output "idle"
    run _job_field '.results[0].pane_id'
    assert_output "w1N:pH"
}

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------

@test "V1: --at is required" {
    _set_agents "${_A}|w1N:pH"
    sap --agent-cwd "${_A}"
    assert_failure
    assert_output --partial "--at"
}

@test "V2: at least one --agent-cwd is required" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)"
    assert_failure
    assert_output --partial "--agent-cwd"
}

@test "V3: a malformed --at is rejected" {
    _set_agents "${_A}|w1N:pH"
    sap --at "25:00" --agent-cwd "${_A}"
    assert_failure
    sap --at "10:5" --agent-cwd "${_A}"
    assert_failure
    sap --at "later" --agent-cwd "${_A}"
    assert_failure
}

@test "V4: a past --at is rejected rather than scheduled for tomorrow" {
    _set_agents "${_A}|w1N:pH"
    # 00:00 is in the past for every run except one exact minute a day.
    if [ "$(date '+%H:%M')" = "00:00" ]; then
        skip "run started exactly at midnight"
    fi
    sap --at "00:00" --agent-cwd "${_A}"
    assert_failure
    assert_output --partial "past"
    run _job_file
    assert_failure
}

@test "V5: a --agent-cwd that is not a directory is rejected" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_WORK}/nope"
    assert_failure
    run _job_file
    assert_failure
}

@test "V6: an unknown option is rejected" {
    sap --at "23:59" --agent-cwd "${_A}" --bogus
    assert_failure
    assert_output --partial "--bogus"
}

@test "V7: --help exits 0 and documents the interface" {
    sap --help
    assert_success
    assert_output --partial "--agent-cwd"
    assert_output --partial "--dry-run"
    assert_output --partial "--status"
    assert_output --partial "--cancel"
}

# ---------------------------------------------------------------------------
# A9 — portability and state hygiene
# ---------------------------------------------------------------------------

@test "A9: --at resolves on a BSD/macOS date, which has no -d" {
    _set_agents "${_A}|w1N:pH"
    local at expected
    at="$(_future_hhmm)"
    expected="$(date -d "today ${at}" '+%s')"

    export BSD_DATE=1
    sap --at "${at}" --agent-cwd "${_A}"
    assert_success

    # Same instant as the GNU path, not merely "some number": a fallback that
    # inherited the current second would drift the wake-up by up to 59s.
    run _job_field '.at_epoch'
    assert_output "${expected}"
}

@test "A9b: the state directory is not readable by other accounts" {
    _set_agents "${_A}|w1N:pH"
    sap --at "$(_future_hhmm)" --agent-cwd "${_A}"
    assert_success

    # Job files carry the prompt text and the target cwd paths verbatim.
    run bash -c 'ls -ld "$1" | cut -c1-10' _ "${_STATE_DIR}"
    assert_output "drwx------"
}

# ---------------------------------------------------------------------------
# A8 — packaging
# ---------------------------------------------------------------------------

@test "A8: the script parses under bash and under zsh" {
    run bash -n "${SCRIPT}"
    assert_success
    if ! command -v zsh >/dev/null 2>&1; then
        skip "zsh not installed"
    fi
    run zsh -n "${SCRIPT}"
    assert_success
}

@test "A8b: the PATH symlink is registered in symlinks.conf" {
    run grep -F '${HOME}/.local/bin/schedule-agent-prompt|${HOME}/dotfiles/shell-common/tools/custom/schedule_agent_prompt.sh|' \
        "${DOTFILES_ROOT}/shell-common/config/symlinks.conf"
    assert_success
}

@test "A8c: the script is executable" {
    [ -x "${SCRIPT}" ]
}
