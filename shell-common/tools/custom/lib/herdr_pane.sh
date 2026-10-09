#!/bin/sh
# shell-common/tools/custom/lib/herdr_pane.sh
# herdr pane helpers shared by the two cron dispatchers (refactor F2):
# ../issue_watcher_cron.sh (`_iw_*`) and ../pr_merge_train_cron.sh (`_pmt_*`).
#
# Both scripts used to carry byte-identical copies of everything below under
# their own prefix. The few real differences — state subdir, lock message,
# idle-warning verb, pane noun in the account errors, settle constants — are
# arguments here, so each script keeps its own SSOT constants and passes them
# in. Script-level wrappers (`_iw_settle`, `_pmt_acquire_lock`, ...) bind those
# constants at call time.
#
# `#!/bin/sh` per the lib/ shebang rule, but only ever sourced by the two bash
# entrypoints: the `10#` base prefix in _hp_settle is bash arithmetic. Sourced
# explicitly — tools/custom is never auto-sourced. Needs ux_* (ux_lib) and jq
# at call time, not at source time.

# Echo the state dir <XDG_STATE_HOME>/<subdir>.
#   $1 = subdir, e.g. issue-watcher
#
# Nested defaults on purpose: under `set -u`, `${XDG_STATE_HOME:-$HOME/...}`
# still aborts with "HOME: unbound variable" when HOME itself is unset (a cron
# environment can be that bare), so HOME is never referenced unguarded.
_hp_state_dir() {
    printf '%s/%s' \
        "${XDG_STATE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.local/state}" \
        "$1"
}

# Extract one string field from JSON on stdin.
#   $1 = jq filter, e.g. '.result.pane.pane_id'.
#
# jq-only, and deliberately so: both dispatchers refuse to run without jq, so
# every caller here is downstream of that check. A hand-rolled awk/sed fallback
# would be unreachable code pretending to be a safety net. Always returns 0 — a
# malformed document reads as "no such field", which is what every caller
# already treats it as.
_hp_json_value() {
    jq -r "${1} // empty" 2>/dev/null || return 0
}

# First string value of a flat key anywhere in the document. `herdr tab create`
# and `herdr workspace create` both answer with a pane, but nest it under
# different parents (`.result.pane` vs `.result.root_pane`), and the CLI is
# free to add another. Keying on the leaf name rather than the path keeps this
# working across both shapes without a per-command filter table.
# The key travels as a jq *argument*, never as interpolated program text: a
# caller-supplied string spliced into the filter would be a jq syntax error at
# best and arbitrary jq at worst (PR #1447 agy review).
_hp_json_first() {
    jq -r --arg k "$1" \
        '[.. | objects | .[$k]? // empty] | map(select(type == "string")) | first // empty' \
        2>/dev/null || return 0
}

# Echo epoch seconds, or nothing when the clock is unreadable.
_hp_now() {
    local _now
    _now=$(date +%s 2>/dev/null) || return 0
    case "${_now}" in
    '' | *[!0-9]*) return 0 ;;
    esac
    printf '%s' "${_now}"
}

# Single-instance guard for one cron tick.
#   $1 = state dir, $2 = lock basename, $3 = tick name for the skip warning
#
# A cron tick can fire while the previous one is still blocked in `herdr agent
# prompt --wait`; without a lock both would observe the same work and both act.
# Deliberately non-blocking: a skipped tick just retries on the next period.
# Returns non-zero only when another tick holds the lock; a missing flock or an
# unusable state dir soft-degrades to "no protection" rather than failing.
# Must run in the caller's shell (not a subshell): fd 9 has to outlive it.
_hp_acquire_lock() {
    local _dir="$1" _lock
    _lock="${_dir}/$2"

    if ! command -v flock >/dev/null 2>&1; then
        ux_warning "flock not found — running without single-instance protection"
        return 0
    fi

    if ! mkdir -p "${_dir}" 2>/dev/null; then
        ux_warning "Cannot create state directory (${_dir}) — running without single-instance protection"
        return 0
    fi

    # The 2>/dev/null must be scoped to the group, not attached to `exec`:
    # `exec 9>FILE 2>/dev/null` applies *both* redirections permanently, muting
    # the whole script's stderr — every later ux_error would vanish from the
    # cron log. The group restores fd 2 on exit while fd 9 persists.
    if ! { exec 9>"${_lock}"; } 2>/dev/null; then
        ux_warning "Cannot open lock file (${_lock}) — running without single-instance protection"
        return 0
    fi

    if ! flock -n 9; then
        ux_warning "another $3 tick is already running — skip"
        return 1
    fi
}

