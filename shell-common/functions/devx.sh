#!/bin/sh
# shell-common/functions/devx.sh
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
# (Skipped in test mode and when being sourced as a function)
# ═══════════════════════════════════════════════════════════════

if [ "${DOTFILES_TEST_MODE:-0}" != "1" ]; then
    # Only run self-heal when being executed directly, not when sourced
    # Safe method: Use parameter expansion instead of basename (avoids $0 flag injection)
    # If $0 starts with -, it's sourced (flag injection detected)
    _is_being_executed=false

    # Extract filename from $0 using parameter expansion (shell-safe, no external commands)
    _script_name="${0##*/}"

    # Validate that _script_name doesn't start with - (indicates sourced with flags)
    if [ "${_script_name#-}" = "$_script_name" ]; then
        # $0 is a valid filename, not a flag
        case "$_script_name" in
            devx.sh|devx)
                _is_being_executed=true
                ;;
        esac
    fi
    unset _script_name

    if [ "$_is_being_executed" = "true" ]; then
        # Detect the source script path (works in both bash and sh)
        if [ -n "${BASH_SOURCE+x}" ]; then
            DEVX_SRC="${BASH_SOURCE[0]}"
        else
            # For shells that don't have BASH_SOURCE, use $0
            DEVX_SRC="$0"
        fi

        # Resolve to absolute path
        if command -v realpath > /dev/null 2>&1; then
            DEVX_SRC="$(realpath "$DEVX_SRC" 2>/dev/null || true)"
        elif command -v readlink > /dev/null 2>&1; then
            DEVX_SRC="$(readlink -f "$DEVX_SRC" 2>/dev/null || true)"
        fi

        # Only create symlink if we have a valid absolute path
        if [ -n "$DEVX_SRC" ] && [ -f "$DEVX_SRC" ]; then
            # Create ~/.local/bin if needed
            mkdir -p "${HOME}/.local/bin"

            # Update symlink if needed
            current_link="$(readlink "${HOME}/.local/bin/devx" 2>/dev/null || true)"
            if [ "$current_link" != "$DEVX_SRC" ]; then
                ln -sf "$DEVX_SRC" "${HOME}/.local/bin/devx" 2>/dev/null || true
                chmod +x "${HOME}/.local/bin/devx" 2>/dev/null || true
            fi
        fi
    fi

    unset _is_being_executed
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
    set -u
    devx__colors

    # No arguments: show usage
    if [ $# -eq 0 ]; then
        devx__usage
        return 2
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

        # Navigate from shell-common/functions/devx.sh to repo root
        # shell-common/functions/devx.sh -> shell-common/functions -> shell-common -> root
        local repo_root
        repo_root="$(dirname "$(dirname "$(dirname "$script_path")")")"
        local tool_path="${repo_root}/shell-common/tools/custom/repo_stats.sh"

        if [ -f "$tool_path" ]; then
            bash "$tool_path" "$@"
            return $?
        else
            devx__log ERR "Could not find repo_stats.sh at ${tool_path}"
            return 1
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
        return 1
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
    return "$rc"
}

# Only execute if directly invoked (not sourced)
# In zsh: when sourced, ZSH_EVAL_CONTEXT has prefix "source:"
#         when called as function/command in .zshrc, it has "file:*" (not reliable for detection)
# In bash: when sourced, basename "$0" is shell name (bash, sh)
#         when executed directly, basename "$0" is script name (devx, devx.sh)
_should_run_main=false

# ═══════════════════════════════════════════════════════════════
# Public Function: devx()
# Wrapper function for interactive shell use
# Allows calling `devx <command>` after sourcing this file
# ═══════════════════════════════════════════════════════════════
devx() {
    devx__main "$@"
}

if [ -n "${ZSH_VERSION+x}" ]; then
    # In zsh: Only "source:*" indicates explicit sourcing
    # All other cases (file:*, toplevel, cmdarg, etc) should default to false for safety
    case "${ZSH_EVAL_CONTEXT:-}" in
        source:*)
            # This is being sourced via "source" command
            _should_run_main=false
            ;;
        *)
            # Default to false (safe) for all other cases
            # This prevents accidental execution during shell initialization
            _should_run_main=false
            ;;
    esac
else
    # In bash/sh: check if script name is devx or devx.sh (not shell name)
    # Safe method: Use parameter expansion instead of basename
    _script_name="${0##*/}"

    # Validate that $0 doesn't start with - (indicates sourced with flags)
    if [ "${_script_name#-}" = "$_script_name" ]; then
        case "$_script_name" in
            devx|devx.sh)
                _should_run_main=true
                ;;
        esac
    fi
    unset _script_name
fi

if [ "$_should_run_main" = "true" ]; then
    devx__main "$@"
fi

unset _should_run_main
