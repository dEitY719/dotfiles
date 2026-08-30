#!/bin/bash
# shell-common/tools/custom/session_doctor_cron.sh
# session-doctor cron 디스패처 — 1회 tick (issue #1581).
#
# cron 이 매분 이 스크립트를 호출하면 tick 1회를 수행한다. tick 은 herdr 가
# 관리하는 모든 pane 을 훑어, 마지막 assistant 턴이 정상 종료가 아니라 API 에러로
# 끊긴 채 `idle` 로 멈춰 있는 탭을 찾아 그 탭 자신에게 `/devx:restart` 를 한 턴으로
# 넣어 준다. 다섯 단계뿐이다:
#   1) 이번 tick 이 유일한 tick 인가 (flock, NF-1)
#   2) herdr agent list — tab_id / agent_status / cwd (F-2)
#   3) 각 탭의 cwd 에 대응하는 최신 Claude Code transcript 의 마지막
#      assistant 이벤트 판정 (F-3/F-4, lib/session_doctor_detect.sh)
#   4) 후보마다 `herdr agent prompt <tab_id> "/devx:restart" --wait` (F-5)
#   5) 탭별 상태 기록 — 감지 시각 / 누적 주입 횟수 / 마지막 주입 시각 (F-6)
#
# NF-2 — 이 스크립트는 감지와 "텍스트 주입"만 한다. `devx:restart` 스킬을 대신
# 실행하지 않는다. 그 스킬은 설계상 같은 세션에서만 의미가 있고
# (claude/skills/devx-restart/SKILL.md), 중단 지점을 아는 것은 그 세션 자신뿐이다.
# 여기서 하는 일은 그 세션의 입력창에 한 줄을 타이핑해 주는 것과 정확히 같고,
# 재개할지 말지는 세션이 스스로 정한다.
#
# GitHub 에 어떤 요청도 하지 않는다 — 로컬 파일과 herdr CLI 만 본다.
#
# Usage: session_doctor_cron.sh [--dry-run] | [-h|--help|help]

set -u

# Initialize common tools environment (DOTFILES_ROOT/SHELL_COMMON + ux_lib)
. "$(dirname "$0")/init.sh" || exit 1

