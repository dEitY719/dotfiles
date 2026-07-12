#!/bin/sh
# shell-common/functions/git_restore.sh
# grs — friendly `git restore` wrapper (Verdict + Next-action preflight).
#
# WHY this exists (issue #1146):
# Raw `git restore` is unhelpful in the common mistake cases. It either
# prints a bare pathspec error (untracked path) without saying *why* it
# failed or *what to do next*, or — worse — it silently succeeds as a
# no-op / touches only the worktree when the user meant to unstage. Both
# hide the real problem from someone who has to re-derive `??` (untracked)
# semantics every time.
#
# This file overrides the `grs` alias (Oh My Zsh git plugin + the explicit
# `alias grs='git restore'` in shell-common/aliases/git.sh) with a shell
# function that runs a *preflight classification* BEFORE calling git —
# not a post-hoc error translation. Preflight is the only way to catch the
# cases git never errors on (no-op, staged-only). When nothing is wrong the
# function is transparent: it execs `git restore "$@"` with no extra output,
# identical exit code, indistinguishable from raw git.
#
# Kept in its own file (not folded into git.sh) to isolate responsibility,
# mirroring gh_host.sh's "explain the why" header style. Only `grs` is
# wrapped — `grss` / `grst` (OMZ) and raw `git` are untouched, so the
# `--staged` guidance can point at `grst` and we avoid wrapping raw git
# (side-effect / performance risk).

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# git.sh already unaliases its own set; grs lives here, so drop it here too.
unalias grs 2>/dev/null || true

# _grs_help — usage for the friendly restore wrapper.
_grs_help() {
    ux_header "grs — git restore (친절 래퍼)"
    ux_info "정상 케이스는 raw \`git restore\`와 동일하게 투명 통과합니다."
    ux_info "흔한 실수/모호 상황에서만 판정(Verdict)과 다음 명령(Next-action)을 안내합니다."
    ux_info ""
    ux_info "Usage:"
    ux_bullet "grs <path>...            워킹트리 변경 되돌리기 (preflight 검사)"
    ux_bullet "grs --staged <path>...   스테이지 해제 (= grst, 그대로 통과)"
    ux_bullet "grs -h | --help          이 도움말"
    ux_info ""
    ux_info "감지하는 상황:"
    ux_bullet_sub "untracked 경로   → restore 대상 아님, rm / git clean 안내"
    ux_bullet_sub "미존재 경로      → 오타 의심, git status 확인 안내"
    ux_bullet_sub "staged 만 변경   → grs 는 unstage 안 함, grs --staged 안내"
    ux_bullet_sub "변경 없음        → no-op 안내 (아무 것도 안 함)"
}

# grs — preflight-classify path args, then restore transparently or diagnose.
grs() {
    # zsh: run under POSIX word-splitting rules (git.sh convention).
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    case "${1-}" in
    -h | --help | help)
        _grs_help
        return 0
        ;;
    esac

    # Outside a git repo the plumbing below can't classify — fall back to
    # raw git so the user sees git's own error, unchanged.
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git restore "$@"
        return $?
    fi

    # Pass 1 — scan args: detect advanced flags, honour `--`, count paths.
    # Advanced flags (--staged / --source / --worktree / --patch and short
    # forms) mean the user knows what they're doing; trust them and pass
    # through without preflight. No path args → let git handle its usage error.
    _grs_advanced=0
    _grs_path_count=0
    _grs_after_ddash=0
    for _grs_arg in "$@"; do
        if [ "$_grs_after_ddash" -eq 1 ]; then
            _grs_path_count=$((_grs_path_count + 1))
            continue
        fi
        case "$_grs_arg" in
        --)
            _grs_after_ddash=1
            ;;
        --staged | -S | --worktree | -W | --source | -s | --source=* | --patch | -p)
            _grs_advanced=1
            ;;
        -*)
            : # other flag (e.g. --quiet, --overlay) — not a path
            ;;
        *)
            _grs_path_count=$((_grs_path_count + 1))
            ;;
        esac
    done

    if [ "$_grs_advanced" -eq 1 ] || [ "$_grs_path_count" -eq 0 ]; then
        git restore "$@"
        return $?
    fi

    # Pass 2 — classify each path arg into buckets (all git calls silent).
    _grs_nl='