# CLAUDE_CONFIG_DIR for a dispatcher's pane (issue #571 / #1393) — the same
# account routing `claude_yolo` applies. herdr's `--kind` enum has no
# `claude-yolo`, so the two effects of that wrapper are reproduced instead:
# this env var, plus the `-- --dangerously-skip-permissions` tail in
# _hp_agent_start.
#   $1 = shell-common dir (claude.sh is sourced from it)
#   $2 = pane noun for the error wording ("watcher", "merge-train")
#   $3 = where the account hints go: `stderr`, or `stdout` — issue_watcher's
#        historical stream, which lands them in the caller's discarded capture
# Exit:
#   0  directory echoed on stdout
#   1  unknown account / missing directory (fail-fast, message already printed)
#   2  HOME unset — nothing to route against; caller degrades to no --env
#
# One narrow exception to the fail-fast (PR #1395 review): a user who never ran
# `claude-accounts setup` has no CLAUDE_ENABLED_ACCOUNTS whitelist at all and
# never named an account, so `_claude_resolve_account` rejects even the implicit
# `personal` default. Before #1393 the pane ran bare `claude` and worked for
# them; routing must not turn that into a hard failure, so ~/.claude is used
# when it exists. Every other resolution failure still fails fast — an explicit
# CLAUDE_DEFAULT_ACCOUNT whose dir is missing, or a non-empty whitelist that
# does not list the account, are real misconfigurations and silently switching
# accounts there would route the pane at the wrong credentials.
#
# claude.sh is sourced inside a subshell on purpose:
#   - its interactive guard (`case $- in *i*`) defines nothing at all in a
#     non-interactive cron run unless DOTFILES_FORCE_INIT is exported first;
#   - the subshell keeps its ~40 functions and aliases out of the caller.
# ux_* diagnostics go to stderr (ux_error) or are routed away from stdout, so
# only the resolved directory reaches the caller's capture on success.
_hp_resolve_config_dir() {
    [ -n "${HOME:-}" ] || return 2

    (
        _shell_common="$1"
        _pane="$2"
        # fd 4 carries the account hints; see $3 above.
        if [ "$3" = "stderr" ]; then
            exec 4>&2
        else
            exec 4>&1
        fi

        # Captured before claude.sh is sourced: the *caller's* environment is
        # what says whether the single-account fallback below applies.
        # set-but-empty CLAUDE_DEFAULT_ACCOUNT counts as explicitly set.
        _enabled="${CLAUDE_ENABLED_ACCOUNTS:-}"
        _default_set=0
        [ -z "${CLAUDE_DEFAULT_ACCOUNT+x}" ] || _default_set=1

        DOTFILES_FORCE_INIT=1
        export DOTFILES_FORCE_INIT

        # shellcheck source=/dev/null
        . "${_shell_common}/tools/integrations/claude.sh" >&2 || {
            ux_error "Cannot load ${_shell_common}/tools/integrations/claude.sh — CLAUDE_CONFIG_DIR unresolvable."
            exit 1
        }

        # Internal-PC single-account override (issue #571): the multi-account
        # layout is off there, so this branch must run before account
        # resolution — an empty CLAUDE_ENABLED_ACCOUNTS must not fail the tick.
        if [ "$(_dotfiles_setup_mode)" = "internal" ]; then
            _cfg_dir="$HOME/.claude"
        else
            _account="${CLAUDE_DEFAULT_ACCOUNT:-personal}"
            _cfg_dir=$(_claude_resolve_account "${_account}") || {
                # No multi-account opt-in at all *and* no account was asked
                # for — the pre-#1393 single-account user. ux_* writes to
                # stdout, which this subshell reserves for the resolved path.
                if [ -z "${_enabled}" ] && [ "${_default_set}" -eq 0 ] &&
                    [ -d "$HOME/.claude" ]; then
                    ux_warning "CLAUDE_ENABLED_ACCOUNTS not configured — falling back to \$HOME/.claude (single-account mode)." >&2
                    ux_info "Run 'claude-accounts setup' to opt into multi-account routing." >&2
                    printf '%s' "$HOME/.claude"
                    exit 0
                fi
                ux_error "Unknown claude account: ${_account} — cannot set CLAUDE_CONFIG_DIR for the ${_pane} pane."
                ux_info "Available: $(_claude_resolve_account --list | tr '\n' ' ')" >&4
                exit 1
            }
        fi

        if [ ! -d "${_cfg_dir}" ]; then
            ux_error "Claude account directory missing: ${_cfg_dir} — cannot bootstrap the ${_pane} pane."
            ux_info "Run: claude-accounts setup" >&4
            exit 1
        fi

        # A directory that exists is not an account that is logged in
        # (issue #1561) — a logged-out pane opens on `Not logged in · Run
        # /login` and drops every keystroke, which the dispatcher then reports
        # as `agent_prompt_stalled`, a symptom that names neither the account
        # nor the cause. Fail here instead, where the account is still in hand.
        # The rule for what counts as "logged in" lives in claude.sh, sourced
        # above; only the wording of the failure is this helper's business.
        if ! _claude_account_logged_in "${_cfg_dir}"; then
            ux_error "Claude account not logged in: ${_cfg_dir}/.credentials.json is missing, empty, or not valid JSON — the pane would open on 'Not logged in' and every prompt would stall."
            ux_info "Run: claude-accounts status   (then log that account in)" >&2
            exit 1
        fi

        printf '%s' "${_cfg_dir}"
    )
}

