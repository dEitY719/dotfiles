#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_pr_lint.sh
# Optional pre-push lint guard for the `gh:pr` skill (issue #396, design
# in #384#issuecomment-4403809305).
#
# Detects repo lint capability (tox > shellcheck > actionlint > pre-commit),
# runs detected tools against the PR's changed files only, and hard-fails on
# any lint error. Bypass via GH_PR_LINT_BYPASS=1.
#
# Usage:
#   _gh_pr_lint_run <base-branch>
#
# Env overrides:
#   GH_PR_LINT_BYPASS=1            — skip the entire guard (escape hatch)
#   GH_PR_LINT_TOOLS=auto          — auto-detect (default)
#   GH_PR_LINT_TOOLS=tox,shellcheck — comma-list of tools to force-run
#                                    (still subject to per-tool detection)
#
# Return codes:
#   0 — all detected tools passed, or skipped (no tools / bypass / no changes)
#   1 — at least one tool failed; caller should block the push
#   2 — usage error (missing base-branch argument)

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_gh_pr_lint__log() {
    printf '[lint guard] %s\n' "$*"
}

_gh_pr_lint__has_tox_envs() {
    # tox.ini exists AND declares at least one of the lint envs we recognise.
    [ -f tox.ini ] || return 1
    grep -qE '^\[testenv:(ruff|mdlint|shellcheck|shfmt|actionlint)\]' tox.ini
}

_gh_pr_lint__tox_env_list() {
    # Print a comma-separated list of declared lint envs in tox.ini, in
    # priority order (ruff, mdlint, shellcheck, shfmt, actionlint).
    [ -f tox.ini ] || return 0
    _envs=""
    for _e in ruff mdlint shellcheck shfmt actionlint; do
        if grep -qE "^\[testenv:$_e\]" tox.ini; then
            _envs="${_envs:+$_envs,}$_e"
        fi
    done
    printf '%s' "$_envs"
    unset _envs _e
}

_gh_pr_lint__filter_changed() {
    # Stdin: list of changed files (one per line).
    # Args:  glob pattern(s) to keep (e.g. '*.sh', '.github/workflows/*').
    # Stdout: filtered subset, preserving order.
    _pat="$1"
    while IFS= read -r _f; do
        # Use a case-glob — POSIX, no GNU-only flags.
        # shellcheck disable=SC2254
        case "$_f" in
            $_pat) printf '%s\n' "$_f" ;;
        esac
    done
    unset _pat _f
}

_gh_pr_lint__want_tool() {
    # 0 if $GH_PR_LINT_TOOLS is unset or "auto", or if $1 appears in the
    # comma-separated list. 1 otherwise.
    #
    # Note the `${VAR-default}` form (no `:`) — empty-string and unset are
    # treated differently. Empty (`GH_PR_LINT_TOOLS=`) means "no tools
    # match", which is the documented soft-disable knob in lint-guard.md.
    # Unset falls through to "auto" → all detected tools run.
    _tools="${GH_PR_LINT_TOOLS-auto}"
    case "$_tools" in
        auto) unset _tools; return 0 ;;
        "")   unset _tools; return 1 ;;
    esac
    case ",$_tools," in
        *",$1,"*) unset _tools; return 0 ;;
    esac
    unset _tools
    return 1
}

