#!/bin/sh
# shell-common/functions/devx.sh
# Dev helper — Type 2A positional dispatcher (issue #726 / #722 PR 2).
#
# Routes sub-commands to `mise run <task>` for lint/fix and to in-process
# helpers for repo-internal checks (lint-helpfunc / lint-deadcode / stat).
# Replaces tools/dev.sh, absorbing its full sub-command surface. Unknown
# sub-commands fail fast (no passthrough) per command-design-pattern.md §6.
#
# Help lives in devx_help.sh (no `devx-help` alias — see §7.6.1 deviation
# documented in devx_help.sh and PR body for #726).

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# ============================================================================
# Internal helpers
# ============================================================================

_devx_have() {
    command -v "$1" >/dev/null 2>&1
}

# Resolve the dotfiles repo root. Preference: DOTFILES_ROOT env, then
# SHELL_COMMON parent, then walking up from PWD looking for mise.toml.
_devx_dotfiles_root() {
    if [ -n "${DOTFILES_ROOT-}" ] && [ -d "${DOTFILES_ROOT}" ]; then
        printf '%s' "${DOTFILES_ROOT}"
        return 0
    fi

    if [ -n "${SHELL_COMMON-}" ]; then
        case "${SHELL_COMMON}" in
            */shell-common)
                _devx_tmp_root=${SHELL_COMMON%/shell-common}
                if [ -d "${_devx_tmp_root}" ]; then
                    printf '%s' "${_devx_tmp_root}"
                    unset _devx_tmp_root
                    return 0
                fi
                ;;
        esac
    fi

    _devx_dir=$PWD
    while [ "${_devx_dir}" != "/" ]; do
        if [ -f "${_devx_dir}/mise.toml" ]; then
            printf '%s' "${_devx_dir}"
            unset _devx_dir _devx_tmp_root
            return 0
        fi
        _devx_dir=$(dirname "${_devx_dir}")
    done

    unset _devx_dir _devx_tmp_root
    return 1
}

_devx_require_mise() {
    if ! _devx_have mise; then
        ux_error "mise not found — install: curl https://mise.run | sh"
        ux_info "Then run: mise install"
        return 1
    fi
}

# Run a mise task from the dotfiles repo root. Args: <task> [extra-args...]
_devx_run_mise() {
    _devx_require_mise || return 1
    _devx_root=$(_devx_dotfiles_root 2>/dev/null) || {
        ux_error "Cannot locate dotfiles repo (set DOTFILES_ROOT or run inside the repo)"
        unset _devx_root
        return 1
    }
    (cd "${_devx_root}" && mise run "$@")
    _devx_rc=$?
    unset _devx_root
    return "${_devx_rc}"
}

# ============================================================================
# Sub-command implementations
# ============================================================================

_devx_lint() {
    _devx_run_mise lint "$@"
}

_devx_fix() {
    _devx_run_mise fix "$@"
}

# `devx fmt` / `devx format` — routed to fix with a one-time deprecation
# warning per issue #726 AC.
_devx_fmt_deprecated() {
    ux_warning "'devx fmt' / 'devx format' is deprecated — use 'devx fix' (mise run fix)."
    _devx_fix "$@"
}

_devx_stat() {
    _devx_root=$(_devx_dotfiles_root 2>/dev/null) || {
        ux_error "DOTFILES_ROOT/SHELL_COMMON not set; cannot locate dotfiles repo"
        unset _devx_root
        return 1
    }
    _devx_tool="${_devx_root}/shell-common/tools/custom/repo_stats.sh"
    if [ ! -f "${_devx_tool}" ]; then
        ux_error "Missing: ${_devx_tool}"
        unset _devx_root _devx_tool
        return 1
    fi
    if ! _devx_have bash; then
        ux_error "bash is required to run ${_devx_tool}"
        unset _devx_root _devx_tool
        return 1
    fi

    bash "${_devx_tool}" "$@"
    _devx_rc=$?
    unset _devx_root _devx_tool
    return "${_devx_rc}"
}