# Run a herdr *create* command with the flags every such call shares:
#   _hp_herdr_create <config-dir> <cwd> <label> <herdr-subcommand-word>...
# e.g. `_hp_herdr_create "$_cfg" "$_cwd" "$_label" tab create --workspace ws-1`.
#
# One owner on purpose. The `--env CLAUDE_CONFIG_DIR=` tail is the invariant
# the issue watcher's rate-limit gate rests on — one account, one quota — so a
# new creation call site must not be able to quietly omit it. An empty
# <config-dir> omits it (HOME unset: no routing). herdr's own JSON goes to
# stdout; the exit code is herdr's.
_hp_herdr_create() {
    local _cfg="$1" _cwd="$2" _label="$3"
    shift 3

    set -- "$@" --cwd "${_cwd}" --label "${_label}" --no-focus
    [ -z "${_cfg}" ] || set -- "$@" --env "CLAUDE_CONFIG_DIR=${_cfg}"

    herdr "$@" 2>/dev/null
}

# Echo the workspace id whose label is <2>, creating it against cwd <3> when no
# such workspace exists.
#   $1 = config dir passed through to _hp_herdr_create
# Label-matched rather than persisted: the herdr server is the SSOT for what is
# open, and a state file would only drift from it.
_hp_workspace_for_label() {
    local _cfg="$1" _label="$2" _cwd="$3" _json _ws

    _json=$(herdr workspace list 2>/dev/null) || _json=""
    _ws=$(printf '%s' "${_json}" | jq -r --arg l "${_label}" '
        [ .result.workspaces[]? | select(.label == $l) | .workspace_id ] | first // empty
    ' 2>/dev/null) || _ws=""

    if [ -n "${_ws}" ]; then
        printf '%s' "${_ws}"
        return 0
    fi

    _json=$(_hp_herdr_create "${_cfg}" "${_cwd}" "${_label}" workspace create) || _json=""
    _ws=$(printf '%s' "${_json}" | _hp_json_first workspace_id)
    [ -n "${_ws}" ] || return 1
    printf '%s' "${_ws}"
}

# Echo the agent status (idle|working|blocked|done|unknown). Returns non-zero
# when herdr itself rejects the query (agent missing / pane closed).
_hp_agent_status() {
    local _json _rc=0
    _json=$(herdr agent get "$1" 2>/dev/null) || _rc=$?
    [ "${_rc}" -eq 0 ] || return 1
    printf '%s' "${_json}" | _hp_json_value '.result.agent.agent_status'
}

# Start claude in pane <2> under agent name <1>; herdr's stderr goes to file <3>.
#
# `-- ARG...` is passed through to the pane's claude invocation. Unattended
# cron ticks must never stop on a permission-approval prompt (issue #1393).
#
# stderr goes to the file named by $3 rather than /dev/null (#1525, the same
# defect class as #1445/#1458): herdr is free to answer on either stream and in
# cron it answers on stderr, so discarding it threw away the one sentence that
# named the failure — `agent_pane_busy`. stdout stays on the pipe because the
# caller reads `.error.code` off it, which is why this is a file and not `2>&1`.
_hp_agent_start() {
    herdr agent start "$1" --kind claude --pane "$2" \
        -- --dangerously-skip-permissions 2>"$3"
}

# Echo the herdr error code behind a failed call: <1> is herdr's stdout, <2> the
# file its stderr was captured to. stdout first, stderr as the fallback. Both
# are consulted because the stream herdr picks is not ours to choose — and in
# production it picked the one nobody was reading. Echoes nothing when neither
# stream carried a parsable error document.
_hp_herdr_error_code() {
    local _json="$1" _errfile="$2" _code

    _code=$(printf '%s' "${_json}" | _hp_json_value '.error.code')
    if [ -z "${_code}" ] && [ -s "${_errfile}" ]; then
        _code=$(_hp_json_value '.error.code' <"${_errfile}")
    fi
    printf '%s' "${_code}"
}

# Wait for a freshly started agent to report idle before prompting it.
#   $1 = agent, $2 = max checks, $3 = gap between checks (0 = none),
#   $4 = what happens next, for the warning ("dispatching", "prompting")
#
# `herdr agent start` only confirms the pane looks interactive — a claude
# process can have drawn its prompt box before its key-input loop accepts
# Enter, so the command is typed but never submitted and herdr's fixed 5s stall
# check fires `agent_prompt_stalled` (issue #1399). Every dispatched pane is
# cold, so every one gets this grace (PR #1447 codex review).
#
# This is a *health* check, not the settle wait. A live agent answers `idle` on
# the first poll, so the normal path leaves here in ~0s — the poll budget only
# bounds how long a missing agent or a closed pane can hold the tick, and
# hitting that budget still proceeds because the caller's stall recovery is the
# second line of defence. The wait that actually makes the prompt land is
# _hp_settle, which runs after this (issue #1560).
_hp_wait_for_idle() {
    local _agent="$1" _max="$2" _gap="$3" _next="$4" _i=0 _status _get_failed=0 _detail=""

    while [ "${_i}" -lt "${_max}" ]; do
        if _status=$(_hp_agent_status "${_agent}"); then
            [ "${_status}" != "idle" ] || return 0
        else
            _get_failed=$((_get_failed + 1))
        fi
        _i=$((_i + 1))
        [ "${_i}" -lt "${_max}" ] || break
        [ "${_gap}" = "0" ] || sleep "${_gap}"
    done

    # Health-check failures (agent missing / pane closed) and a merely slow
    # `starting` pane both land here — surface the failure count so a genuinely
    # gone agent does not read as "just slow" (PR #1400 codex review).
    # Counted in checks, not seconds: the gap between them is overridable, so a
    # wall-clock figure here would be wrong in exactly the runs that read it.
    [ "${_get_failed}" -eq 0 ] ||
        _detail=" (${_get_failed}/${_max} health-check failures)"
    ux_warning "Agent ${_agent} never reported idle in ${_max} checks${_detail} — ${_next} anyway."
}

# Echo the tail of an agent's pane, or nothing when it cannot be read.
#   $1 = agent name, $2 = lines to read
#
# `--format text` gives the pane as plain lines. herdr answers its error
# document as JSON on *stdout* with exit 0 when the target is gone (#1444), so
# an unreadable pane has to be recognised by parsing rather than by the exit
# code. Shared by the settle poll and the issue watcher's limit evidence
# (#1444) — the callers differ only in how many lines they need.
#
# Always returns 0 and simply echoes nothing when there is no text: every
# caller reads "no text" as "nothing to conclude", never as a failure.
_hp_pane_text() {
    local _text
    _text=$(herdr agent read "$1" --lines "$2" \
        --format text 2>/dev/null) || return 0
    [ -z "$(printf '%s' "${_text}" | _hp_json_value '.error.code')" ] || return 0
    printf '%s' "${_text}"
}

# True when three consecutive pane reads say the agent is listening.
#   $1 = this read, $2 = the previous one, $3 = the one before that,
#   $4 = the not-ready mark (the login banner)
#
# Three-in-a-row, not two (PR #1611 review, codex, 5th pass): two identical
# reads only proves the *render* stopped changing between one poll gap, and
# the render settling is not evidence the key-input loop has too — that gap
# is exactly what #1560 exists to describe, and an active probe to prove
# input-readiness directly turned out not to be viable (state_change_seq did
# not move for typed-but-unsubmitted keystrokes in a live herdr 0.7.5 test —
# it tracks submission-level events, not raw terminal content, so there is no
# cheap corroborating signal available pre-prompt). A third agreeing frame
# does not *prove* input-readiness either, but it does raise the bar past a
# single lucky poll gap, cutting the odds of firing into a merely-rendered,
# not-yet-listening pane without adding an unverified new mechanism.
#
# Four conditions, each earning its place. Non-empty: a pane that has drawn
# nothing yet reads empty, and so does one herdr refused to read, so "empty
# three times" is the opposite of evidence. Identical across all three: a TUI
# still painting changes somewhere in that window. Not the login banner: that
# frame is perfectly stable and means claude is up and unusable (#1561) — the
# case a state_change_seq comparison cannot see at all, which is why the pane
# text is the signal here and the counter stays with the issue watcher's
# _iw_stall_recover_via_enter.
#
# Known gap (PR #1611 review, codex, 2nd/3rd pass): "any stable, non-empty,
# non-`Not logged in` text" is still not *proven* ready — only proven not to
# be that one banner, and not proven to be the input loop rather than the
# render loop. A different steady pre-ready or error frame could still
# false-positive. Not fixed here: the only evidence available is what herdr
# 0.7.5 has actually been observed to show (#1560's measurement, and PR
# #1611's own live probing), and this repo has no fixture for a second
# stable-but-unready frame to design against. The cap (13s) is the backstop
# either way — a false-positive settle is not a new failure mode, just a
# prompt sent slightly earlier than warranted.
_hp_pane_settled() {
    [ -n "$1" ] || return 1
    [ "$1" = "$2" ] && [ "$2" = "$3" ] || return 1
    case "$1" in
    *"$4"*) return 1 ;;
    esac
    return 0
}

