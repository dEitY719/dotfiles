#!/usr/bin/env bash
# devx.bash — global setup for devx command (dotfiles friendly)
# Safe when sourced from .bashrc; strict only when executed directly.

# --- Ensure ~/.local/bin on PATH (idempotent) ---
case ":${PATH}:" in
*":${HOME}/.local/bin:"*) ;;
*) export PATH="${HOME}/.local/bin:${PATH}" ;;
esac

# --- Self-heal: make ~/.local/bin/devx point to this script ---
# Resolve absolute path to this devx.bash
DEVX_SRC="${BASH_SOURCE[0]}"
if command -v realpath >/dev/null 2>&1; then
    DEVX_SRC="$(realpath "$DEVX_SRC")"
elif command -v readlink >/dev/null 2>&1; then
    DEVX_SRC="$(readlink -f "$DEVX_SRC" 2>/dev/null || echo "$DEVX_SRC")"
fi

mkdir -p "${HOME}/.local/bin"

# If not a symlink to this file, fix it.
if [[ ! -L "${HOME}/.local/bin/devx" ]] || [[ "$(readlink "${HOME}/.local/bin/devx" 2>/dev/null)" != "$DEVX_SRC" ]]; then
    ln -sf "$DEVX_SRC" "${HOME}/.local/bin/devx"
    chmod +x "${HOME}/.local/bin/devx" 2>/dev/null || true
fi

# =======================
# devx command implementation
# =======================

# ---- lightweight helpers (no strict mode at top-level) ----
devx__colors() {
    if [[ "${NO_COLOR:-}" != "1" && -t 1 ]]; then
        bold=$'\e[1m'
        dim=$'\e[2m'
        reset=$'\e[0m'
        c_blue=$'\e[34m'
        c_green=$'\e[32m'
        c_yellow=$'\e[33m'
        c_red=$'\e[31m'
    else
        bold=
        dim=
        reset=
        c_blue=
        c_green=
        c_yellow=
        c_red=
    fi
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
    cat <<'EOF'
Usage: devx <command>

Commands:
  up       Start dev server (uvicorn on :8000 + DB init)
  test     Run test suite (pytest)
  format   Format + lint code (tox -e ruff)
  shell    Enter project shell
  cli      Start interactive CLI
  db       Start database CLI

Env:
  NO_COLOR=1     # 컬러 출력 끄기
EOF
}

# ---- main runner: run in a subshell with strict modes ----
devx__main() (
    set -euo pipefail

    devx__colors

    local cmd="${1:-}"
    if [[ -z "$cmd" ]]; then
        devx__usage
        exit 2
    fi

    # timer start (fallback to SECONDS)
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

    devx__log INFO "from='${cwd}'  ->  root='${root}'  cmd='${cmd}'"
    devx__log RUN "${root}/tools/dev.sh ${cmd}"

    # execute (even if not executable, run via bash)
    set +e
    (cd "$root" && bash "tools/dev.sh" "$cmd")
    local rc=$?
    set -e

    # duration
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

# --- only run when executed directly, stay inert when sourced ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    devx__main "$@"
fi