'
    _grs_untracked="" # [사고] untracked & exists
    _grs_missing=""   # [사고] missing (typo?)
    _grs_staged=""    # [주의] staged-only, grs won't unstage
    _grs_normal=0     # has worktree diff → real restore target
    _grs_noop=0       # tracked but no changes at all

    _grs_after_ddash=0
    for _grs_arg in "$@"; do
        if [ "$_grs_after_ddash" -eq 0 ]; then
            case "$_grs_arg" in
            --)
                _grs_after_ddash=1
                continue
                ;;
            -*)
                continue # flag, not a path
                ;;
            esac
        fi
        _grs_p="$_grs_arg"

        if git ls-files --error-unmatch -- "$_grs_p" >/dev/null 2>&1; then
            # Tracked path.
            if ! git diff --quiet -- "$_grs_p" >/dev/null 2>&1; then
                _grs_normal=$((_grs_normal + 1)) # worktree diff present
            elif ! git diff --cached --quiet -- "$_grs_p" >/dev/null 2>&1; then
                _grs_staged="${_grs_staged}${_grs_p}${_grs_nl}" # staged only
            else
                _grs_noop=$((_grs_noop + 1)) # nothing to restore
            fi
        else
            # Not tracked.
            if [ -e "$_grs_p" ]; then
                _grs_untracked="${_grs_untracked}${_grs_p}${_grs_nl}"
            else
                _grs_missing="${_grs_missing}${_grs_p}${_grs_nl}"
            fi
        fi
    done

    # Gate — any accident (사고) or caution (주의) blocks the whole run so
    # the user fixes the args and re-runs (no confusing partial restore).
    if [ -n "$_grs_untracked" ] || [ -n "$_grs_missing" ] || [ -n "$_grs_staged" ]; then
        if [ -n "$_grs_untracked" ]; then
            ux_error "[사고] restore 대상이 아님 — untracked 경로 (git 이 추적하지 않음)"
            printf '%s' "$_grs_untracked" | while IFS= read -r _grs_p; do
                [ -n "$_grs_p" ] || continue
                if git check-ignore -q -- "$_grs_p" >/dev/null 2>&1; then
                    ux_bullet "삭제하려면: rm -rf -- $_grs_p  또는  git clean -fdx -- $_grs_p"
                else
                    ux_bullet "삭제하려면: rm -rf -- $_grs_p  또는  git clean -fd -- $_grs_p"
                fi
            done
        fi
        if [ -n "$_grs_missing" ]; then
            ux_error "[사고] 그런 경로 없음 — 오타 의심"
            printf '%s' "$_grs_missing" | while IFS= read -r _grs_p; do
                [ -n "$_grs_p" ] || continue
                ux_bullet "확인하려면: git status -- $_grs_p  (철자 점검)"
            done
        fi
        if [ -n "$_grs_staged" ]; then
            ux_warning "[주의] grs 는 unstage 하지 않음 — 스테이지된 변경만 있음"
            printf '%s' "$_grs_staged" | while IFS= read -r _grs_p; do
                [ -n "$_grs_p" ] || continue
                ux_bullet "언스테이지하려면: grs --staged -- $_grs_p  (= grst)"
            done
        fi
        return 1
    fi

    # No problems. All-no-op → one info line; otherwise transparent restore.
    if [ "$_grs_normal" -eq 0 ] && [ "$_grs_noop" -gt 0 ]; then
        ux_info "[정보] 되돌릴 변경 없음 (no-op) — 아무 것도 하지 않았습니다."
        return 0
    fi

    git restore "$@"
    return $?
}