# Echo how many settle polls fit in <1> seconds at <2> apart — ceil(seconds /
# gap), floored at 2 whenever the gap is real. The pre-#1611-review shape
# hardcoded this to the seconds themselves, silently assuming a 1s gap: a 0.5
# gap then hit the count bound at 6.5s of real sleeping, cutting the wait short
# of the cap it was supposed to honour, while a gap *above* 1s (e.g. 4)
# overshot it several times over — agy and codex both flagged the same root
# cause from opposite sides in the PR #1611 review.
#
# The zero/negative check lives inside awk, not a shell `case`, so it catches
# every numeral spelling of "no delay" (`0`, `00`, `.0`, `0.000`, a stray
# `-1`) — a `case 0 | 0.0 | 0.00)` pattern missed `.0`/`0.000` and fell
# through to a fatal awk division-by-zero, leaving `_max_polls` empty and the
# caller's `[ -lt ]` broken (agy, PR #1611 review, second pass). `LC_ALL=C`
# pins `.` as the decimal point regardless of the caller's locale — a
# comma-decimal locale would otherwise mis-parse a fractional gap.
# `0` itself keeps the pre-scaling answer (the seconds themselves): division
# by zero has no answer, and a `0` gap already means "no real delay", so
# "poll up to N times" is the only sense left to give the cap — and it is
# also the shape the bats suites' stubbed `sleep` relies on to stay fast (a
# wall-clock-only bound would make a "never settles" fixture actually wait
# out real seconds, timeout stub or not).
#
# The floor at 2 (once the gap is real) is what keeps a gap at or above the
# cap itself (a 13s gap, say) from producing exactly one read and zero sleeps
# — ceil(13/13)=1 alone would give up instantly instead of waiting the one
# real gap the override asked for (agy, PR #1611 review, second pass).
_hp_settle_max_polls() {
    local _seconds="$1" _gap="$2"
    LC_ALL=C awk -v s="${_seconds}" -v g="${_gap}" \
        'BEGIN {
            if (g <= 0) { print s; exit }
            n = s / g; i = int(n); if (i < n) i++
            if (i < 2) i = 2
            # A gap far below 1s (a fat-fingered override, e.g. 0.001) would
            # otherwise scale into thousands of herdr round trips for one
            # dispatch — a self-inflicted but real resource-exhaustion risk
            # (agy, PR #1611 review, 4th pass). 1000 is far above any gap this
            # repo ships or documents (default 1, the widest override tested
            # is 13) and still bounds the worst case to a fixed, small budget.
            if (i > 1000) i = 1000
            print i
        }'
}