# Audit shell-common/functions/*.sh for public *help functions that are
# missing from HELP_DESCRIPTIONS in my_help.sh. Mirrors the legacy
# _check_help_integrity from the deleted tools/dev.sh, ported to POSIX.
_devx_lint_helpfunc() {
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    _devx_root=$(_devx_dotfiles_root 2>/dev/null) || {
        ux_error "DOTFILES_ROOT/SHELL_COMMON not set; cannot locate dotfiles repo"
        unset _devx_root
        return 1
    }
    _devx_my_help="${_devx_root}/shell-common/functions/my_help.sh"
    if [ ! -f "${_devx_my_help}" ]; then
        ux_error "Missing: ${_devx_my_help}"
        unset _devx_root _devx_my_help
        return 1
    fi

    _devx_files=$(find "${_devx_root}/shell-common/functions" -name "*.sh" -type f 2>/dev/null)
    _devx_found=0
    _devx_checked=0
    _devx_violations=""

    while IFS= read -r _devx_file; do
        [ -n "${_devx_file}" ] || continue
        # Public *help function names — ending in "help", not starting with `_`.
        _devx_funcs=$(grep -E '^[[:space:]]*(function[[:space:]]+)?[a-zA-Z][a-zA-Z0-9_-]*help[[:space:]]*(\(\))?[[:space:]]*\{' "${_devx_file}" 2>/dev/null \
            | sed -E 's/^[[:space:]]*(function[[:space:]]+)?//; s/[[:space:]]*(\(\))?[[:space:]]*\{.*//' \
            | grep -v '^_')

        while IFS= read -r _devx_func; do
            [ -n "${_devx_func}" ] || continue
            _devx_checked=$((_devx_checked + 1))

            _devx_dash=$(printf '%s' "${_devx_func}" | tr '_' '-')
            _devx_underscore=$(printf '%s' "${_devx_func}" | tr '-' '_')

            if ! grep -Eq "HELP_DESCRIPTIONS\[\"?(${_devx_func}|${_devx_dash}|${_devx_underscore})\"?\]" "${_devx_my_help}" 2>/dev/null; then
                _devx_rel="${_devx_file#"${_devx_root}/"}"
                _devx_violations="${_devx_violations}  - ${_devx_rel}: '${_devx_func}' not registered in HELP_DESCRIPTIONS
"
                _devx_found=$((_devx_found + 1))
            fi
        done <<EOF
${_devx_funcs}
EOF
    done <<EOF
${_devx_files}
EOF

    if [ "${_devx_checked}" -eq 0 ]; then
        ux_info "No public *help functions found in shell-common/functions/."
        unset _devx_root _devx_my_help _devx_files _devx_file _devx_funcs _devx_func _devx_dash _devx_underscore _devx_rel _devx_violations _devx_found _devx_checked
        return 0
    fi

    if [ "${_devx_found}" -eq 0 ]; then
        ux_success "All ${_devx_checked} public help functions are registered in HELP_DESCRIPTIONS."
        unset _devx_root _devx_my_help _devx_files _devx_file _devx_funcs _devx_func _devx_dash _devx_underscore _devx_rel _devx_violations _devx_found _devx_checked
        return 0
    fi

    ux_warning "Found ${_devx_found} unregistered help function(s) out of ${_devx_checked} checked:"
    printf '%s' "${_devx_violations}"
    unset _devx_root _devx_my_help _devx_files _devx_file _devx_funcs _devx_func _devx_dash _devx_underscore _devx_rel _devx_violations _devx_found _devx_checked
    return 1
}

