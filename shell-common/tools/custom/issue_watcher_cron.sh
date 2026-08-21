#!/bin/bash
# shell-common/tools/custom/issue_watcher_cron.sh
# issue-watcher 5분 주기 감시 사이클 — 1회 tick (issue #1389).
#
# 전용 herdr workspace(label `issue-watcher`)의 고정 pane 하나에 claude 세션을
# 하나만 띄워 재사용한다. cron 이 5분마다 이 스크립트를 호출하면 tick 1회를
# 수행한다:
#   - 상태 파일이 없으면 workspace + agent 를 부트스트랩하고 기록한다.
#   - agent 가 idle/done 이면 dispatcher 프롬프트를 보낸다.
#   - agent 가 working/blocked 이면 이번 tick 을 건너뛴다(에러 아님, exit 0).
#   - agent 가 사라졌거나 pane 이 닫혔으면 재부트스트랩 후 프롬프트를 보낸다.
#
# Usage: issue_watcher_cron.sh [--cwd <PATH>] | [-h|--help|help]

set -u

# Initialize common tools environment (DOTFILES_ROOT/SHELL_COMMON + ux_lib)
. "$(dirname "$0")/init.sh" || exit 1

# init.sh returns early under DOTFILES_TEST_MODE=1 (and before its own ux
# fallbacks), so ux_* can still be undefined here. Load ux_lib directly from
# this script's own location in that case — every output path below depends
# on it.
if ! type ux_header >/dev/null 2>&1; then
    _IW_SHELL_COMMON="$(cd "$(dirname "$0")/../.." && pwd)"
    if [ -f "${_IW_SHELL_COMMON}/tools/ux_lib/ux_lib.sh" ]; then
        # shellcheck source=/dev/null
        . "${_IW_SHELL_COMMON}/tools/ux_lib/ux_lib.sh"
    fi
fi

# ============================================================
# Constants (SSOT for the watch cycle)
# ============================================================

_IW_LABEL="issue-watcher"
_IW_STATE_SUBDIR="issue-watcher"
_IW_STATE_BASENAME="herdr-watch.json"
_IW_PROMPT="@issue-watcher:dispatcher 실행"
# 5분 주기보다 여유 있게 4분 — cron tick 이 겹치지 않게 한다.
_IW_TIMEOUT_MS="240000"

# Overwritten by _iw_read_state when a state file exists.
_IW_AGENT_NAME="iw-watch"
_IW_WORKSPACE_ID=""
_IW_PANE_ID=""

# ============================================================
# Helpers
# ============================================================

_iw_state_dir() {
    printf '%s/%s' "${XDG_STATE_HOME:-$HOME/.local/state}" "${_IW_STATE_SUBDIR}"
}

_iw_state_file() {
    printf '%s/%s' "$(_iw_state_dir)" "${_IW_STATE_BASENAME}"
}

# Extract one string field from JSON on stdin.
#   $1 = jq filter, e.g. '.result.pane.pane_id' (used when jq is available).
#        The POSIX fallback derives the flat key from the filter's last
#        dot-segment (here: pane_id) and matches that key anywhere in the doc.
_iw_json_value() {
    local _json _key
    _json=$(cat)
    [ -n "${_json}" ] || return 0

    if command -v jq >/dev/null 2>&1; then
        printf '%s' "${_json}" | jq -r "${1} // empty" 2>/dev/null
        return 0
    fi

    _key="${1##*.}"

    # One JSON token per line first, so the greedy `.*` below cannot skip past
    # the wanted key into a later one on the same (single-line) document.
    printf '%s' "${_json}" |
        awk '{ gsub(/[,{}]/, "\n"); print }' |
        sed -n "s/.*\"${_key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" |
        head -n 1
}

_iw_write_state() {
    local _dir _file
    _dir=$(_iw_state_dir)
    _file=$(_iw_state_file)

    if ! mkdir -p "${_dir}"; then
        ux_error "Cannot create state directory: ${_dir}"
        return 1
    fi

    # Fixed-shape object — printf is the data writer here, not UX output.
    printf '{ "workspace_id": "%s", "pane_id": "%s", "agent_name": "%s" }\n' \
        "${_IW_WORKSPACE_ID}" "${_IW_PANE_ID}" "${_IW_AGENT_NAME}" >"${_file}"
}

# Populate _IW_* from the state file. Returns non-zero when the file is
# absent or incomplete, which the caller treats as "bootstrap needed".
_iw_read_state() {
    local _file _json
    _file=$(_iw_state_file)
    [ -f "${_file}" ] || return 1

    _json=$(cat "${_file}" 2>/dev/null) || return 1
    _IW_WORKSPACE_ID=$(printf '%s' "${_json}" | _iw_json_value '.workspace_id')
    _IW_PANE_ID=$(printf '%s' "${_json}" | _iw_json_value '.pane_id')
    _IW_AGENT_NAME=$(printf '%s' "${_json}" | _iw_json_value '.agent_name')

    [ -n "${_IW_WORKSPACE_ID}" ] || return 1
    [ -n "${_IW_PANE_ID}" ] || return 1
    [ -n "${_IW_AGENT_NAME}" ] || return 1
}