# Wait for a freshly launched pane to look ready before typing into it
# (issue #1560; polled since #1570).
#   $1 = agent, $2 = cap in seconds (0 = no wait), $3 = poll gap,
#   $4 = lines per pane read, $5 = not-ready mark
#
# Separate from _hp_wait_for_idle on purpose: that one asks herdr for the
# agent's *status*, which reports "not working" and says nothing about the
# key-input loop. This one reads the pane's own text, which does tell a claude
# still coming up from one sitting at a settled prompt.
#
# Always succeeds and always ends in a prompt attempt — a settle that could
# fail would skip the prompt it exists to protect, which is a worse outcome
# than a prompt sent slightly too early. Reaching the cap with no ready signal
# therefore warns and proceeds, which is exactly the pre-#1570 behaviour: this
# poll can only make the wait *shorter*, never turn it into a new failure mode.
#
# Bounded twice over, both against the cap: by a poll count scaled to the poll
# gap (_hp_settle_max_polls, above — the primary bound in practice), and by
# wall clock, which is what keeps a poll gap that runs slower than expected (a
# loaded herdr, a slow read) from overrunning the cap even when the count has
# not yet been exhausted.
#
# Like any poll, the cap holds to within one gap — no *read* happens past the
# deadline, but a sleep already under way can carry the return up to one gap
# beyond it. At the default 1s gap that is 13s becoming at most ~14s, still
# bounded and still no worse than the unconditional 13s this replaced.
_hp_settle() {
    local _agent="$1" _seconds="$2" _gap="$3" _lines="$4" _mark="$5"
    local _i=0 _prev="" _prev2="" _text _now _deadline="" _max_polls

    [ "${_seconds}" = "0" ] && return 0
    # A fractional cap cannot bound a poll count. It predates #1570 and still
    # means the flat wait it always meant rather than being refused.
    case "${_seconds}" in
    *[!0-9]*)
        sleep "${_seconds}"
        return 0
        ;;
    esac

    _max_polls=$(_hp_settle_max_polls "${_seconds}" "${_gap}")

    _now=$(_hp_now)
    # `10#` forces base 10: bash arithmetic otherwise reads a leading-zero
    # numeral as octal, so a cap of 08/09 aborted the whole tick with
    # "value too great for base" and 01-07 silently computed the (here
    # harmless, but wrong) octal value instead of the decimal one someone
    # typed (codex, PR #1611 review, second pass — a genuine regression: the
    # pre-#1611-review code only ever passed this value to `sleep`, which has
    # no such reading).
    # shellcheck disable=SC3052 # bash-only callers; see the file header.
    [ -z "${_now}" ] || _deadline=$((_now + 10#${_seconds}))

    while [ "${_i}" -lt "${_max_polls}" ]; do
        # Checked before the read, not after the sleep: a poll gap wider than
        # the cap would otherwise let the last read land past the cap it is
        # capped by. A clock that stopped being readable mid-wait leaves the
        # (now correctly-scaled) count as the only bound, which is what it is
        # there for.
        if [ -n "${_deadline}" ]; then
            _now=$(_hp_now)
            [ -z "${_now}" ] || [ "${_now}" -lt "${_deadline}" ] || break
        fi
        _text=$(_hp_pane_text "${_agent}" "${_lines}")
        ! _hp_pane_settled "${_text}" "${_prev}" "${_prev2}" "${_mark}" || return 0
        _prev2="${_prev}"
        _prev="${_text}"
        _i=$((_i + 1))
        [ "${_i}" -lt "${_max_polls}" ] || break
        [ "${_gap}" = "0" ] || sleep "${_gap}"
    done

    ux_warning "Agent ${_agent} pane never settled within ${_seconds}s — prompting anyway."
    return 0
}
