#!/bin/bash
# shell-common/tools/custom/pr_merge_train_cron.sh
# merge-train cron 디스패처 — 1회 tick (issue #1470).
#
# cron 이 주기마다 이 스크립트를 호출하면 tick 1회를 수행한다. tick 은 train 을
# 직접 돌리지 않는다 — 선행 조건 3개만 확인하고 claude 세션 하나를 띄운 뒤 끝난다:
#   1) 이번 tick 이 유일한 tick 인가 (flock)
#   2) 직전 tick 이 띄운 train 세션이 아직 살아 있는가 (herdr agent get)
#   3) 깨울 만한 대상 PR 이 있는가 (`gh pr list --author @me`, D-6 조용한 기간 적용)
#   4) herdr workspace -> tab -> agent -> `/gh-pr-merge-train <owner/repo>`
#
# 왜 train 본체가 셸이 아닌가 (D-8). issue-watcher 는 dispatch 가 서로 독립·병렬
# 이라 fire-and-forget 이 성립하지만, merge train 은 **직렬이고 각 단계가 앞
# 단계의 완료에 의존**한다. 셸이 fire-and-forget 으로 던지면 순서가 깨지고, 매
# 단계를 블로킹 대기하려면 결국 한 프로세스가 전 구간을 들고 있어야 한다. 그
# 프로세스는 충돌 해결과 CI 수정 두 지점에서 LLM 이 필요하므로 claude 세션이
# 맞다. 그래서 이 파일에는 tick 의 선행 조건 판정만 있다 — 라우팅 표(D-1)·정렬
# (D-2)·시도 상한(F-5)·리포트(F-9)는 전부 스킬 쪽 텍스트이고, 여기에 셸로 다시
# 구현하면 서로 드리프트하는 SSOT 가 둘 생긴다.
#
# GitHub 에 어떤 쓰기도 하지 않는다 — 머지·코멘트·라벨 변경 없음. 조회 전용이다.
#
# Usage: pr_merge_train_cron.sh [--cwd <PATH>] [--dry-run] | [-h|--help|help]

set -u

# Initialize common tools environment (DOTFILES_ROOT/SHELL_COMMON + ux_lib)
. "$(dirname "$0")/init.sh" || exit 1

