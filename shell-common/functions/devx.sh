#!/bin/sh
# shell-common/functions/devx.sh
# Development helper - routes `devx <command>` to a repo-local `./tools/dev.sh`.
#
# Design goals:
# - POSIX-compatible (safe for bash/zsh)
# - Safe to source (no top-level side effects)
# - Uses ux_lib output functions when available

devx__have() {
    command -v "$1" >/dev/null 2>&1
}

devx__is_digits() {
    case "${1-}" in
        ""|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

devx__log_info() {
    if devx__have ux_info; then
        ux_info "$*"
        return 0
    fi
    printf '%s\n' "$*"
}

devx__log_run() {
    if devx__have ux_info; then
        ux_info "$*"
        return 0
    fi
    printf '%s\n' "$*"
}

devx__log_ok() {
    if devx__have ux_success; then
        ux_success "$*"
        return 0
    fi
    printf '%s\n' "$*"
}

devx__log_warn() {
    if devx__have ux_warning; then
        ux_warning "$*"
        return 0
    fi
    printf '%s\n' "$*" >&2
}

devx__log_err() {
    if devx__have ux_error; then
        ux_error "$*"
        return 0
    fi
    printf '%s\n' "$*" >&2
}

devx__dotfiles_root() {
    if [ -n "${DOTFILES_ROOT-}" ] && [ -d "${DOTFILES_ROOT}" ]; then
        printf '%s' "${DOTFILES_ROOT}"
        return 0
    fi

    if [ -n "${SHELL_COMMON-}" ]; then
        case "${SHELL_COMMON}" in
            */shell-common)
                devx__tmp_root=${SHELL_COMMON%/shell-common}
                if [ -n "${devx__tmp_root}" ] && [ -d "${devx__tmp_root}" ]; then
                    printf '%s' "${devx__tmp_root}"
                    unset devx__tmp_root
                    return 0
                fi
                ;;
        esac
    fi

    unset devx__tmp_root
    return 1
}

devx__find_root() {
    devx__dir=$PWD
    while [ "${devx__dir}" != "/" ]; do
        if [ -f "${devx__dir}/tools/dev.sh" ]; then
            printf '%s' "${devx__dir}"
            unset devx__dir
            return 0
        fi
        devx__dir=$(dirname "${devx__dir}")
    done
    unset devx__dir
    return 1
}

devx__usage() {
    if devx__have ux_section && devx__have ux_bullet; then
        ux_section "devx"
        devx__log_info "Usage: devx <command>"

        ux_section "Commands"
        ux_bullet "stat        - Show dotfiles repo statistics"
        ux_bullet "<command>    - Delegated to ./tools/dev.sh in project root"

        ux_section "Notes"
        ux_bullet "Project root is discovered by walking up to find tools/dev.sh"
        ux_bullet "SSOT: out of scope for this command"
        return 0
    fi

    printf '%s\n' "Usage: devx <command>"
    printf '%s\n' ""
    printf '%s\n' "Commands:"
    printf '%s\n' "  stat        Show dotfiles repo statistics"
    printf '%s\n' "  <command>   Delegated to ./tools/dev.sh in project root"
}

devx__run_repo_stats() {
    devx__repo_root=$(devx__dotfiles_root 2>/dev/null || printf '')
    if [ -z "${devx__repo_root}" ]; then
        devx__log_err "DOTFILES_ROOT/SHELL_COMMON not set; cannot locate dotfiles repo"
        unset devx__repo_root
        return 1
    fi

    devx__tool_path="${devx__repo_root}/shell-common/tools/custom/repo_stats.sh"
    if [ ! -f "${devx__tool_path}" ]; then
        devx__log_err "Could not find repo_stats.sh at ${devx__tool_path}"
        unset devx__repo_root devx__tool_path
        return 1
    fi

    if ! devx__have bash; then
        devx__log_err "bash is required to run ${devx__tool_path}"
        unset devx__repo_root devx__tool_path
        return 1
    fi

    bash "${devx__tool_path}" "$@"
    devx__rc=$?
    unset devx__repo_root devx__tool_path
    return "${devx__rc}"
}

devx__main_impl() {
    if [ $# -eq 0 ]; then
        devx__usage
        return 2
    fi

    case "$1" in
        -h|--help|help)
            devx__usage
            return 0
            ;;
        stat)
            shift
            devx__run_repo_stats "$@"
            return $?
            ;;
    esac

    if ! devx__have bash; then
        devx__log_err "bash is required to run tools/dev.sh"
        return 1
    fi

    devx__cwd=$PWD
    devx__root=$(devx__find_root 2>/dev/null) || devx__root=""
    if [ -z "${devx__root}" ]; then
        devx__log_err "Could not find tools/dev.sh from ${devx__cwd}"
        unset devx__cwd devx__root
        return 1
    fi

    devx__use_ns=0
    devx__t_start_ns=$(date +%s%N 2>/dev/null || printf '')
    if devx__is_digits "${devx__t_start_ns}"; then
        devx__use_ns=1
    else
        devx__t_start_s=$(date +%s 2>/dev/null || printf '0')
    fi

    devx__cmd_str=$*
    devx__log_info "from='${devx__cwd}' -> root='${devx__root}' cmd='${devx__cmd_str}'"
    devx__log_run "${devx__root}/tools/dev.sh ${devx__cmd_str}"

    (cd "${devx__root}" && bash "tools/dev.sh" "$@")
    devx__rc=$?

    devx__dur_ms=""
    if [ "${devx__use_ns}" = "1" ]; then
        devx__t_end_ns=$(date +%s%N 2>/dev/null || printf '')
        if devx__is_digits "${devx__t_end_ns}"; then
            devx__dur_ms=$(((devx__t_end_ns - devx__t_start_ns) / 1000000))
        fi
    else
        devx__t_end_s=$(date +%s 2>/dev/null || printf '0')
        if devx__is_digits "${devx__t_start_s}" && devx__is_digits "${devx__t_end_s}"; then
            devx__dur_ms=$(((devx__t_end_s - devx__t_start_s) * 1000))
        fi
    fi

    if [ -n "${devx__dur_ms}" ]; then
        devx__dur_str="${devx__dur_ms}ms"
    else
        devx__dur_str="(duration unavailable)"
    fi

    if [ "${devx__rc}" -eq 0 ]; then
        devx__log_ok "exit_code=0 duration=${devx__dur_str}"
    else
        devx__log_err "exit_code=${devx__rc} duration=${devx__dur_str}"
    fi

    unset devx__cwd devx__root devx__use_ns devx__t_start_ns devx__t_start_s devx__t_end_ns devx__t_end_s
    unset devx__cmd_str devx__dur_ms devx__dur_str

    return "${devx__rc}"
}

devx() {
    devx__main_impl "$@"
}
