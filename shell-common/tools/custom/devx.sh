#!/bin/sh
# shell-common/tools/custom/devx.sh
# Development utility - project setup and command routing
# Shared between bash and zsh

# ═══════════════════════════════════════════════════════════════
# PATH Setup - Ensure ~/.local/bin is accessible
# ═══════════════════════════════════════════════════════════════

case ":${PATH}:" in
*":${HOME}/.local/bin:"*) ;;
*) export PATH="${HOME}/.local/bin:${PATH}" ;;
esac

# ═══════════════════════════════════════════════════════════════
# Self-heal: Create symlink to devx in ~/.local/bin
# (Skipped in test mode)
# ═══════════════════════════════════════════════════════════════

if [ "${DOTFILES_TEST_MODE:-0}" != "1" ]; then
    # Detect the source script path (works in both bash and sh)
    if [ -n "${BASH_SOURCE+x}" ]; then
        DEVX_SRC="${BASH_SOURCE[0]}"
    else
        # For shells that don't have BASH_SOURCE, use $0
        # This is a limitation of POSIX sh, but the tool is primarily bash-friendly
        DEVX_SRC="$0"
    fi

    # Resolve to absolute path
    if command -v realpath > /dev/null 2>&1; then
        DEVX_SRC="$(realpath "$DEVX_SRC")"
    elif command -v readlink > /dev/null 2>&1; then
        DEVX_SRC="$(readlink -f "$DEVX_SRC" 2>/dev/null || echo "$DEVX_SRC")"
    fi

    # Create ~/.local/bin if needed
    mkdir -p "${HOME}/.local/bin"

    # Update symlink if needed
    current_link="$(readlink "${HOME}/.local/bin/devx" 2>/dev/null || true)"
    if [ "$current_link" != "$DEVX_SRC" ]; then
        ln -sf "$DEVX_SRC" "${HOME}/.local/bin/devx"
        chmod +x "${HOME}/.local/bin/devx" 2>/dev/null || true
    fi
fi

# ═══════════════════════════════════════════════════════════════
# Color Setup - Use UX library variables
# ═══════════════════════════════════════════════════════════════

devx__colors() {
    bold="${UX_BOLD:-}"
    dim="${UX_MUTED:-}"
    reset="${UX_RESET:-}"
    c_blue="${UX_PRIMARY:-}"
    c_green="${UX_SUCCESS:-}"
    c_yellow="${UX_WARNING:-}"
    c_red="${UX_ERROR:-}"
}

# ═══════════════════════════════════════════════════════════════
# Logging Functions
# ═══════════════════════════════════════════════════════════════

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
    OK)
        printf '%s✔ OK%s  %s\n' "$c_green" "$reset" "$*"
        ;;
    WARN)
        printf '%s! WARN%s %s\n' "$c_yellow" "$reset" "$*"
        ;;
    ERR)
        printf '%s✖ ERR%s  %s\n' "$c_red" "$reset" "$*"
        ;;
    *)
        printf '• %s\n' "$*"
        ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# Project Root Detection
# ═══════════════════════════════════════════════════════════════

devx__find_root() {
    local dir="$PWD"
    while [ "$dir" != "/" ]; do
        if [ -f "$dir/tools/dev.sh" ]; then
            printf '%s' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# ═══════════════════════════════════════════════════════════════
# Usage / Help
# ═══════════════════════════════════════════════════════════════

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
  ${c_yellow}NO_COLOR=1${reset}     # Disable color output
EOF
}

# ═══════════════════════════════════════════════════════════════
# Main Command Router
# ═══════════════════════════════════════════════════════════════

devx__main() {
    set -eu
    devx__colors

    # No arguments: show usage
    if [ $# -eq 0 ]; then
        devx__usage
        exit 2
    fi

    # Note: help is now delegated to tools/dev.sh like other commands
    # This allows each project to define its own help text

    # Built-in stat command
    if [ "$1" = "stat" ]; then
        shift

        # Find repo root for stat command
        local script_path
        if [ -n "${BASH_SOURCE+x}" ]; then
            script_path="${BASH_SOURCE[0]}"
        else
            script_path="$0"
        fi

        # Resolve absolute path
        if command -v realpath > /dev/null 2>&1; then
            script_path="$(realpath "$script_path")"
        else
            script_path="$(readlink -f "$script_path" 2>/dev/null || echo "$script_path")"
        fi

        # Navigate from shell-common/tools/custom/devx.sh to repo root
        # shell-common/tools/custom/devx.sh -> shell-common/tools/custom -> shell-common/tools -> shell-common -> root
        local repo_root
        repo_root="$(dirname "$(dirname "$(dirname "$(dirname "$script_path")")")")"
        local tool_path="${repo_root}/shell-common/tools/custom/repo_stats.sh"

        if [ -f "$tool_path" ]; then
            bash "$tool_path" "$@"
            exit $?
        else
            devx__log ERR "Could not find repo_stats.sh at ${tool_path}"
            exit 1
        fi
    fi

    # Timing setup
    t_start_ns="$(date +%s%N 2>/dev/null || true)"
    if [ -z "$t_start_ns" ] || [ "$t_start_ns" = "${t_start_ns%N}" ]; then
        SECONDS=0
    fi

    # Find project root
    local cwd="$PWD"
    local root
    if ! root="$(devx__find_root)"; then
        devx__log ERR "Could not find tools/dev.sh from ${cwd}"
        exit 1
    fi

    # Log and execute command
    local cmd_str="$*"
    devx__log INFO "from='${cwd}'  ->  root='${root}'  cmd='${cmd_str}'"
    devx__log RUN "${root}/tools/dev.sh ${cmd_str}"

    # Execute with error handling
    (cd "$root" && bash "tools/dev.sh" "$@")
    local rc=$?

    # Calculate duration
    if [ -n "${t_start_ns:-}" ] && [ "$t_start_ns" != "${t_start_ns%N}" ]; then
        t_end_ns="$(date +%s%N 2>/dev/null || true)"
        if [ -n "$t_end_ns" ] && [ "$t_end_ns" != "${t_end_ns%N}" ]; then
            dur_ms=$(((t_end_ns - t_start_ns) / 1000000))
        else
            dur_ms=$((SECONDS * 1000))
        fi
    else
        dur_ms=$((SECONDS * 1000))
    fi

    # Log result
    if [ "$rc" -eq 0 ]; then
        devx__log OK "exit_code=0  duration=${dur_ms}ms"
    else
        devx__log ERR "exit_code=${rc}  duration=${dur_ms}ms"
    fi
    exit "$rc"
}

# Only execute if directly invoked (not sourced)
# In POSIX sh, $0 check is the standard way
if [ "$(basename "$0")" = "devx.sh" ] || [ "$(basename "$0")" = "devx" ]; then
    devx__main "$@"
fi