# init.sh returns early under DOTFILES_TEST_MODE=1 (and before it exports
# SHELL_COMMON), so resolve shell-common from this script's own location as a
# fallback. ux_lib, gh_host.sh and the claude integration all load from here.
_PMT_SHELL_COMMON="${SHELL_COMMON:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Same early return means ux_* can still be undefined here — every output path
# below depends on it.
if ! type ux_header >/dev/null 2>&1; then
    if [ -f "${_PMT_SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
        # shellcheck source=/dev/null
        . "${_PMT_SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
    fi
fi

# ============================================================
# Constants (SSOT for the dispatcher)
# ============================================================

_PMT_STATE_SUBDIR="pr-merge-train"
_PMT_LOCK_BASENAME=".lock"

# Field separator, resolved once — `IFS="$(printf '\t')"` written into a loop
# header re-forks `printf` on every iteration.
_PMT_TAB=$(printf '\t')

# D-6 — quiet period, in minutes. `gh:issue-flow` Step 2.4 schedules
# `gh:pr-reply` four minutes after the PR is opened (`--defer-reply 4`), so a
# train that merges inside that window drops the review replies and the
# `/simplify` fixes with them. A human running the train by hand never hit this
# because the wait happened naturally; cron has no such protection. 11 = the
# 4-minute defer + the reply's own runtime + slack.
#
# The dispatcher applies the same filter the skill does, for a narrower
# purpose: it only has to answer "is there anything worth waking a session
# for". The skill re-applies it authoritatively at the moment it processes each
# PR, because minutes pass between this count and that decision.
_PMT_QUIET_MINUTES="11"

# Upper bound on the open-PR window. The dispatcher only needs "more than
# zero", so this is a courtesy cap, not a correctness boundary.
_PMT_PR_LIMIT="50"

# herdr agent naming. One train per repo, so the name is deterministic and
# derived from the repo slug — that is what lets the *next* tick find the
# session this tick started (see _pmt_train_state).
_PMT_AGENT_PREFIX="pmt-"
# Workspace label prefix. issue-watcher labels its workspaces with the repo
# directory's basename; the train must not land in those tabs, so it carries
# its own prefix (issue #1470, Impact).
_PMT_WORKSPACE_PREFIX="mt-"

# `herdr agent prompt --wait` 한 번의 상한 — 4분. train 자체는 수십 분을 돌 수
# 있지만 `--wait` 는 프롬프트가 *접수* 될 때까지만 기다린다. tick 이 겹치지 않게
# 막는 것은 flock 이므로 이 값은 cron 주기와 무관하다.
_PMT_TIMEOUT_MS="240000"
# Gap between the post-start idle checks (see _pmt_wait_for_idle). Overridable
# so the bats suite does not pay ~5s of real sleep per cold-agent path.
_PMT_IDLE_POLL_SLEEP="${PMT_IDLE_POLL_SLEEP:-0.5}"

# CLAUDE_CONFIG_DIR for the pane this tick opens. Resolved once per tick.
_PMT_CONFIG_DIR=""
# Set by --dry-run: report what the tick would do, mutate nothing.
_PMT_DRY_RUN=0
# The GitHub target, bound once in main() from the checkout's `origin` (#1403).
_PMT_REPO=""
_PMT_HOST=""

# ============================================================
# Helpers — state paths and JSON
# ============================================================

# Nested defaults on purpose: under `set -u`, `${XDG_STATE_HOME:-$HOME/...}`
# still aborts with "HOME: unbound variable" when HOME itself is unset (a cron
# environment can be that bare), so HOME is never referenced unguarded.
_pmt_state_dir() {
    printf '%s/%s' \
        "${XDG_STATE_HOME:-${HOME:-${TMPDIR:-/tmp}}/.local/state}" \
        "${_PMT_STATE_SUBDIR}"
}

# Extract one string field from JSON on stdin.
#   $1 = jq filter, e.g. '.result.agent.agent_status'.
#
# jq-only, and deliberately so: main() refuses to run without jq (the PR list
# is an array of objects, which no flat-key text scanner can walk), so every
# caller here is downstream of that check. Always returns 0 — a malformed
# document reads as "no such field", which is what every caller treats it as.
_pmt_json_value() {
    jq -r "${1} // empty" 2>/dev/null || return 0
}

# First string value of a flat key anywhere in the document. `herdr tab create`
# and `herdr workspace create` both answer with a pane but nest it under
# different parents (`.result.pane` vs `.result.root_pane`), and the CLI is
# free to add another. Keying on the leaf name rather than the path keeps this
# working across both shapes.
#
# The key travels as a jq *argument*, never as interpolated program text.
_pmt_json_first() {
    jq -r --arg k "$1" \
        '[.. | objects | .[$k]? // empty] | map(select(type == "string")) | first // empty' \
        2>/dev/null || return 0
}

# Echo epoch seconds, or nothing when the clock is unreadable.
_pmt_now() {
    local _now
    _now=$(date +%s 2>/dev/null) || return 0
    case "${_now}" in
    '' | *[!0-9]*) return 0 ;;
    esac
    printf '%s' "${_now}"
}

# ============================================================
# Helpers — the GitHub target (#1403 / #1407)
# ============================================================

# Bind `owner/repo` and the host from one and the same remote URL, so the
# dispatcher's single `gh` call cannot drift to another server. Echoes
# `<owner/repo><TAB><host>`; returns non-zero (with the reason on stderr) when
# the checkout has no usable remote — the tick must not guess a target.
_pmt_bind_target() {
    local _remote_url _repo _host

    if [ ! -f "${_PMT_SHELL_COMMON}/functions/gh_host.sh" ]; then
        ux_error "gh_host.sh not found under ${_PMT_SHELL_COMMON}/functions — cannot resolve the GitHub target."
        return 1
    fi
    # shellcheck source=/dev/null
    . "${_PMT_SHELL_COMMON}/functions/gh_host.sh" || return 1

    _remote_url=$(git remote get-url origin 2>/dev/null) || {
        ux_error "No 'origin' remote in $(pwd) — cannot resolve the merge-train target."
        # >&2 because this function's stdout is the binding itself: an ux_info
        # written to stdout would be swallowed by the caller's `$( )` and never
        # reach the cron log. ux_error already writes to stderr on its own.
        ux_info "Run the tick with --cwd pointing at a checkout that has one." >&2
        return 1
    }

    _repo=$(_gh_parse_owner_repo_url "${_remote_url}" 2>/dev/null) || {
        ux_error "Cannot parse owner/repo from origin's URL: ${_remote_url}"
        return 1
    }
    _host=$(_gh_host_from_url "${_remote_url}" 2>/dev/null) || _host=$(_gh_resolve_host)
    [ -n "${_host}" ] || {
        ux_error "Cannot resolve the GitHub host for ${_remote_url} — refusing to run unpinned (#1403)."
        return 1
    }

    printf '%s\t%s' "${_repo}" "${_host}"
}