# init.sh returns early under DOTFILES_TEST_MODE=1 (and before it exports
# SHELL_COMMON), so resolve shell-common from this script's own location as a
# fallback — the same two-tier resolution issue_watcher_cron.sh and
# pr_merge_train_cron.sh use.
_SD_SHELL_COMMON="${SHELL_COMMON:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Same early return means ux_* can still be undefined here — every output path
# below depends on it.
if ! type ux_header >/dev/null 2>&1; then
    if [ -f "${_SD_SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
        # shellcheck source=/dev/null
        . "${_SD_SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
    fi
fi

# Detection (F-3/F-4) and per-tab state (F-6). Hard failures, not
# degradations: without either one the tick has no way to tell a stuck session
# from a finished one, and a tick that guessed would type into healthy panes.
for _sd_lib in session_doctor_detect session_doctor_state; do
    if [ ! -f "${_SD_SHELL_COMMON}/tools/custom/lib/${_sd_lib}.sh" ]; then
        ux_error "${_sd_lib}.sh not found under ${_SD_SHELL_COMMON}/tools/custom/lib — cannot scan for stuck sessions."
        exit 1
    fi
    # shellcheck source=/dev/null
    . "${_SD_SHELL_COMMON}/tools/custom/lib/${_sd_lib}.sh" || exit 1
done
unset _sd_lib

# ============================================================
# Constants
# ============================================================

# The one thing this tick ever types. A literal, not a computed string: NF-2's
# whole point is that the tab decides what to do with it.
_SD_PROMPT="/devx:restart"

# `herdr agent prompt --wait` 한 번의 상한. `--wait` 는 프롬프트가 *접수* 될
# 때까지만 기다린다 — 재개된 세션은 몇 분을 더 돌 수 있고, 그것을 기다리지는
# 않는다. cron 주기(1분)보다 짧게 잡아, 느린 주입 하나가 다음 tick 을 통째로
# 굶기지 않게 한다. 겹침 자체는 flock 이 막는다.
_SD_TIMEOUT_MS="${SESSION_DOCTOR_TIMEOUT_MS:-45000}"

# Set by --dry-run: report what the tick would inject, mutate nothing.
_SD_DRY_RUN=0

# Field separator for the `herdr agent list` rows below.
_SD_TAB=$(printf '\t')

# ============================================================
# Preconditions — one tick at a time (NF-1)
# ============================================================

# The tick lock, mirroring _pmt_acquire_lock. A missing flock, an uncreatable
# state dir and an unopenable lock file all degrade to "run without the
# guarantee" rather than skipping the tick: the worst case is two ticks
# injecting into the same tab, which the cap still bounds, while skipping
# would leave a stuck session stuck.
_sd_acquire_lock() {
    local _dir _lock

    _dir=$(session_doctor_state_dir)
    _lock=$(session_doctor_tick_lock)

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
        # No output: a tick that overlaps its predecessor is the normal
        # outcome of a */1 schedule whose predecessor is mid-injection, not an
        # incident worth a line every minute.
        return 1
    fi
}

# ============================================================
# F-2 — every herdr-managed pane
# ============================================================

# Emit `<tab_id><TAB><agent_status><TAB><cwd>` for every agent herdr knows
# about. Non-zero when herdr could not be asked at all — the caller then ends
# the tick silently and the next one retries (AC-6). A herdr that answers
# nothing must not read as "no panes": that is indistinguishable from a
# healthy machine with nothing running, and the difference matters only for
# the log, which is why both end the tick the same quiet way.
_sd_agent_rows() {
    local _json

    _json=$(herdr agent list 2>/dev/null) || return 1
    [ -n "${_json}" ] || return 1

    # Rows missing either identifying column are dropped here rather than in
    # the loop, and an unreported status becomes the literal `unknown`, so no
    # field the loop reads can ever be empty. That is not cosmetic: a tab is
    # an IFS whitespace character, so `read` collapses two adjacent tabs into
    # one, and a single empty middle field would shift `cwd` into `status`.
    printf '%s' "${_json}" | jq -r '
        if (.result.agents | type) == "array"
        then .result.agents[]?
             | select(((.tab_id // "") != "") and ((.cwd // "") != ""))
             | [ .tab_id,
                 (if ((.agent_status // "") == "") then "unknown" else .agent_status end),
                 .cwd ]
             | @tsv
        else error("no agent list")
        end
    ' 2>/dev/null || return 1
}

# ============================================================
# F-5 — inject the prompt, and only then count it
# ============================================================

# Type `/devx:restart` into tab <1>. Runs in a background subshell (see the
# call site), so the tick's tabs are prompted concurrently rather than one
# 45-second timeout after another.
#
# The state write lives here, after herdr has accepted the prompt, and that
# ordering is the requirement: an injection herdr refused (a busy pane, a tab
# that closed between the scan and now) did not happen, so it must not spend a
# retry. Warning only, budget untouched, next tick tries again.
_sd_inject() {
    local _tab _stamp

    _tab="$1"

    if ! herdr agent prompt "${_tab}" "${_SD_PROMPT}" \
        --wait --timeout "${_SD_TIMEOUT_MS}" >/dev/null 2>&1; then
        ux_warning "herdr agent prompt failed for tab ${_tab} — nothing was injected, and its retry budget is untouched."
        return 1
    fi

    _stamp=$(_sd_now)
    session_doctor_record_injection "${_tab}" "${_stamp}" ||
        ux_warning "Could not record the injection for tab ${_tab} — its cap may under-count."
    ux_success "Injected ${_SD_PROMPT} into tab ${_tab}."
}

# ISO-8601 UTC, the stamp format aicron's own state file uses.
_sd_now() {
    date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf ''
}

# ============================================================
# The tick
# ============================================================

_SD_SCANNED=0
_SD_STUCK=0
_SD_LAUNCHED=0
_SD_CAPPED=0

# Decide and act on one pane: <1> tab id, <2> agent_status, <3> cwd.
# Always returns 0 — a pane this tick cannot classify is simply not a
# candidate, and must not end the scan for the panes after it.
_sd_visit_pane() {
    local _tab _status _cwd _count _now

    _tab="$1"
    _status="$2"
    _cwd="$3"

    [ -n "${_tab}" ] || return 0
    _SD_SCANNED=$((_SD_SCANNED + 1))

    # F-4's first half. Anything else — working, blocked, or a status this
    # script does not know — is a session that is either fine or busy, and
    # typing into a busy pane is exactly the harm NF-2 is written against.
    [ "${_status}" = "idle" ] || return 0

    # A pane whose directory is gone carries herdr's own " (deleted)" suffix.
    # It has no live transcript to judge and no session worth restarting.
    case "${_cwd}" in
    '' | *' (deleted)') return 0 ;;
    esac

    # F-4's second half, and the error case "no matching transcript → exclude
    # from candidates": every unknown inside this call is non-zero.
    session_doctor_cwd_is_stuck "${_cwd}" || return 0

    _SD_STUCK=$((_SD_STUCK + 1))
    _now=$(_sd_now)

    if [ "${_SD_DRY_RUN}" -eq 1 ]; then
        _count=$(session_doctor_tab_injections "${_tab}")
        ux_bullet "${_tab} (${_cwd}) — stuck on an API error, ${_count}/${SESSION_DOCTOR_CAP} injections used"
        return 0
    fi

    session_doctor_mark_detected "${_tab}" "${_now}" ||
        ux_warning "Could not record the detection for tab ${_tab}."

    # F-7. The budget is spent, so this tab stops being helped and starts
    # being reported instead — `aicron status session-doctor` and the state
    # file are where a human picks it up from here.
    _count=$(session_doctor_tab_injections "${_tab}")
    if [ "${_count}" -ge "${SESSION_DOCTOR_CAP}" ]; then
        session_doctor_mark_capped "${_tab}" "${_now}" ||
            ux_warning "Could not record the cap for tab ${_tab}."
        ux_warning "Tab ${_tab} (${_cwd}) is stuck on an API error but has spent its injection budget (${_count}/${SESSION_DOCTOR_CAP}) — no further ${_SD_PROMPT}; restart it by hand."
        _SD_CAPPED=$((_SD_CAPPED + 1))
        return 0
    fi

    ux_info "Tab ${_tab} (${_cwd}) is idle after an API error — injecting ${_SD_PROMPT} (attempt $((_count + 1))/${SESSION_DOCTOR_CAP})."
    _sd_inject "${_tab}" &
    _SD_LAUNCHED=$((_SD_LAUNCHED + 1))
    return 0
}

# ============================================================
# Usage
# ============================================================

_sd_usage() {
    ux_header "session_doctor_cron"
    ux_info "Usage: session_doctor_cron.sh [--dry-run] | [-h|--help|help]"
    ux_info "Runs one session-doctor tick: find idle tabs whose last turn died on an API error, inject ${_SD_PROMPT}."
    ux_bullet "options"
    ux_bullet_sub "--dry-run          list the tabs this tick would inject, change nothing"
    ux_bullet_sub "                   (takes no lock, injects nothing, writes no state)"
    ux_bullet_sub "-h, --help, help   show this help"
    ux_bullet "tick"
    ux_bullet_sub "1. flock — one tick at a time"
    ux_bullet_sub "2. herdr agent list — every pane's tab_id / agent_status / cwd"
    ux_bullet_sub "3. the pane's newest ~/.claude*/projects/<slug>/*.jsonl — last assistant event"
    ux_bullet_sub "4. herdr agent prompt <tab_id> \"${_SD_PROMPT}\" --wait"
    ux_bullet "candidate (all of these, or the tab is left alone)"
    ux_bullet_sub "agent_status is idle — a working or blocked pane is never typed into"
    ux_bullet_sub "the last assistant event is Claude Code's synthetic API-error turn"
    ux_bullet_sub "  (isApiErrorMessage, or model \"<synthetic>\" plus the error text)"
    ux_bullet_sub "no transcript, no readable event, no herdr — not a candidate, never a guess"
    ux_bullet "injection budget"
    ux_bullet_sub "${SESSION_DOCTOR_CAP} per tab (SESSION_DOCTOR_CAP), cumulative and never reset"
    ux_bullet_sub "a refused injection does not spend one — nothing was typed, so the next tick retries"
    ux_bullet_sub "past the budget the tab is reported, not helped — restart it by hand"
    ux_bullet "scope (NF-2)"
    ux_bullet_sub "this job only types ${_SD_PROMPT} into the tab's own session"
    ux_bullet_sub "it never runs devx:restart itself — that skill is same-session by design"
    ux_bullet "state"
    ux_bullet_sub "\${XDG_STATE_HOME:-\$HOME/.local/state}/session-doctor/state.json   (per tab)"
    ux_bullet_sub "\${XDG_STATE_HOME:-\$HOME/.local/state}/session-doctor/.lock         (tick lock)"
    ux_bullet "crontab"
    ux_bullet_sub "*/1 * * * * /path/to/session_doctor_cron.sh >> ~/.local/state/session-doctor/cron.log 2>&1"
}

# ============================================================
# Main
# ============================================================

main() {
    local _rows _tab _status _cwd _dir

    while [ "$#" -gt 0 ]; do
        case "$1" in
        -h | --help | help)
            _sd_usage
            exit 0
            ;;
        --dry-run)
            _SD_DRY_RUN=1
            shift
            ;;
        *)
            ux_error "Unknown option: $1"
            ux_info "Run 'session_doctor_cron.sh --help' for usage."
            exit 1
            ;;
        esac
    done

    # jq parses both halves of this tick — herdr's agent list and every
    # transcript event — so there is no reduced mode to fall back to. Reported
    # rather than silent (a missing jq is a machine that needs fixing, not a
    # transient), but exit 0 all the same: cron mails on any non-zero exit and
    # a mail a minute helps nobody.
    if ! command -v jq >/dev/null 2>&1; then
        ux_error "jq not found in PATH — cannot inspect herdr panes or session transcripts."
        exit 0
    fi

    # AC-6 — herdr missing is a silent skip. On a machine where herdr is not
    # installed this job would otherwise write 1440 identical lines a day.
    command -v herdr >/dev/null 2>&1 || exit 0

    # AC-6's other half: herdr is installed but could not answer. Same silent
    # skip, same retry next tick — a herdr server restarting is not an
    # incident, and the tick has nothing to say about panes it never saw.
    #
    # Asked before the lock is taken, deliberately: this read-only probe is
    # the cheap way out, and taking a lock (which creates the state directory)
    # on a machine with no herdr server would leave a directory behind every
    # minute for a job that can never do anything. The lock guards the
    # mutations below, and there are none above it.
    _rows=$(_sd_agent_rows) || exit 0

    if [ "${_SD_DRY_RUN}" -eq 0 ]; then
        _sd_acquire_lock || exit 0
        # Assigned first, never inlined into the message: this repo's naming
        # check flags a function whose name also shows up inside a quoted
        # string (see the note atop lib/session_doctor_state.sh).
        if ! session_doctor_state_ensure; then
            _dir=$(session_doctor_state_dir)
            ux_warning "State dir is not writable (${_dir}) — injections will not be counted, so the per-tab cap cannot be enforced this tick."
        fi
    fi

    # A here-doc, not a pipe: the loop's counters have to survive it, and the
    # right-hand side of a pipe runs in a subshell that would take them with it.
    while IFS="${_SD_TAB}" read -r _tab _status _cwd; do
        _sd_visit_pane "${_tab}" "${_status}" "${_cwd}"
    done <<EOF
${_rows}
EOF

    # The injections were launched in the background so they run concurrently;
    # the tick still waits for all of them before it reports. F-5 asks for the
    # merge-train-wake convention — launch, don't block *between* prompts —
    # and this delivers that while keeping two things it cannot give up: the
    # tick lock is still held while herdr is being typed into, so the next
    # period cannot inject into the same tab twice, and every injection's
    # result is in the state file before `aicron status` reads it.
    wait

    if [ "${_SD_DRY_RUN}" -eq 1 ]; then
        ux_success "Dry run — ${_SD_SCANNED} pane(s) scanned, ${_SD_STUCK} stuck on an API error."
        exit 0
    fi

    # Silence is the normal outcome of a */1 job on a healthy machine, and a
    # line a minute saying so would bury the ticks that matter.
    if [ "${_SD_STUCK}" -eq 0 ]; then
        exit 0
    fi

    if [ "${_SD_LAUNCHED}" -eq 0 ]; then
        ux_warning "Tick complete — ${_SD_STUCK} stuck tab(s) found, all past their injection budget; none was injected."
        exit 0
    fi

    # "dispatched", not "injected": the per-tab result is reported by the
    # injection itself (an accepted one logs a success line, a refused one a
    # warning), and this counter only knows how many were launched. Claiming a
    # landing it never observed is the one thing a summary must not do.
    ux_success "Tick complete — ${_SD_SCANNED} pane(s) scanned, ${_SD_STUCK} stuck, ${_SD_LAUNCHED} injection(s) dispatched, ${_SD_CAPPED} over budget."
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