_gh_pr_lint_run() {
    _base="$1"
    if [ -z "$_base" ]; then
        printf '[gh-pr-lint] usage: _gh_pr_lint_run <base-branch>\n' >&2
        unset _base
        return 2
    fi

    if [ "${GH_PR_LINT_BYPASS:-0}" = "1" ]; then
        _gh_pr_lint__log "bypassed (GH_PR_LINT_BYPASS=1)"
        unset _base
        return 0
    fi

    # Compute the PR's changed-file set against the base branch.
    _changed=$(git diff --name-only "$_base...HEAD" 2>/dev/null)
    if [ -z "$_changed" ]; then
        _gh_pr_lint__log "no changed files vs $_base — skip"
        unset _base _changed
        return 0
    fi

    _ran_any=0
    _failed=0

    # ---- tox (highest priority) ----------------------------------------
    if _gh_pr_lint__want_tool tox \
        && command -v tox >/dev/null 2>&1 \
        && _gh_pr_lint__has_tox_envs; then
        _envs=$(_gh_pr_lint__tox_env_list)
        if [ -n "$_envs" ]; then
            _gh_pr_lint__log "running tox -e $_envs"
            if tox -e "$_envs"; then
                _gh_pr_lint__log "tox passed"
            else
                _gh_pr_lint__log "tox FAILED"
                _failed=1
            fi
            _ran_any=1
        fi
        unset _envs
    fi

    # When tox already covered the repo, individual fallbacks are redundant.
    if [ "$_ran_any" = "0" ]; then
        # ---- shellcheck (changed *.sh) ---------------------------------
        if _gh_pr_lint__want_tool shellcheck \
            && command -v shellcheck >/dev/null 2>&1; then
            _sh_files=$(printf '%s\n' "$_changed" \
                | _gh_pr_lint__filter_changed '*.sh')
            if [ -n "$_sh_files" ]; then
                _gh_pr_lint__log "running shellcheck on $(printf '%s\n' "$_sh_files" | wc -l | tr -d ' ') file(s)"
                # POSIX-safe: build positional params one-by-one so paths
                # with spaces survive (xargs would word-split).
                set --
                while IFS= read -r _f; do
                    [ -n "$_f" ] && set -- "$@" "$_f"
                done <<EOF
$_sh_files
EOF
                if shellcheck -x -S warning "$@"; then
                    _gh_pr_lint__log "shellcheck passed"
                else
                    _gh_pr_lint__log "shellcheck FAILED"
                    _failed=1
                fi
                _ran_any=1
                unset _f
            fi
            unset _sh_files
        fi

        # ---- actionlint (changed .github/workflows/*) ------------------
        if _gh_pr_lint__want_tool actionlint \
            && command -v actionlint >/dev/null 2>&1; then
            _wf_files=$(printf '%s\n' "$_changed" \
                | _gh_pr_lint__filter_changed '.github/workflows/*')
            if [ -n "$_wf_files" ]; then
                _gh_pr_lint__log "running actionlint on $(printf '%s\n' "$_wf_files" | wc -l | tr -d ' ') file(s)"
                set --
                while IFS= read -r _f; do
                    [ -n "$_f" ] && set -- "$@" "$_f"
                done <<EOF
$_wf_files
EOF
                if actionlint "$@"; then
                    _gh_pr_lint__log "actionlint passed"
                else
                    _gh_pr_lint__log "actionlint FAILED"
                    _failed=1
                fi
                _ran_any=1
                unset _f
            fi
            unset _wf_files
        fi

        # ---- pre-commit (changed files) --------------------------------
        if _gh_pr_lint__want_tool pre-commit \
            && [ -f .pre-commit-config.yaml ] \
            && command -v pre-commit >/dev/null 2>&1; then
            _gh_pr_lint__log "running pre-commit on changed files"
            set --
            while IFS= read -r _f; do
                [ -n "$_f" ] && set -- "$@" "$_f"
            done <<EOF
$_changed
EOF
            if pre-commit run --files "$@"; then
                _gh_pr_lint__log "pre-commit passed"
            else
                _gh_pr_lint__log "pre-commit FAILED"
                _failed=1
            fi
            _ran_any=1
            unset _f
        fi
    fi

    if [ "$_ran_any" = "0" ]; then
        _gh_pr_lint__log "no lint tools detected — skip"
        unset _base _changed _ran_any _failed
        return 0
    fi

    if [ "$_failed" = "1" ]; then
        printf '\n' >&2
        _gh_pr_lint__log "FAILED — fix lint errors and re-run /gh:pr, or set GH_PR_LINT_BYPASS=1 to skip" >&2
        unset _base _changed _ran_any _failed
        return 1
    fi

    unset _base _changed _ran_any _failed
    return 0
}