# ============================================================
# Precondition 3 — are there PRs worth waking a session for
# ============================================================

# Echo the number of PRs this tick considers targets. Returns non-zero when
# GitHub could not be asked at all — the caller ends the tick rather than
# launching a train that would start by guessing (issue #1470, Error Cases:
# "상태를 모르는 채 머지하지 않는다").
#
# Two filters, both mirrored in the skill:
#   --author @me  D-7. A colleague's PR is never auto-merged.
#   quiet period  D-6. A PR touched in the last _PMT_QUIET_MINUTES minutes may
#                 still have a deferred `gh:pr-reply` in flight.
# Drafts are dropped as well: `DRAFT` is a skip row in the D-1 routing table,
# so a repo whose only open PR is a draft has nothing for the train to do and
# must not wake a session every cron period.
_pmt_target_count() {
    local _json _cutoff _now

    _json=$(GH_HOST="${_PMT_HOST}" gh pr list --repo "${_PMT_REPO}" \
        --author @me --state open --limit "${_PMT_PR_LIMIT}" \
        --json number,updatedAt,isDraft 2>/dev/null) || return 1
    [ -n "${_json}" ] || return 1

    _now=$(_pmt_now)
    # No clock means no defensible cutoff. Counting every PR as a target would
    # merge inside the quiet window; counting none would wedge the train
    # permanently. Refusing the tick is the only answer that does neither.
    [ -n "${_now}" ] || return 1
    _cutoff=$((_now - _PMT_QUIET_MINUTES * 60))

    printf '%s' "${_json}" | jq -r --argjson cutoff "${_cutoff}" '
        [ .[]?
          | select((.isDraft // false) | not)
          | select(((.updatedAt // "") | fromdateiso8601? // 0) <= $cutoff)
        ] | length
    ' 2>/dev/null || return 1
}

# ============================================================
# Preconditions 1-2 — one train at a time (NF-1)
# ============================================================

# Two layers guard NF-1 and neither one subsumes the other.
#
# The flock below covers *ticks*: two cron periods overlapping, or a manual run
# racing a scheduled one. It cannot cover the train, because the tick is
# short-lived (seconds) while the session it spawns is long-lived (a merge
# train over N PRs runs for many minutes) — the tick that started the train has
# already exited and dropped the lock long before the train finishes.
#
# So the second layer asks herdr directly whether the previously started train
# agent is still doing something. Together: the lock stops two dispatchers, the
# agent probe stops a second train.
_pmt_acquire_lock() {
    local _dir _lock
    _dir=$(_pmt_state_dir)
    _lock="${_dir}/${_PMT_LOCK_BASENAME}"

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
        ux_warning "another pr_merge_train_cron tick is already running — skip"
        return 1
    fi
}

# Echo the herdr agent name for <owner/repo>: `pmt-<owner>-<repo>`, with
# anything outside herdr's safe name charset folded to `-`.
_pmt_agent_name() {
    printf '%s%s' "${_PMT_AGENT_PREFIX}" \
        "$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-')"
}

# Echo the herdr workspace label for <owner/repo>. Prefixed so it can never
# collide with an issue-watcher workspace, which labels by the checkout's
# directory basename.
_pmt_workspace_label() {
    printf '%s%s' "${_PMT_WORKSPACE_PREFIX}" \
        "$(printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-')"
}

# Echo the agent status (idle|working|blocked|done|unknown). Returns non-zero
# when herdr itself rejects the query — agent missing, or pane closed.
_pmt_agent_status() {
    local _json _rc=0
    _json=$(herdr agent get "$1" 2>/dev/null) || _rc=$?
    [ "${_rc}" -eq 0 ] || return 1
    printf '%s' "${_json}" | _pmt_json_value '.result.agent.agent_status'
}

# Classify the previously started train session. Echoes one of:
#   live     a train is still running — this tick must not start another (NF-1)
#   reuse    the pane is open and idle, so the finished train's session can be
#            prompted again instead of stacking a second tab on top of it
#   fresh    no such agent — open a workspace/tab/agent from scratch
#
# `done`/`unknown`/anything else reads as `fresh`: the pane is gone or herdr
# cannot say, and a fresh launch is recoverable while a permanent block is not.
_pmt_train_state() {
    local _status

    _status=$(_pmt_agent_status "$1") || {
        printf 'fresh'
        return 0
    }

    case "${_status}" in
    working | blocked) printf 'live' ;;
    idle) printf 'reuse' ;;
    *) printf 'fresh' ;;
    esac
}

# ============================================================
# Launch — herdr pane -> claude -> prompt (D-8)
# ============================================================

# CLAUDE_CONFIG_DIR for the train's pane (issue #571 / #1393). Same account
# routing as issue_watcher_cron.sh's `_iw_resolve_config_dir`, which carries the
# per-branch rationale in full; only the error wording differs here. Returns 2
# when HOME is unset (the caller degrades to no routing), 1 on a real failure.
_pmt_resolve_config_dir() {
    [ -n "${HOME:-}" ] || return 2

    (
        # Captured before claude.sh is sourced: the *caller's* environment is
        # what says whether the single-account fallback applies. A set-but-empty
        # CLAUDE_DEFAULT_ACCOUNT counts as explicitly set.
        _enabled="${CLAUDE_ENABLED_ACCOUNTS:-}"
        _default_set=0
        [ -z "${CLAUDE_DEFAULT_ACCOUNT+x}" ] || _default_set=1

        DOTFILES_FORCE_INIT=1
        export DOTFILES_FORCE_INIT

        # shellcheck source=/dev/null
        . "${_PMT_SHELL_COMMON}/tools/integrations/claude.sh" >&2 || {
            ux_error "Cannot load ${_PMT_SHELL_COMMON}/tools/integrations/claude.sh — CLAUDE_CONFIG_DIR unresolvable."
            exit 1
        }

        # Internal-PC single-account override: must run before account
        # resolution — an empty CLAUDE_ENABLED_ACCOUNTS must not fail the tick.
        if [ "$(_dotfiles_setup_mode)" = "internal" ]; then
            _cfg_dir="$HOME/.claude"
        else
            _account="${CLAUDE_DEFAULT_ACCOUNT:-personal}"
            _cfg_dir=$(_claude_resolve_account "${_account}") || {
                # Pre-#1393 single-account user. ux_* is redirected because
                # this subshell reserves stdout for the resolved path.
                if [ -z "${_enabled}" ] && [ "${_default_set}" -eq 0 ] &&
                    [ -d "$HOME/.claude" ]; then
                    ux_warning "CLAUDE_ENABLED_ACCOUNTS not configured — falling back to \$HOME/.claude (single-account mode)." >&2
                    ux_info "Run 'claude-accounts setup' to opt into multi-account routing." >&2
                    printf '%s' "$HOME/.claude"
                    exit 0
                fi
                ux_error "Unknown claude account: ${_account} — cannot set CLAUDE_CONFIG_DIR for the merge-train pane."
                ux_info "Available: $(_claude_resolve_account --list | tr '\n' ' ')" >&2
                exit 1
            }
        fi

        if [ ! -d "${_cfg_dir}" ]; then
            ux_error "Claude account directory missing: ${_cfg_dir} — cannot bootstrap the merge-train pane."
            ux_info "Run: claude-accounts setup" >&2
            exit 1
        fi

        printf '%s' "${_cfg_dir}"
    )
}

_pmt_herdr_create() {
    local _cwd="$1" _label="$2"
    shift 2

    set -- "$@" --cwd "${_cwd}" --label "${_label}" --no-focus
    [ -z "${_PMT_CONFIG_DIR}" ] || set -- "$@" --env "CLAUDE_CONFIG_DIR=${_PMT_CONFIG_DIR}"

    herdr "$@" 2>/dev/null
}

# Echo the workspace id whose label is <1>, creating it against cwd <2> when no
# such workspace exists. Label-matched rather than persisted: the herdr server
# is the SSOT for what is open, and a state file would only drift from it.
_pmt_workspace_for_label() {
    local _label="$1" _cwd="$2" _json _ws

    _json=$(herdr workspace list 2>/dev/null) || _json=""
    _ws=$(printf '%s' "${_json}" | jq -r --arg l "${_label}" '
        [ .result.workspaces[]? | select(.label == $l) | .workspace_id ] | first // empty
    ' 2>/dev/null) || _ws=""

    if [ -n "${_ws}" ]; then
        printf '%s' "${_ws}"
        return 0
    fi

    _json=$(_pmt_herdr_create "${_cwd}" "${_label}" workspace create) || _json=""
    _ws=$(printf '%s' "${_json}" | _pmt_json_first workspace_id)
    [ -n "${_ws}" ] || return 1
    printf '%s' "${_ws}"
}

# Open the train's tab and echo `<pane_id><TAB><tab_id>`.
_pmt_tab_create() {
    local _ws="$1" _cwd="$2" _label="$3" _json _pane _tab

    _json=$(_pmt_herdr_create "${_cwd}" "${_label}" tab create --workspace "${_ws}") || return 1

    _pane=$(printf '%s' "${_json}" | _pmt_json_first pane_id)
    _tab=$(printf '%s' "${_json}" | _pmt_json_first tab_id)
    [ -n "${_pane}" ] || return 1
    printf '%s\t%s' "${_pane}" "${_tab}"
}

# `-- ARG...` is passed through to the pane's claude invocation. Unattended
# cron ticks must never stop on a permission-approval prompt (issue #1393).
_pmt_agent_start() {
    herdr agent start "$1" --kind claude --pane "$2" \
        -- --dangerously-skip-permissions >/dev/null 2>&1
}

# Wait for a freshly started agent to report idle before prompting it.
# `herdr agent start` only confirms the pane looks interactive — a claude
# process can have drawn its prompt box before its key-input loop accepts
# Enter, so the command is typed but never submitted (issue #1399). Capped at
# ~5s (10 checks, 0.5s apart), far below any sane cron period; hitting the cap
# still dispatches, because a stalled prompt is reported rather than silently
# booked as a started train.
_pmt_wait_for_idle() {
    local _agent="$1" _i=0 _status _get_failed=0

    while [ "${_i}" -lt 10 ]; do
        if _status=$(_pmt_agent_status "${_agent}"); then
            [ "${_status}" != "idle" ] || return 0
        else
            _get_failed=$((_get_failed + 1))
        fi
        _i=$((_i + 1))
        [ "${_i}" -lt 10 ] || break
        [ "${_PMT_IDLE_POLL_SLEEP}" = "0" ] || sleep "${_PMT_IDLE_POLL_SLEEP}"
    done

    if [ "${_get_failed}" -gt 0 ]; then
        ux_warning "Agent ${_agent} did not report idle within ~5s (${_get_failed}/10 health-check failures) — prompting anyway."
    else
        ux_warning "Agent ${_agent} did not report idle within ~5s — prompting anyway."
    fi
}

# Echo herdr's JSON response on stdout; the exit code is herdr's own.
_pmt_prompt_once() {
    herdr agent prompt "$1" "$2" --wait --timeout "${_PMT_TIMEOUT_MS}" 2>/dev/null
}

# Hand the whole train over to the session. This is the one place where the
# dispatcher's job ends and the skill's begins (D-8).
_pmt_prompt_train() {
    local _agent="$1" _prompt _json _code _rc=0

    _prompt="/gh-pr-merge-train ${_PMT_REPO}"

    _json=$(_pmt_prompt_once "${_agent}" "${_prompt}") || _rc=$?
    if [ "${_rc}" -eq 0 ]; then
        ux_success "Dispatched to ${_agent}: ${_prompt}"
        return 0
    fi

    # No retry, and deliberately none: a prompt that *did* land but looked
    # stalled would earn a second train on the same repo, which is precisely
    # what NF-1 forbids. The next tick re-evaluates from scratch.
    _code=$(printf '%s' "${_json}" | _pmt_json_value '.error.code')
    ux_error "herdr agent prompt failed for agent ${_agent} (${_code:-unknown})."
    return 1
}

# Open a fresh workspace/tab/agent for the train and prompt it.
_pmt_launch_fresh() {
    local _agent="$1" _cwd="$2" _label _ws _pane_tab _pane _tab

    _label=$(_pmt_workspace_label "${_PMT_REPO}")

    _ws=$(_pmt_workspace_for_label "${_label}" "${_cwd}") || {
        ux_error "No herdr workspace for ${_label} — ending this tick."
        return 1
    }
    _pane_tab=$(_pmt_tab_create "${_ws}" "${_cwd}" "merge-train") || {
        ux_error "herdr tab create failed for ${_PMT_REPO} — ending this tick."
        return 1
    }
    IFS="${_PMT_TAB}" read -r _pane _tab <<EOF
${_pane_tab}
EOF
    _pmt_agent_start "${_agent}" "${_pane}" || {
        ux_error "herdr agent start ${_agent} failed on pane ${_pane} — ending this tick."
        return 1
    }

    _pmt_wait_for_idle "${_agent}"
    _pmt_prompt_train "${_agent}"
}

# ============================================================
# Usage
# ============================================================

_pmt_usage() {
    ux_header "pr_merge_train_cron"
    ux_info "Usage: pr_merge_train_cron.sh [--cwd <PATH>] [--dry-run] | [-h|--help|help]"
    ux_info "Runs one merge-train tick: check preconditions, launch /gh-pr-merge-train."
    ux_bullet "options"
    ux_bullet_sub "--cwd <PATH>   run the tick from PATH; the target repo is PATH's origin remote"
    ux_bullet_sub "--dry-run      print what this tick would launch, change nothing"
    ux_bullet_sub "               (takes no lock and opens no pane)"
    ux_bullet_sub "-h, --help, help   show this help"
    ux_bullet "tick"
    ux_bullet_sub "1. flock — one tick at a time"
    ux_bullet_sub "2. herdr agent get ${_PMT_AGENT_PREFIX}<owner>-<repo> — a running train blocks a new one"
    ux_bullet_sub "3. gh pr list --author @me --state open — is there anything to merge"
    ux_bullet_sub "4. herdr workspace -> tab -> claude -> /gh-pr-merge-train <owner/repo>"
    ux_bullet_sub "the train itself runs inside that claude session, never in this shell (D-8)"
    ux_bullet_sub "no PR is ever written to from here — no merge, comment or label change"
    ux_bullet "target PRs"
    ux_bullet_sub "your own PRs only (--author @me) — a colleague's PR is never auto-merged (D-7)"
    ux_bullet_sub "a PR updated in the last ${_PMT_QUIET_MINUTES}m is excluded (D-6: gh:pr-reply may be in flight)"
    ux_bullet_sub "drafts are excluded — DRAFT is a skip row in the routing table"
    ux_bullet_sub "gh pr list failure ends the tick: never merge without knowing state"
    ux_bullet "duplicate-start guard (NF-1)"
    ux_bullet_sub "the lock covers overlapping ticks; the agent probe covers the running train"
    ux_bullet_sub "the tick is short-lived, the train session is not — the lock alone cannot see it"
    ux_bullet_sub "agent working/blocked -> hold; idle -> reuse the pane; missing -> open a new one"
    ux_bullet "state"
    ux_bullet_sub "\${XDG_STATE_HOME:-\$HOME/.local/state}/${_PMT_STATE_SUBDIR}/${_PMT_LOCK_BASENAME}   (tick lock)"
    ux_bullet "claude session (claude-yolo parity)"
    ux_bullet_sub "the pane runs claude --dangerously-skip-permissions (unattended cron)"
    ux_bullet_sub "internal setup mode  → CLAUDE_CONFIG_DIR=\$HOME/.claude"
    ux_bullet_sub "otherwise            → CLAUDE_CONFIG_DIR=\$HOME/.claude-\${CLAUDE_DEFAULT_ACCOUNT:-personal}"
    ux_bullet "crontab"
    ux_bullet_sub "*/15 * * * * /path/to/pr_merge_train_cron.sh --cwd ~/dotfiles >> ~/.local/state/pr-merge-train/cron.log 2>&1"
}

# ============================================================
# Main
# ============================================================

main() {
    local _cwd="" _target _agent _binding _state

    while [ "$#" -gt 0 ]; do
        case "$1" in
        -h | --help | help)
            _pmt_usage
            exit 0
            ;;
        --cwd)
            if [ "$#" -lt 2 ]; then
                ux_error "--cwd requires a PATH argument."
                exit 1
            fi
            _cwd="$2"
            shift 2
            ;;
        --dry-run)
            _PMT_DRY_RUN=1
            shift
            ;;
        *)
            ux_error "Unknown option: $1"
            ux_info "Run 'pr_merge_train_cron.sh --help' for usage."
            exit 1
            ;;
        esac
    done

    # --cwd is where the tick runs from, and therefore which checkout's origin
    # names the target repo. A cron tick starts in $HOME, which is not a repo.
    if [ -n "${_cwd}" ]; then
        if ! cd "${_cwd}"; then
            ux_error "Cannot cd to --cwd ${_cwd}."
            exit 1
        fi
    fi

    ux_header "pr-merge-train tick"

    if ! command -v gh >/dev/null 2>&1; then
        ux_error "gh not found in PATH — cannot query the open PRs."
        exit 1
    fi

    # jq is not optional on this path: `gh pr list --json` answers with an
    # array of objects, and the flat-key fallback _pmt_json_value uses for the
    # single-value herdr responses cannot walk that.
    if ! command -v jq >/dev/null 2>&1; then
        ux_error "jq not found in PATH — cannot parse the PR list."
        ux_info "Install jq, or add it to the cron PATH."
        exit 1
    fi

    # A dry run reports and touches nothing, so it must stay usable on a
    # machine with no herdr server.
    if [ "${_PMT_DRY_RUN}" -eq 0 ] && ! command -v herdr >/dev/null 2>&1; then
        ux_error "herdr not found in PATH — cannot launch the merge-train session."
        ux_info "Install it via ./herdr/setup.sh, or add it to the cron PATH."
        exit 1
    fi

    _binding=$(_pmt_bind_target) || exit 1
    IFS="${_PMT_TAB}" read -r _PMT_REPO _PMT_HOST <<EOF
