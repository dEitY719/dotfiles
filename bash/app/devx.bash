#!/usr/bin/env bash
# devx.bash — global setup for devx command (dotfiles friendly)
# Safe when sourced from .bashrc; strict only when executed directly.

# --- Ensure ~/.local/bin on PATH (idempotent) ---
case ":${PATH}:" in
*":${HOME}/.local/bin:"*) ;;
*) export PATH="${HOME}/.local/bin:${PATH}" ;;
esac

# --- Self-heal: make ~/.local/bin/devx point to this script ---
DEVX_SRC="${BASH_SOURCE[0]}"
if command -v realpath >/dev/null 2>&1; then
    DEVX_SRC="$(realpath "$DEVX_SRC")"
elif command -v readlink >/dev/null 2>&1; then
    DEVX_SRC="$(readlink -f "$DEVX_SRC" 2>/dev/null || echo "$DEVX_SRC")"
fi

mkdir -p "${HOME}/.local/bin"

if [[ ! -L "${HOME}/.local/bin/devx" ]] || [[ "$(readlink "${HOME}/.local/bin/devx" 2>/dev/null)" != "$DEVX_SRC" ]]; then
    ln -sf "$DEVX_SRC" "${HOME}/.local/bin/devx"
    chmod +x "${HOME}/.local/bin/devx" 2>/dev/null || true
fi

# =======================
# devx command implementation
# =======================

devx__colors() {
    # Use UX library variables instead of hardcoding colors
    bold="${UX_BOLD:-}"
    dim="${UX_MUTED:-}"
    reset="${UX_RESET:-}"
    c_blue="${UX_PRIMARY:-}"
    c_green="${UX_SUCCESS:-}"
    c_yellow="${UX_WARNING:-}"
    c_red="${UX_ERROR:-}"
}

devx__log() {
    local lvl="$1"
    shift
    local ts
    ts="$(date '+%F %T')"
    case "$lvl" in
    INFO)
        printf '%s%s▶ %s INFO%s %s\n' "$dim" "$ts" "$reset" "$dim" "$*"
        printf '%s' "$reset"
        ;;
    RUN)
        printf '%s▶ %sRUN%s   %s\n' "$c_blue" "$reset" "$c_blue" "$*"
        printf '%s' "$reset"
        ;;
    OK) printf '%s✔ OK%s  %s\n' "$c_green" "$reset" "$*" ;;
    WARN) printf '%s! WARN%s %s\n' "$c_yellow" "$reset" "$*" ;;
    ERR) printf '%s✖ ERR%s  %s\n' "$c_red" "$reset" "$*" ;;
    *) printf '• %s\n' "$*" ;;
    esac
}

devx__find_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/tools/dev.sh" ]]; then
            printf '%s' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

devx__usage() {
    cat <<EOF
${bold}${c_blue}Usage:${reset} devx <command>

${bold}${c_blue}Commands:${reset}
  ${c_green}up [b|f]${reset}   Start dev server (b: backend, f: frontend)
  ${c_green}down${reset}       Stop dev server and related services
  ${c_green}test${reset}       Run test suite (pytest)
  ${c_green}format${reset}     Format + lint code (tox -e ruff)
  ${c_green}stat${reset}       Show repository statistics (commits, LOC)
  ${c_green}help${reset}       Show this help message
  ${c_green}shell${reset}      Enter project shell
  ${c_green}cli${reset}        Start interactive CLI
  ${c_green}db${reset}         Start database CLI

${bold}${c_blue}Env:${reset}
  ${c_yellow}NO_COLOR=1${reset}     # 컬러 출력 끄기
EOF
}

devx__main() (
    set -euo pipefail
    devx__colors

    if [[ $# -eq 0 ]]; then
        devx__usage
        exit 2
    fi

    if [[ "$1" == "help" || "$1" == "--help" || "$1" == "-h" ]]; then
        devx__usage
        exit 0
    fi

    # --- Built-in command: stat ---
    if [[ "$1" == "stat" ]]; then
        shift
        local src="${BASH_SOURCE[0]}"
        local real_script_path
        if command -v realpath >/dev/null 2>&1; then
            real_script_path="$(realpath "$src")"
        else
            # Simple fallback for readlink
            real_script_path="$(readlink -f "$src" 2>/dev/null || echo "$src")"
        fi

        # devx.bash is in bash/app/, so we go up 3 levels to repo root
        # bash/app/devx.bash -> bash/app -> bash -> root
        local repo_root
        repo_root="$(dirname "$(dirname "$(dirname "$real_script_path")")")"
        local tool_path="${repo_root}/mytool/repo_stats.sh"

        if [[ -f "$tool_path" ]]; then
            bash "$tool_path" "$@"
            exit $?
        else
            devx__log ERR "Could not find repo_stats.sh at ${tool_path}"
            exit 1
        fi
    fi

    local t_start_ns t_end_ns dur_ms
    t_start_ns="$(date +%s%N 2>/dev/null || true)"
    if [[ -z "$t_start_ns" || "$t_start_ns" == *N ]]; then
        SECONDS=0
    fi

    local cwd="$PWD"
    local root
    if ! root="$(devx__find_root)"; then
        devx__log ERR "현재 경로(${cwd})부터 상위로 탐색했지만 ${bold}tools/dev.sh${reset}를 찾지 못했습니다."
        exit 1
    fi

    local cmd_str="$*"
    devx__log INFO "from='${cwd}'  ->  root='${root}'  cmd='${cmd_str}'"
    devx__log RUN "${root}/tools/dev.sh ${cmd_str}"

    set +e
    (cd "$root" && bash "tools/dev.sh" "$@")
    local rc=$?
    set -e

    if [[ -n "${t_start_ns:-}" && "$t_start_ns" != *N ]]; then
        t_end_ns="$(date +%s%N 2>/dev/null || true)"
        if [[ -n "$t_end_ns" && "$t_end_ns" != *N ]]; then
            dur_ms=$(((t_end_ns - t_start_ns) / 1000000))
        else
            dur_ms=$((SECONDS * 1000))
        fi
    else
        dur_ms=$((SECONDS * 1000))
    fi

    if [[ $rc -eq 0 ]]; then
        devx__log OK "exit_code=0  duration=${dur_ms}ms"
    else
        devx__log ERR "exit_code=${rc}  duration=${dur_ms}ms"
    fi
    exit "$rc"
)

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    devx__main "$@"
fi