# Flag _internal functions in shell-common/functions/*.sh that are
# referenced only once (their own definition) across the repo — candidates
# for removal. Ported from the legacy _check_deadcode in tools/dev.sh.
_devx_lint_deadcode() {
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    _devx_root=$(_devx_dotfiles_root 2>/dev/null) || {
        ux_error "DOTFILES_ROOT/SHELL_COMMON not set; cannot locate dotfiles repo"
        unset _devx_root
        return 1
    }
    _devx_fnsdir="${_devx_root}/shell-common/functions"
    if [ ! -d "${_devx_fnsdir}" ]; then
        ux_error "Missing: ${_devx_fnsdir}"
        unset _devx_root _devx_fnsdir
        return 1
    fi

    _devx_files=$(find "${_devx_fnsdir}" -name "*.sh" -type f 2>/dev/null)
    _devx_found=0
    _devx_checked=0
    _devx_report=""

    while IFS= read -r _devx_file; do
        [ -n "${_devx_file}" ] || continue
        _devx_hits=$(grep -n "^[[:space:]]*_[a-z_][a-z0-9_]*()[[:space:]]*{" "${_devx_file}" 2>/dev/null)

        while IFS= read -r _devx_line; do
            [ -n "${_devx_line}" ] || continue
            _devx_lineno="${_devx_line%%:*}"
            _devx_text="${_devx_line#*:}"
            _devx_func=$(printf '%s' "${_devx_text}" | sed -E 's/^[[:space:]]*(_[a-z_][a-z0-9_]*)\(\).*/\1/')
            [ -n "${_devx_func}" ] || continue
            _devx_checked=$((_devx_checked + 1))

            _devx_count=$(grep -rw "${_devx_func}" "${_devx_root}" \
                --include="*.sh" --include="*.zsh" --include="*.bash" 2>/dev/null \
                | wc -l)

            if [ "${_devx_count}" -eq 1 ]; then
                _devx_rel="${_devx_file#"${_devx_root}/"}"
                _devx_report="${_devx_report}  - ${_devx_rel}:${_devx_lineno} potentially unused: ${_devx_func}()
"
                _devx_found=$((_devx_found + 1))
            fi
        done <<EOF
${_devx_hits}
EOF
    done <<EOF
${_devx_files}
EOF

    if [ "${_devx_checked}" -eq 0 ]; then
        ux_info "No _internal functions found in shell-common/functions/."
        unset _devx_root _devx_fnsdir _devx_files _devx_file _devx_hits _devx_line _devx_lineno _devx_text _devx_func _devx_count _devx_rel _devx_report _devx_found _devx_checked
        return 0
    fi

    if [ "${_devx_found}" -eq 0 ]; then
        ux_success "All ${_devx_checked} internal functions are in use."
        unset _devx_root _devx_fnsdir _devx_files _devx_file _devx_hits _devx_line _devx_lineno _devx_text _devx_func _devx_count _devx_rel _devx_report _devx_found _devx_checked
        return 0
    fi

    ux_warning "Found ${_devx_found} potentially unused internal function(s) out of ${_devx_checked} checked:"
    printf '%s' "${_devx_report}"
    unset _devx_root _devx_fnsdir _devx_files _devx_file _devx_hits _devx_line _devx_lineno _devx_text _devx_func _devx_count _devx_rel _devx_report _devx_found _devx_checked
    return 1
}

# ============================================================================
# devx — Type 2A dispatcher
# ============================================================================
devx() {
    case "${1:-}" in
        lint)          shift; _devx_lint "$@" ;;
        fix)           shift; _devx_fix "$@" ;;
        fmt|format)    shift; _devx_fmt_deprecated "$@" ;;
        lint-helpfunc) shift; _devx_lint_helpfunc "$@" ;;
        lint-deadcode) shift; _devx_lint_deadcode "$@" ;;
        stat)          shift; _devx_stat "$@" ;;
        -h|--help|help|"")
            [ $# -gt 0 ] && shift
            devx_help "$@"
            ;;
        *)
            ux_error "Unknown command: $1"
            ux_info "Run: devx help"
            return 1
            ;;
    esac
}