${_binding}
EOF
    _agent=$(_pmt_agent_name "${_PMT_REPO}")

    # The dry run answers ahead of both guards, deliberately: taking the lock
    # would make a dry run silently no-op while a real tick is mid-cycle —
    # exactly when a human is most likely to be asking what the train sees.
    if [ "${_PMT_DRY_RUN}" -eq 1 ]; then
        if ! _target=$(_pmt_target_count); then
            ux_error "gh pr list failed for ${_PMT_REPO} — a real tick would end here."
            exit 0
        fi
        ux_success "Dry run — ${_PMT_REPO} on ${_PMT_HOST}: ${_target} target PR(s)."
        ux_bullet "would prompt agent ${_agent} with /gh-pr-merge-train ${_PMT_REPO}"
        exit 0
    fi

    _pmt_acquire_lock || exit 0

    # NF-1 layer 2 — the train the *previous* tick started outlives the tick
    # that started it, so the lock above cannot see it.
    _state=$(_pmt_train_state "${_agent}")
    if [ "${_state}" = "live" ]; then
        ux_info "A merge train is already running on ${_PMT_REPO} (agent ${_agent}) — skip."
        exit 0
    fi

    if ! _target=$(_pmt_target_count); then
        ux_error "gh pr list failed for ${_PMT_REPO} — ending this tick rather than merging blind."
        exit 0
    fi
    if [ "${_target}" -eq 0 ]; then
        ux_info "No target PR on ${_PMT_REPO} — nothing to wake a session for."
        exit 0
    fi

    # Resolved once, before any pane is opened: the train session inherits one
    # claude account for its whole run.
    _PMT_CONFIG_DIR=$(_pmt_resolve_config_dir)
    case "$?" in
    0) ;;
    2)
        _PMT_CONFIG_DIR=""
        ux_warning "HOME is unset — starting claude without CLAUDE_CONFIG_DIR account routing."
        ;;
    *)
        exit 1
        ;;
    esac

    ux_info "${_target} target PR(s) on ${_PMT_REPO} — starting the merge train."

    if [ "${_state}" = "reuse" ]; then
        # The previous train's pane is open and idle: prompt it again rather
        # than stacking a second tab on the workspace every cron period.
        _pmt_prompt_train "${_agent}" || exit 1
    else
        _pmt_launch_fresh "${_agent}" "$(pwd)" || exit 1
    fi

    ux_success "Tick complete — merge train handed to ${_agent}."
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
