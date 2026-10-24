#!/bin/bash
# shell-common/tools/custom/avatar_watched_repos.sh
# Render the tracked avatar/watched-repos.public.json into this PC's
# avatar-issue-watcher watch list (#2285). The merge lives in
# dotfiles_tools.issue_watcher.watched_repos (docs/.ssot/shell-vs-python.md);
# this entrypoint only routes and prints.
#
# Usage: avatar_watched_repos.sh [--dry-run|-h|--help]
# Target: $IW_WATCHED_REPOS, else ~/.avatars/issue-watcher/watched-repos.json
# (the same default avatar_issue_watcher.sh reads).

# readlink -f: resolve a ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1

avatar_watched_repos_main() {
    local _dry="" _tracked _target _out _rc _kind _a _b _line

    case "${1:-}" in
    -h | --help | help)
        # shellcheck source=/dev/null
        DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/avatar_watched_repos_help.sh"
        avatar_watched_repos_help
        return 0
        ;;
    --dry-run) _dry="--dry-run" ;;
    "") ;;
    *)
        ux_error "unknown option: $1 (see --help)"
        return 2
        ;;
    esac

    _tracked="${DOTFILES_ROOT}/avatar/watched-repos.public.json"
    _target="${IW_WATCHED_REPOS:-${HOME}/.avatars/issue-watcher/watched-repos.json}"

    if ! command -v python3 >/dev/null 2>&1; then
        ux_error "python3 not found — cannot render the watch list"
        return 1
    fi

    _out=$(cd "${DOTFILES_ROOT}/tools/py" && python3 -E -s -m \
        dotfiles_tools.issue_watcher.watched_repos render \
        "${_tracked}" "${_target}" "${HOME}" ${_dry})
    _rc=$?
    if [ "${_rc}" -ne 0 ]; then
        ux_error "watch list render failed (exit ${_rc}); ${_target} left untouched"
        return 1
    fi

    while IFS= read -r _line; do
        _kind="${_line%%$'\t'*}"
        _a="${_line#*$'\t'}"
        _b="${_a#*$'\t'}"
        _a="${_a%%$'\t'*}"
        case "${_kind}" in
        skip) ux_warning "skip ${_a}: ${_b} not found" ;;
        # Raw diff body is data (like git diff), not decorated status output.
        diff) printf '%s\n' "${_line#*$'\t'}" ;;
        unchanged) ux_success "watch list already up to date: ${_target}" ;;
        would-write) ux_info "dry-run: ${_target} would change (not written)" ;;
        written)
            ux_success "watch list written: ${_target}"
            [ "${_a}" = "-" ] || ux_info "backup: ${_a}"
            ;;
        esac
    done <<EOF
${_out}
EOF
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    avatar_watched_repos_main "$@"
fi