# Create the dedicated workspace, start a claude agent in its root pane, and
# persist the resulting ids. Idempotent at the tick level: only ever called
# when there is no usable state.
_iw_bootstrap() {
    local _cwd="$1" _ws_json

    ux_info "Bootstrapping herdr workspace (label: ${_IW_LABEL}, cwd: ${_cwd})"

    _ws_json=$(herdr workspace create --cwd "${_cwd}" --label "${_IW_LABEL}" --no-focus 2>/dev/null) ||
        _ws_json=""

    _IW_WORKSPACE_ID=$(printf '%s' "${_ws_json}" | _iw_json_value '.result.workspace.workspace_id')
    _IW_PANE_ID=$(printf '%s' "${_ws_json}" | _iw_json_value '.result.root_pane.pane_id')

    if [ -z "${_IW_WORKSPACE_ID}" ] || [ -z "${_IW_PANE_ID}" ]; then
        ux_error "herdr workspace create failed — no workspace_id/pane_id in the response."
        return 1
    fi

    if ! herdr agent start "${_IW_AGENT_NAME}" --kind claude --pane "${_IW_PANE_ID}" >/dev/null 2>&1; then
        ux_error "herdr agent start ${_IW_AGENT_NAME} failed (pane ${_IW_PANE_ID})."
        return 1
    fi

    _iw_write_state || return 1

    ux_success "Bootstrapped workspace=${_IW_WORKSPACE_ID} pane=${_IW_PANE_ID} agent=${_IW_AGENT_NAME}"
}

# Echo the agent status (idle|working|blocked|done|unknown). Returns non-zero
# when herdr itself rejects the query (agent missing / pane closed).
_iw_agent_status() {
    local _json _rc=0
    _json=$(herdr agent get "${_IW_AGENT_NAME}" 2>/dev/null) || _rc=$?
    [ "${_rc}" -eq 0 ] || return 1
    printf '%s' "${_json}" | _iw_json_value '.result.agent.agent_status'
}

_iw_dispatch() {
    if herdr agent prompt "${_IW_AGENT_NAME}" "${_IW_PROMPT}" \
        --wait --timeout "${_IW_TIMEOUT_MS}" >/dev/null 2>&1; then
        ux_success "Dispatched to ${_IW_AGENT_NAME}: ${_IW_PROMPT}"
        return 0
    fi

    ux_error "herdr agent prompt failed for agent ${_IW_AGENT_NAME}."
    return 1
}

_iw_usage() {
    ux_header "issue_watcher_cron"
    ux_info "Usage: issue_watcher_cron.sh [--cwd <PATH>] | [-h|--help|help]"
    ux_info "Runs one issue-watcher tick against the dedicated herdr workspace."
    ux_bullet "options"
    ux_bullet_sub "--cwd <PATH>   workspace working directory (default: git repo root)"
    ux_bullet_sub "-h, --help, help   show this help"
    ux_bullet "state"
    ux_bullet_sub "\${XDG_STATE_HOME:-\$HOME/.local/state}/${_IW_STATE_SUBDIR}/${_IW_STATE_BASENAME}"
    ux_bullet "crontab"
    ux_bullet_sub "*/5 * * * * /path/to/issue_watcher_cron.sh >> ~/.local/state/issue-watcher/cron.log 2>&1"
}

# ============================================================
# Main
# ============================================================

main() {
    local _cwd="" _status

    while [ "$#" -gt 0 ]; do
        case "$1" in
        -h | --help | help)
            _iw_usage
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
        *)
            ux_error "Unknown option: $1"
            ux_info "Run 'issue_watcher_cron.sh --help' for usage."
            exit 1
            ;;
        esac
    done

    if [ -z "${_cwd}" ]; then
        _cwd=$(git rev-parse --show-toplevel 2>/dev/null) || _cwd=""
    fi
    [ -n "${_cwd}" ] || _cwd="$PWD"

    ux_header "issue-watcher tick"

    if ! command -v herdr >/dev/null 2>&1; then
        ux_error "herdr not found in PATH — cannot run the issue-watcher tick."
        ux_info "Install it via ./herdr/setup.sh, or add it to the cron PATH."
        exit 1
    fi

    if _iw_read_state; then
        ux_info "Reusing state: workspace=${_IW_WORKSPACE_ID} pane=${_IW_PANE_ID} agent=${_IW_AGENT_NAME}"
    else
        _iw_bootstrap "${_cwd}" || exit 1
    fi

    _status=$(_iw_agent_status) || _status=""

    case "${_status}" in
    idle | done)
        _iw_dispatch || exit 1
        ;;
    working | blocked)
        ux_warning "Agent ${_IW_AGENT_NAME} is ${_status} — skip this tick (previous cycle still running or awaiting approval)."
        exit 0
        ;;
    *)
        ux_warning "Agent ${_IW_AGENT_NAME} unreachable (status: ${_status:-none}) — stale state, re-bootstrapping."
        _iw_bootstrap "${_cwd}" || exit 1
        _iw_dispatch || exit 1
        ;;
    esac
}

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
