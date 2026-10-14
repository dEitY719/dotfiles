#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/git_worktree_spawn.sh
# gwt spawn / teardown — split from git_worktree.sh (#2156). The gwt
# dispatcher and the helpers both use (git_worktree_add, _gwt_report_no_git,
# _gwt_branch_merged, _gwt_claude_lock_pid) stay in git_worktree.sh; AI
# launch (agent command, tmux window, mise trust) is lib/agent_launch.sh.

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

# shellcheck source=/dev/null
. "${SHELL_COMMON:-${DOTFILES_ROOT:-$HOME/dotfiles}/shell-common}/lib/agent_launch.sh"

# ============================================================================
# Worktree spawn — auto-index, auto-branch, log
# Grammar (#650): option-only; --wt-name is required, --prompt is trailing.
# Usage: git_worktree_spawn [OPTIONS] --wt-name <slug> [--prompt <text...>]
# ============================================================================
_git_worktree_spawn_show_help() {
    ux_header "gwt spawn - create a named worktree"
    ux_info "Usage: gwt spawn [OPTIONS] --wt-name <slug> [--prompt <text...>]"
    ux_info ""
    ux_info "Required:"
    ux_info "  --wt-name <slug> Worktree name. Safe chars only:"
    ux_info "                   no '/', no spaces, no leading dash."
    ux_info "                   Examples: issue-11, login-fix, feature-x"
    ux_info ""
    ux_info "Optional (order-independent):"
    ux_info "  --base <ref>     Base branch/commit (default: origin/main)"
    ux_info "  --tmux           Auto-create tmux session/window with 3-pane layout"
    ux_info "  --launch         cd into the new worktree and run the agent's yolo"
    ux_info "                   command in the current shell."
    ux_info "                   Mutually exclusive with --tmux."
    ux_info "  --bg             Dispatch claude in background mode (Agent View, #640)."
    ux_info "                   Requires --launch or --tmux. Only with --ai claude."
    ux_info "  --ai <agent>     AI agent (default: claude)."
    ux_info "                   Known: claude, codex, agy, opencode, cursor, copilot"
    ux_info "  --user <account> Claude account for --tmux/--launch (issue #295)."
    ux_info "                   Only valid with --ai claude."
    ux_info ""
    ux_info "Trailing (must be LAST if used):"
    ux_info "  --prompt <text...>"
    ux_info "                   Initial task for the AI. All remaining tokens are"
    ux_info "                   joined with single spaces. No quotes needed."
    ux_info ""
    ux_info "Examples:"
    ux_info "  gwt spawn --wt-name issue-11"
    ux_info "  gwt spawn --launch --wt-name issue-11"
    ux_info "  gwt spawn --launch --ai claude --user work --wt-name issue-717 --prompt 이슈 717 요약해"
    ux_info "  gwt spawn --launch --bg --wt-name issue-718"
    ux_info "  gwt spawn --launch --bg --wt-name issue-718 --prompt 오늘의 날씨 검색해"
    ux_info "  gwt spawn --tmux   --user work --wt-name feat-x"
    ux_info ""
    ux_info "Removed (#650):"
    ux_info "  Positional <name>     -> use --wt-name <slug>"
    ux_info "  --task <slug>         -> removed (branch-suffix dropped)"
    ux_info "  --bg <task>           -> use --prompt <text...>"
}

git_worktree_spawn() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local base="" name="" use_tmux=0 use_launch=0 use_bg=0 \
          agent="claude" account="" prompt="" prompt_set=0 prompt_warned=0

    # Parse arguments. New grammar (#650): option-only; --wt-name is the
    # required name, --prompt is the trailing AI initial-task flag that
    # consumes every remaining token.
    while [ $# -gt 0 ]; do
        # Once --prompt has fired, every subsequent token (including
        # things that look like flags) becomes part of the prompt text
        # (AC-9). AC-10: warn ONCE if a recognized flag is absorbed so
        # the user knows their flag did not take effect.
        if [ "$prompt_set" = 1 ]; then
            case "$1" in
                --launch|--tmux|--bg|--ai|--user|--base|--wt-name|--task|--prompt|-h|--help)
                    if [ "$prompt_warned" = 0 ]; then
                        ux_warning "Token '$1' after --prompt is consumed as prompt text (use quotes if intentional)" >&2
                        prompt_warned=1
                    fi
                    ;;
            esac
            if [ -z "$prompt" ]; then
                prompt="$1"
            else
                prompt="$prompt $1"
            fi
            shift
            continue
        fi

        case "$1" in
            -h|--help)
                _git_worktree_spawn_show_help
                return 0
                ;;
            --wt-name)
                if [ $# -lt 2 ] || [ -z "${2-}" ]; then
                    ux_error "--wt-name requires a value"
                    return 1
                fi
                name="$2"; shift 2
                ;;
            --base)
                # `[ "${2#-}" != "$2" ]` rejects a next token that starts
                # with `-` so a stray `--base --launch` does not silently
                # absorb the following flag as the base value (PR #652
                # gemini-code-assist review).
                if [ $# -lt 2 ] || [ -z "${2-}" ] || [ "${2#-}" != "$2" ]; then
                    ux_error "--base requires a value"; return 1
                fi
                base="$2"; shift 2
                ;;
            --ai)
                if [ $# -lt 2 ] || [ -z "${2-}" ] || [ "${2#-}" != "$2" ]; then
                    ux_error "--ai requires a value"; return 1
                fi
                agent="$2"; shift 2
                ;;
            --user)
                if [ $# -lt 2 ] || [ -z "${2-}" ] || [ "${2#-}" != "$2" ]; then
                    ux_error "--user requires a value"; return 1
                fi
                account="$2"; shift 2
                ;;
            --tmux) use_tmux=1; shift ;;
            --launch) use_launch=1; shift ;;
            --bg)
                # Boolean since #650 — the optional positional task was
                # removed in favor of --prompt. AC-11.
                use_bg=1
                shift
                ;;
            --prompt)
                # All remaining tokens become the prompt text (AC-9).
                prompt_set=1
                shift
                ;;
            --task)
                # Hard-break migration error (#650 / AC-7). The branch-
                # suffix feature was removed; if the user wanted an AI
                # initial prompt they want --prompt now.
                ux_error "--task flag has been removed (branch-suffix feature dropped)."
                ux_info  "For AI initial prompt use --prompt:"
                ux_info  "  gwt spawn --wt-name <slug> --prompt <text...>"
                return 1
                ;;
            -*)
                ux_error "Unknown option: $1"
                echo ""
                _git_worktree_spawn_show_help
                return 1
                ;;
            *)
                # Hard-break migration error (#650 / AC-6). Build a
                # corrected suggestion that carries any flags the user
                # had already typed forward, with --wt-name appended at
                # the end so it is unambiguous.
                local _gwt_bad_name="$1"
                shift
                local _gwt_hint_flags=""
                while [ $# -gt 0 ]; do
                    _gwt_hint_flags="$_gwt_hint_flags $1"
                    shift
                done
                ux_error "Positional <name> is no longer supported."
                ux_info  "Use --wt-name <slug>:"
                ux_info  "  gwt spawn${_gwt_hint_flags} --wt-name '${_gwt_bad_name}'"
                return 1
                ;;
        esac
    done

    # --wt-name is required
    if [ -z "$name" ]; then
        ux_error "<name> is required"
        echo ""
        ux_info "Hint: use --wt-name <slug>"
        return 1
    fi

    # Validate name: no path separators, no spaces, no leading dash
    case "$name" in
        -* | */* | *" "*)
            ux_error "Invalid name: '$name' (no '/', no spaces, no leading dash)"
            return 1
            ;;
    esac

    # --tmux and --launch are mutually exclusive (tmux opens a new pane,
    # --launch runs in the current shell — combining them is incoherent).
    if [ "$use_tmux" = 1 ] && [ "$use_launch" = 1 ]; then
        ux_error "--tmux and --launch are mutually exclusive"
        echo ""
        _git_worktree_spawn_show_help
        return 1
    fi

    # --bg dispatches the agent in background mode, so it needs --launch or
    # --tmux to actually run something. Without either, the worktree is
    # created but nothing is dispatched (#640).
    if [ "$use_bg" = 1 ] && [ "$use_tmux" != 1 ] && [ "$use_launch" != 1 ]; then
        ux_error "--bg requires --launch or --tmux"
        return 1
    fi

    # --bg currently only wires through claude (the only agent with Agent
    # View / background dispatch). Other agents have no equivalent flag.
    if [ "$use_bg" = 1 ] && [ "$agent" != "claude" ]; then
        ux_error "--bg is only supported with --ai claude (got: --ai $agent)"
        return 1
    fi

    # Validate --tmux dependency
    if [ "$use_tmux" = 1 ] && ! command -v tmux >/dev/null 2>&1; then
        ux_error "tmux is not installed (required for --tmux)"
        return 1
    fi

    # Validate --ai: must be a known AI agent (only when tmux/launch will use it)
    if { [ "$use_tmux" = 1 ] || [ "$use_launch" = 1 ]; } && ! _ts_known_agent "$agent"; then
        ux_error "Unknown agent: $agent"
        ux_info "Available: claude, codex, agy, opencode, cursor, copilot"
        return 1
    fi

    # Validate --user (issue #295): only meaningful with claude + tmux/launch.
    # Other agents have no multi-account support so combining them is a typo
    # we want to surface, not silently ignore.
    if [ -n "$account" ]; then
        if [ "$use_tmux" != 1 ] && [ "$use_launch" != 1 ]; then
            ux_error "--user requires --tmux or --launch"
            return 1
        fi
        if [ "$agent" != "claude" ]; then
            ux_error "--user is only supported with --ai claude (got: --ai $agent)"
            return 1
        fi
        # SSOT account validation — reuse claude_yolo's resolver and error shape.
        if ! _claude_resolve_account "$account" >/dev/null 2>&1; then
            ux_error "Unknown account: $account"
            ux_info  "Available: $(_claude_resolve_account --list | tr '\n' ' ')"
            return 1
        fi
    fi

    # Must be inside a git repo, NOT a worktree
    local git_common git_dir
    git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || {
        _gwt_report_no_git
        return 1
    }
    git_dir="$(git rev-parse --git-dir)"
    if [ "$git_dir" != "$git_common" ]; then
        ux_error "Cannot spawn from inside a worktree. Run from the main repo."
        return 1
    fi

    # Resolve the base ref early so we can verify it before doing any work.
    # Verifying the resolved $base (rather than HEAD directly) avoids a false
    # positive when HEAD is unborn but a valid ref like origin/main exists
    # (e.g. a fresh clone that fetched but never checked out), and it also
    # catches an invalid user-supplied --base here instead of letting
    # `git worktree add` die with a cryptic raw error later
    # (gemini-code-assist review, PR #1020).
    if [ -z "$base" ]; then
        if git rev-parse --verify --quiet "origin/main" >/dev/null 2>&1; then
            base="origin/main"
        elif git rev-parse --verify --quiet "main" >/dev/null 2>&1; then
            base="main"
        else
            base="HEAD"
        fi
    fi

    if ! git rev-parse --verify --quiet "$base" >/dev/null 2>&1; then
        if [ "$base" = "HEAD" ]; then
            # Unborn HEAD with no other base — a freshly `git init`-ed repo.
            ux_error "Cannot spawn a worktree: this repository has no commits yet."
            ux_info "A git worktree needs at least one commit to branch from."
            ux_info "Create an initial commit first, then re-run gwt spawn:"
            ux_info '  git commit --allow-empty -m "chore: initial commit to allow empty repository"'
        else
            ux_error "Cannot spawn a worktree: base ref '$base' is invalid."
            ux_info "Pass an existing branch/commit via --base, or omit it to use origin/main."
        fi
        return 1
    fi

    # Compute project, parent, next index
    local project parent next_index=1
    project="$(basename "$(git rev-parse --show-toplevel)")"
    parent="$(dirname "$(git rev-parse --show-toplevel)")"

    for dir in "$parent/${project}-${name}"-*/; do
        if [ -d "$dir" ]; then
            local n="${dir##*-}"
            n="${n%/}"
            case "$n" in
                "" | *[!0-9]*) continue ;;
            esac
            if [ "$n" -ge "$next_index" ]; then
                next_index=$((n + 1))
            fi
        fi
    done

    # Branch name + path must both be unique. A previous teardown may leave a
    # branch (e.g., --keep-branch), so don't rely on directory scan alone.
    # Branch suffix (--task) was removed in #650, so the branch is always
    # `wt/<name>/<index>`.
    local wt_path branch
    while :; do
        wt_path="${parent}/${project}-${name}-${next_index}"
        branch="wt/${name}/${next_index}"

        if [ -d "$wt_path" ]; then
            next_index=$((next_index + 1))
            continue
        fi
        if git rev-parse --verify --quiet "refs/heads/${branch}" >/dev/null 2>&1; then
            next_index=$((next_index + 1))
            continue
        fi
        break
    done

    # Create worktree (reuse git_worktree_add for git-crypt safety)
    git_worktree_add "$wt_path" "$branch" "$base" || return 1

    # Log
    printf '[%s] SPAWN name=%s index=%s path=%s branch=%s base=%s\n' \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" "$name" "$next_index" "$wt_path" "$branch" "$base" \
        >> "${git_common}/ai-worktree-spawn.log"

    ux_header "Worktree spawned"
    ux_info "  Path:   $wt_path"
    ux_info "  Branch: $branch"
    ux_info "  Base:   $base"

    _agent_mise_trust "$wt_path"

    # --- Optional tmux integration ---
    if [ "$use_tmux" = 1 ]; then
        # New 6-arg signature (#650): pass use_bg + prompt as a pair so the
        # window can decide whether to wrap in --bg or pass the prompt as a
        # plain TUI first-message.
        _tmux_add_agent_window "$project" "$agent" "$wt_path" "$account" "$use_bg" "$prompt"
        ux_info "  tmux:   session '$project', window '$agent' (runs ${agent}-yolo${account:+ --user $account}$([ "$use_bg" = 1 ] && printf ' --bg'))"
        _agent_tmux_focus "$project" "$agent"
    elif [ "$use_launch" = 1 ]; then
        # cd in the caller's shell (gwt is a function, not a subshell), then
        # run the agent's yolo command. Resolved via _gwt_yolo_command (inside
        # _agent_launch_cmd) rather than `eval "<agent>-yolo"`, because zsh
        # does NOT expand aliases from inside a function body even under eval
        # (issue #243). --bg / --prompt tail: see _agent_prompt_suffix (#650).
        local launch_cmd
        if ! launch_cmd=$(_agent_launch_cmd "$agent" "$account" "$use_bg" "$prompt"); then
            ux_error "No --launch yolo command for agent: $agent"
            ux_info "Supported with --launch: $(_gwt_yolo_command --list)"
            return 1
        fi
        ux_info "  launch: cd \"$wt_path\" && $launch_cmd"
        cd "$wt_path" || { ux_error "Cannot cd to $wt_path"; return 1; }
        eval "$launch_cmd"
    else
        ux_info ""
        ux_info "  cd $wt_path"
    fi
}

# ============================================================================
# Internal: check if current HEAD's commits are safe to discard
# Returns 0 (safe) if: upstream matches, HEAD is in origin/main,
# HEAD's tree matches origin/main (squash directly under main HEAD),
# all patches are already in origin/main (rebase merge), or GitHub reports
# the branch's PR as MERGED with the merge_commit reachable from main_ref.
# ============================================================================
_gwt_commits_safe() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local local_rev remote_rev
    local_rev="$(git rev-parse HEAD)"

    # 1. Upstream tracking branch matches exactly
    remote_rev="$(git rev-parse '@{u}' 2>/dev/null || echo "no-upstream")"
    if [ "$remote_rev" != "no-upstream" ] && [ "$local_rev" = "$remote_rev" ]; then
        return 0
    fi

    # 2. HEAD is an ancestor of origin/main (fast-forward or true merge)
    local main_ref="origin/main"
    git rev-parse --verify --quiet "$main_ref" >/dev/null 2>&1 || main_ref="origin/master"
    if git merge-base --is-ancestor HEAD "$main_ref" 2>/dev/null; then
        return 0
    fi

    # 3. Working tree of HEAD matches origin/main (squash-merge case, narrow).
    # No diff means every change is already on main, even if no individual
    # commit is a patch-id match — squash collapses N→1, so `git cherry`
    # (step 4) cannot detect this. `--quiet` is fail-closed: exit 0 only on
    # genuine no-diff; on bad ref / git error it exits non-zero so we do NOT
    # mistake a failed comparison for a clean tree. Loses signal once
    # origin/main progresses past the squash with overlapping changes —
    # step 5 (PR API) covers that broader case.
    if git diff --quiet "$main_ref" HEAD 2>/dev/null; then
        return 0
    fi

    # 4. All patches already applied via rebase merge (patch-id comparison).
    # git cherry marks already-applied commits with '-', unapplied with '+'.
    # If grep finds no '+' line, every HEAD commit is patch-id-equivalent to
    # something already in main_ref → safe. Misses squash-merge (handled in
    # step 3 / 5) because squash maps N commits to a single patch-id on main.
    if ! git cherry "$main_ref" HEAD 2>/dev/null | grep -q '^+'; then
        return 0
    fi

    # 5. PR API verification. When squash collapses N→1 AND origin/main
    # later progresses with overlapping changes, neither tree-equivalence
    # (step 3) nor patch-id (step 4) detects it. Trust the same `gh` signal
    # gwt status already uses; soft-fails when gh is unavailable.
    local current_branch
    current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
    if [ -n "$current_branch" ] && [ "$current_branch" != "HEAD" ] \
       && _gwt_pr_merged_into "$current_branch" "$main_ref"; then
        return 0
    fi

    # 6. Upstream exists but remote branch was deleted (PR merged + branch auto-deleted)
    if [ "$remote_rev" = "no-upstream" ]; then
        # No upstream ever set — could be genuinely unpushed
        # Check if there are any commits beyond the merge-base with main
        local ahead
        ahead="$(git rev-list --count "$main_ref"..HEAD 2>/dev/null || echo "999")"
        if [ "$ahead" = "0" ]; then
            return 0
        fi
    fi

    return 1
}

# ============================================================================
# Internal: pick the best merge-detection target. Prefer origin/<main> if
# fetched, else fall back to local <main> (stale detection better than none).
# Usage: _gwt_merge_target <main_branch>
# ============================================================================
_gwt_merge_target() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local main_branch="$1"
    if git rev-parse --verify --quiet "origin/$main_branch" >/dev/null 2>&1; then
        printf '%s\n' "origin/$main_branch"
    else
        printf '%s\n' "$main_branch"
    fi
}

# ============================================================================
# Internal: render an actionable "unpushed commits" diagnostic.
# Usage: _gwt_report_unpushed <branch>
# ============================================================================
_gwt_report_unpushed() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local branch="$1"
    local main_ref="origin/main"
    git rev-parse --verify --quiet "$main_ref" >/dev/null 2>&1 || main_ref="origin/master"

    local upstream ahead remote_branch_ref remote_branch_exists
    # `git rev-parse --abbrev-ref '@{u}'` exits non-zero AND prints the
    # literal "@{u}" to stdout when no upstream is set, which leaks into
    # the captured value. Sanitize before display.
    upstream="$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null)"
    if [ -z "$upstream" ] || [ "$upstream" = "@{u}" ]; then
        upstream="(none)"
    fi
    ahead="$(git rev-list --count "$main_ref"..HEAD 2>/dev/null || echo "?")"
    remote_branch_ref="origin/$branch"
    if git rev-parse --verify --quiet "refs/remotes/$remote_branch_ref" >/dev/null 2>&1; then
        remote_branch_exists=true
    else
        remote_branch_exists=false
    fi

    ux_error "Local commits on '$branch' are not in $main_ref ($ahead ahead, upstream: $upstream)."
    if [ "$remote_branch_exists" = true ]; then
        ux_info "  Remote branch exists: $remote_branch_ref"
        ux_info "  Next:   merge/cherry-pick these commits, or use --force to discard locally."
    else
        ux_info "  Push:   git push -u origin $branch"
    fi
    ux_info "  Or:     gwt teardown --force   # discard local commits in this worktree"
    if [ "$ahead" != "?" ] && [ "$ahead" != "0" ]; then
        ux_info "  Commits not in $main_ref (newest first):"
        git log --no-color --format='    %h %s' "$main_ref"..HEAD 2>/dev/null | head -10
    fi
}

# ============================================================================
# Worktree teardown — remove worktree, sync main, delete branch, log
# Usage: git_worktree_teardown [--all|-a|all] [--recursive|-r] [--force] [--keep-branch]
# ============================================================================
git_worktree_teardown() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local force=false keep_branch=false all_mode=false recursive=false

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help|help)
                ux_header "gwt teardown - AI worktree cleanup"
                ux_info "Usage: gwt teardown [--all|-a|all] [--recursive|-r] [--force] [--keep-branch]"
                ux_info ""
                ux_info "Options:"
                ux_info "  --all, -a, all tear down every non-main worktree (run from main"
                ux_info "                 repo or inside any worktree)"
                ux_info "  --recursive,-r with --all (implied): tear down worktrees of every"
                ux_info "                 main repo directly under \$PWD (one confirmation)"
                ux_info "  --force        discard uncommitted changes and force remove"
                ux_info "  --keep-branch  keep the branch after removing worktree"
                return 0
                ;;
            --all|-a|all) all_mode=true; shift ;;
            --recursive|-r) recursive=true; all_mode=true; shift ;;
            --force) force=true; shift ;;
            --keep-branch) keep_branch=true; shift ;;
            -*)
                ux_error "Unknown option: $1. Use --help for usage."
                return 1
                ;;
            *)
                # Detect whether current pwd is main repo or inside a worktree
                # so we can tailor the error guidance to the mistake actually made.
                local _gwt_common _gwt_dir _gwt_in_wt=false _gwt_loc
                _gwt_common="$(git rev-parse --git-common-dir 2>/dev/null)" || {
                    _gwt_report_no_git
                    return 1
                }
                _gwt_dir="$(git rev-parse --git-dir 2>/dev/null)"
                [ "$_gwt_dir" != "$_gwt_common" ] && _gwt_in_wt=true
                _gwt_loc="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

                ux_error "'gwt teardown' does not accept a path argument."
                echo ""
                if [ "$_gwt_in_wt" = true ]; then
                    # Scenario B: user is already in a worktree but still typed a path
                    ux_info "You are already inside a worktree: $_gwt_loc"
                    ux_info "Drop the path argument and just run:"
                    echo ""
                    ux_bullet "gwt teardown"
                else
                    # Scenario A: user is in the main repo (most common mistake)
                    ux_info "You are in:  main repo ($_gwt_loc)"
                    ux_info "You passed:  $1"
                    echo ""
                    ux_warning "'gwt teardown' is SELF-CLEANUP — it tears down the worktree"
                    ux_warning "you are currently inside (cd into it first, then run)."
                    echo ""
                    ux_info "Did you mean:"
                    ux_bullet "cd \"$1\" && gwt teardown     # full cleanup: remove + sync main + delete branch"
                    ux_bullet "gwt remove \"$1\"             # remove worktree only (no main sync, no branch delete)"
                    ux_bullet "gwt teardown --all          # tear down every non-main worktree at once"
                fi
                return 1
                ;;
        esac
    done

    # Batch mode: tear down every non-main worktree.
    if [ "$recursive" = true ]; then
        _gwt_teardown_recursive "$force" "$keep_branch"
        return $?
    fi
    if [ "$all_mode" = true ]; then
        _gwt_teardown_all "$force" "$keep_branch"
        return $?
    fi

    # Must be inside a worktree
    local git_common git_dir
    git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || {
        _gwt_report_no_git
        return 1
    }
    git_dir="$(git rev-parse --git-dir)"
    if [ "$git_dir" = "$git_common" ]; then
        ux_error "Not inside a worktree. Nothing to tear down."
        ux_info "  Use 'gwt teardown --all' to tear down every linked worktree."
        return 1
    fi

    _gwt_teardown_one_inplace "$force" "$keep_branch"
    return $?
}

# ============================================================================
# Internal: tear down the worktree containing $PWD (single-mode pipeline).
# Caller MUST already be inside the target worktree. Performs pre-flight
# checks, removes the worktree, ff-syncs main, deletes the branch, logs.
# Cd's to main repo on success, restores cwd to original worktree on failure.
# Args: <force> <keep_branch>
# ============================================================================
_gwt_teardown_one_inplace() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local force="$1" keep_branch="$2"

    local git_common git_dir
    git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || {
        _gwt_report_no_git
        return 1
    }
    git_dir="$(git rev-parse --git-dir)"
    if [ "$git_dir" = "$git_common" ]; then
        ux_error "Not inside a worktree. Nothing to tear down."
        return 1
    fi

    # Collect info before pre-flights so lock checks can run before dirty-state
    # exits and leave stale Claude agent locks cleaned up for the next attempt.
    local wt_path branch wt_name main_repo
    wt_path="$(git rev-parse --show-toplevel)"
    branch="$(git rev-parse --abbrev-ref HEAD)"
    wt_name="$(basename "$wt_path")"
    main_repo="$(dirname "$git_common")"

    local claude_lock_pid="" claude_lock_live=false
    if claude_lock_pid=$(_gwt_claude_lock_pid "$wt_path"); then
        if kill -0 "$claude_lock_pid" 2>/dev/null; then
            claude_lock_live=true
            if [ "$force" != true ]; then
                ux_error "Cannot remove worktree: $wt_path"
                ux_warning "Claude agent lock is active (pid $claude_lock_pid). Another Claude session may still be using this worktree."
                ux_info "  Inspect:  ps -p $claude_lock_pid"
                ux_info "  Override: gwt teardown --force"
                ux_info "            (only after confirming the Claude session is safe to discard)"
                return 1
            fi
        else
            ux_info "Stale Claude agent lock detected (pid $claude_lock_pid is not running) - unlocking worktree."
            if ! git worktree unlock "$wt_path" 2>/dev/null; then
                ux_warning "Failed to unlock stale Claude agent lock; git will report details if removal fails."
            fi
        fi
    fi

    # Pre-flight: uncommitted changes
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        if [ "$force" = true ]; then
            ux_warning "Discarding uncommitted changes (--force)"
        else
            ux_error "Uncommitted changes. Commit, stash, or use --force."
            return 1
        fi
    fi

    # Pre-flight: untracked files.
    # `git worktree remove` (without --force) refuses when untracked files
    # exist. Catch it here with a message the user can act on, instead of
    # letting the later remove call fail with a stderr we'd have to surface.
    if git status --porcelain 2>/dev/null | grep -q '^??'; then
        if [ "$force" = true ]; then
            ux_warning "Discarding untracked files (--force)"
        else
            ux_error "Untracked files present — git worktree remove will refuse."
            ux_info "  Inspect:  git status --short"
            ux_info "  Clean:    git clean -fd"
            ux_info "  Override: gwt teardown --force"
            return 1
        fi
    fi

    # Pre-flight: unpushed commits.
    # (A) Capture fetch stderr so failures surface the actual cause, not a
    # misleading "network?" blurb. Real reason (auth, hook, URL, etc.) wins.
    local _gwt_fetch_err_file="${TMPDIR:-/tmp}/gwt-fetch.$$.err"
    if ! git fetch origin 2>"$_gwt_fetch_err_file" >/dev/null; then
        ux_warning "git fetch origin failed (non-blocking); using local refs for safety checks."
        if [ -s "$_gwt_fetch_err_file" ]; then
            sed 's/^/    /' "$_gwt_fetch_err_file" >&2
        fi
    fi
    rm -f "$_gwt_fetch_err_file"
    # Checks (in order): upstream match → ancestor of origin/main → patch-id (rebase merge)
    if ! _gwt_commits_safe; then
        if [ "$force" = true ]; then
            ux_warning "Discarding unpushed commits (--force)"
        else
            # (E) Actionable diagnostic: show ahead count, upstream state,
            # push command, and the list of unpushed commits.
            _gwt_report_unpushed "$(git rev-parse --abbrev-ref HEAD)"
            return 1
        fi
    fi

    # Switch to main repo
    cd "$main_repo" || { ux_error "Cannot cd to $main_repo"; return 1; }

    # Remove worktree. Capture stderr so the actual git reason (locked, dirty
    # submodule, untracked residuals, etc.) reaches the user instead of being
    # swallowed — same pattern as the fetch-stderr capture above. Choose the
    # remove command upfront from $force so a single error-handling block
    # covers both paths. On failure, cd back into $wt_path so the user stays
    # in the worktree they asked to remove (we already cd'd to $main_repo
    # above) and can investigate.
    local _gwt_rm_err_file="${TMPDIR:-/tmp}/gwt-rm.$$.err"
    local _gwt_rm_exit=0
    if [ "$force" = true ]; then
        if [ "$claude_lock_live" = true ]; then
            ux_warning "Removing Claude agent locked worktree (--force)."
            git worktree remove -f -f "$wt_path" 2>"$_gwt_rm_err_file" || _gwt_rm_exit=$?
        else
            git worktree remove --force "$wt_path" 2>"$_gwt_rm_err_file" || _gwt_rm_exit=$?
        fi
    else
        git worktree remove "$wt_path" 2>"$_gwt_rm_err_file" || _gwt_rm_exit=$?
    fi

    # Auto-recovery for the submodule-block case. `git worktree remove` refuses
    # any tree that contains submodules, even when their working trees are
    # untouched — the AI-worktree workflow re-clones submodules on the next
    # spawn, so their populated state is disposable. The parent worktree has
    # already passed every dirty-state pre-flight above (uncommitted, staged,
    # untracked, unpushed), so retrying with --force here only adds permission
    # to drop populated submodule contents — exactly what we want. Without
    # this, every teardown of a repo with submodules would force the user to
    # rerun manually, which is what issue #211 was filed against.
    if [ "$_gwt_rm_exit" -ne 0 ] && [ "$force" != true ] \
       && grep -q "working trees containing submodules cannot be moved or removed" "$_gwt_rm_err_file" 2>/dev/null; then
        ux_info "Submodules detected — retrying removal (parent worktree already verified clean)."
        : > "$_gwt_rm_err_file"
        if git worktree remove --force "$wt_path" 2>"$_gwt_rm_err_file"; then
            _gwt_rm_exit=0
        else
            _gwt_rm_exit=$?
        fi
    fi

    if [ "$_gwt_rm_exit" -ne 0 ]; then
        local _gwt_submodule_blocked=false
        if grep -q "working trees containing submodules cannot be moved or removed" "$_gwt_rm_err_file" 2>/dev/null; then
            _gwt_submodule_blocked=true
        fi

        if [ "$force" = true ]; then
            ux_error "Failed to remove worktree: $wt_path"
        else
            ux_error "Cannot remove worktree: $wt_path"
        fi
        if [ -s "$_gwt_rm_err_file" ]; then
            ux_info "  git says:"
            sed 's/^/    /' "$_gwt_rm_err_file" >&2
        fi
        if [ "$_gwt_submodule_blocked" = true ]; then
            # Auto-recovery already retried with --force above; reaching here
            # means even --force could not remove this worktree (locked
            # submodule, permissions, gitlink corruption, etc.). The user has
            # to investigate manually.
            ux_warning "  Git blocked removal even with --force — a submodule is in an unusual state."
            local _gwt_submodule_paths _gwt_submodule_path _gwt_submodule_count=0
            _gwt_submodule_paths="$(git -C "$wt_path" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')"
            if [ -n "$_gwt_submodule_paths" ]; then
                ux_info "  Submodules in this repository:"
                while IFS= read -r _gwt_submodule_path; do
                    [ -n "$_gwt_submodule_path" ] || continue
                    ux_info "    - $_gwt_submodule_path"
                    _gwt_submodule_count=$((_gwt_submodule_count + 1))
                    [ "$_gwt_submodule_count" -ge 3 ] && break
                done <<EOF
$_gwt_submodule_paths
EOF
            fi
            ux_info "  Inspect:  git -C \"$wt_path\" submodule foreach 'git status --short'"
            ux_info "  Locks:    git -C \"$wt_path\" submodule foreach 'git config --get core.bare; git status'"
        elif [ "$force" != true ]; then
            ux_info "  Inspect:  git -C \"$wt_path\" status --short"
            ux_info "  Clean:    git -C \"$wt_path\" clean -fd"
            ux_info "  Override: gwt teardown --force"
            ux_info "            (run from inside: $wt_path)"
        fi
        rm -f "$_gwt_rm_err_file"
        cd "$wt_path" 2>/dev/null || true
        return 1
    fi
    rm -f "$_gwt_rm_err_file"
    git worktree prune

    # Restore repo format when this was the last linked worktree.
    # git worktree add writes repositoryformatversion=1 + extensions.worktreeConfig
    # into .git/config. When all worktrees are gone these linger and cause
    # gitstatusd v1.5.4 to treat the repo as "not a git repo" (result=0),
    # breaking p10k's branch display (issue #968).
    local _gwt_remaining
    _gwt_remaining="$(git worktree list --porcelain | grep -c "^worktree ")"
    if [ "${_gwt_remaining:-2}" -le 1 ] \
       && [ "$(git config core.repositoryformatversion 2>/dev/null)" = "1" ]; then
        git config --unset extensions.worktreeConfig 2>/dev/null || true
        if ! git config --name-only --get-regexp '^extensions\.' >/dev/null 2>&1; then
            git config core.repositoryformatversion 0
        fi
    fi

    # Sync main BEFORE branch delete.
    local main_branch="main"
    if ! git rev-parse --verify --quiet "main" >/dev/null 2>&1; then
        main_branch="master"
    fi
    # (F) -q suppresses "Your branch is behind 'origin/<main>' by N commits"
    # which git checkout prints to stdout (unsilenceable via 2>/dev/null).
    if ! git checkout -q "$main_branch" 2>/dev/null; then
        ux_error "Failed to checkout $main_branch in main repository."
        return 1
    fi
    # (B) Replace `git pull origin <main>` with local `git merge --ff-only
    # origin/<main>`. We already fetched above — no second network round-trip,
    # no rebase-merge surprises under pull.rebase=true. Diverged local main is
    # reported clearly rather than collapsed into "network?".
    local _gwt_ff_err_file="${TMPDIR:-/tmp}/gwt-ff.$$.err"
    local main_sync_ok=true
    if git rev-parse --verify --quiet "origin/$main_branch" >/dev/null 2>&1; then
        if ! git merge --ff-only "origin/$main_branch" 2>"$_gwt_ff_err_file" >/dev/null; then
            main_sync_ok=false
            ux_error "Main sync failed — git merge --ff-only origin/$main_branch"
            if [ -s "$_gwt_ff_err_file" ]; then
                sed 's/^/    /' "$_gwt_ff_err_file" >&2
            fi
            # Reuse the status view's ahead/behind pattern (~l.986) so the
            # message says HOW FAR local main diverged, not just that it did.
            local _gwt_main_ahead _gwt_main_behind
            _gwt_main_ahead="$(git rev-list --count "origin/$main_branch..$main_branch" 2>/dev/null || printf '?')"
            _gwt_main_behind="$(git rev-list --count "$main_branch..origin/$main_branch" 2>/dev/null || printf '?')"
            ux_info "  Local '$main_branch' has diverged from origin/$main_branch (${_gwt_main_ahead} ahead, ${_gwt_main_behind} behind)."
            ux_info "  Resolve manually (rebase / reset) before spawning new worktrees from local '$main_branch'."
        fi
    else
        main_sync_ok=false
        ux_warning "origin/$main_branch not found — skipping ff-sync (fetch likely failed)."
    fi
    rm -f "$_gwt_ff_err_file"

    # (D) Prefer origin/<main> over local <main> for rebase-merge detection.
    # Local <main> can be stale when the ff-only sync above failed — exactly
    # the scenario where we most need merge detection to still fire.
    local merge_target
    merge_target=$(_gwt_merge_target "$main_branch")

    # Delete branch. A detached worktree has no branch: `rev-parse --abbrev-ref`
    # returned the literal "HEAD", which here (cwd = main repo) would resolve
    # to main's own HEAD and look "merged" (#2022).
    if [ "$branch" = HEAD ]; then
        branch="(detached)"
        ux_info "Detached HEAD — no branch to delete"
    elif [ "$keep_branch" = true ]; then
        ux_info "Branch kept: $branch (--keep-branch)"
    elif git branch -d "$branch" 2>/dev/null; then
        : # deleted successfully (fast-forward or true merge)
    elif _gwt_branch_merged "$branch" "$merge_target"; then
        # Rebase/squash merge: commits are in main_ref but SHAs differ.
        if git branch -D "$branch" 2>/dev/null; then
            ux_success "Branch deleted (rebase-merged): $branch"
        else
            ux_warning "Branch '$branch' is merged but could not be deleted (git branch -D failed)."
        fi
    elif [ "$force" = true ]; then
        if git branch -D "$branch" 2>/dev/null; then
            ux_success "Branch force-deleted: $branch"
        else
            ux_warning "Branch '$branch' could not be force-deleted (git branch -D failed)."
        fi
    else
        ux_warning "Branch '$branch' not fully merged. Use --force or --keep-branch."
    fi

    # Log
    printf '[%s] TEARDOWN worktree=%s branch=%s path=%s\n' \
        "$(date +%Y-%m-%dT%H:%M:%S%z)" "$wt_name" "$branch" "$wt_path" \
        >> "$(git rev-parse --git-common-dir)/ai-worktree-spawn.log"

    # (C-2) Strict exit: if main is not in sync with origin, report partial
    # teardown and return non-zero so callers (CI, hooks, chained aliases)
    # notice. Worktree removal and branch delete still ran.
    if [ "$main_sync_ok" = true ]; then
        ux_success "Teardown complete"
        ux_info "  Removed: $wt_path"
        ux_info "  Now on:  $main_branch"
        return 0
    fi

    ux_warning "Teardown partial — worktree removed, main NOT in sync with origin/$main_branch"
    ux_info "  Removed: $wt_path"
    ux_info "  Now on:  $main_branch (out of sync)"
    return 1
}

# ============================================================================
# Internal: tear down every non-main worktree (best-effort).
# Args: <force> <keep_branch> [skip_confirm]
# skip_confirm=true suppresses ONLY the prompt (recursive mode already asked
# once); it never implies --force.
# Returns 0 if all teardowns succeed, 1 if any failed (or aborted, or no repo).
# ============================================================================
_gwt_teardown_all() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local force="$1" keep_branch="$2" skip_confirm="${3:-false}"

    # Must be inside a git repo (main or any worktree).
    # Keep `|| { ...; }` on one line so the closing brace does not appear at
    # line-start; library_purity_check tracks brace depth via `^\s*\}` and
    # would otherwise treat this as the enclosing function's close, falsely
    # flagging the `read -r` below as top-level interactive code.
    git rev-parse --git-common-dir >/dev/null 2>&1 || { _gwt_report_no_git; _gwt_hint_recursive; return 1; }

    # Resolve main worktree and collect non-main worktrees from a single
    # `git worktree list --porcelain` snapshot — one fork instead of two,
    # and both parses see the same repo state.
    local porcelain main_wt all_wts="" all_count=0
    porcelain="$(git worktree list --porcelain)"
    IFS= read -r main_wt <<EOF
$porcelain
EOF
    main_wt="${main_wt#worktree }"

    while IFS= read -r line; do
        case "$line" in
            "worktree "*)
                local wt="${line#worktree }"
                if [ "$wt" != "$main_wt" ]; then
                    all_wts="${all_wts}${wt}
"
                    all_count=$((all_count + 1))
                fi
                ;;
        esac
    done <<EOF
$porcelain
EOF

    if [ "$all_count" -eq 0 ]; then
        ux_info "No worktrees to tear down."
        return 0
    fi

    ux_warning "About to tear down $all_count worktree(s):"
    while IFS= read -r wt; do
        [ -n "$wt" ] || continue
        ux_info "  $wt"
    done <<EOF
$all_wts
EOF

    if [ "$force" != true ] && [ "$skip_confirm" != true ]; then
        if ! ux_confirm "Proceed with teardown?" "n"; then
            ux_info "Aborted."
            return 1
        fi
    fi

    # Park in main repo so loop iterations have a stable cwd between runs.
    cd "$main_wt" 2>/dev/null || { ux_error "Cannot cd to main repo: $main_wt"; return 1; }

    local ok_count=0 fail_count=0 failed_wts=""
    while IFS= read -r wt; do
        [ -n "$wt" ] || continue
        ux_header "Tearing down: $wt"
        if [ ! -d "$wt" ]; then
            ux_warning "  Path missing on disk — skipping (run 'gwt prune' to clean stale refs)."
            fail_count=$((fail_count + 1))
            failed_wts="${failed_wts}${wt} (missing)
"
            continue
        fi
        # Split across lines: naming_check.sh greedy-matches `".*<func>.*"` on
        # a single line, so keeping `"$wt"` and `"$force"` from sandwiching the
        # helper name on one physical line avoids a false-positive flag.
        # MISE_NO_CONFIG is exported BEFORE cd: zsh chpwd hooks (mise activate)
        # fire during cd itself and would print "not trusted" for every
        # worktree mise.toml that `gwt spawn` never trusted (#2023).
        if ( export MISE_NO_CONFIG=1; cd "$wt" \
             && _gwt_teardown_one_inplace "$force" "$keep_branch" ); then
            ok_count=$((ok_count + 1))
        else
            fail_count=$((fail_count + 1))
            failed_wts="${failed_wts}${wt}
"
        fi
        # Restore cwd to main_wt — _gwt_teardown_one_inplace ran in subshell,
        # so caller's cwd is unchanged, but defensively re-anchor.
        cd "$main_wt" 2>/dev/null || true
    done <<EOF
$all_wts
EOF

    ux_header "Teardown summary"
    ux_info "  Succeeded: $ok_count"
    ux_info "  Failed:    $fail_count"
    if [ "$fail_count" -gt 0 ]; then
        ux_info "  Failed worktrees:"
        while IFS= read -r wt; do
            [ -n "$wt" ] || continue
            ux_info "    $wt"
        done <<EOF
$failed_wts
EOF
        return 1
    fi
    ux_success "All worktrees torn down."
    return 0
}

# ============================================================================
# Internal: print main repos (.git is a DIRECTORY) directly under $PWD, one
# absolute path per line. Linked worktrees (.git is a file) are skipped —
# their main repo covers them.
# ============================================================================
_gwt_find_main_repos() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local d
    for d in ./*/; do
        [ -d "$d.git" ] || continue
        d="${d#./}"
        printf '%s\n' "$PWD/${d%/}"
    done
}

# Hint for `gwt teardown --all` run outside a repo (issue #1835 F-8).
_gwt_hint_recursive() {
    [ -n "${ZSH_VERSION-}" ] && emulate -L sh
    local repos
    repos=$(_gwt_find_main_repos)
    [ -n "$repos" ] || return 0
    ux_info "  Subdirectories contain git repositories. To tear them all down:"
    ux_bullet "gwt teardown --all --recursive"
}

# ============================================================================
# Internal: tear down every linked worktree of every main repo directly
# under $PWD (issue #1835). Plans first, confirms once, then runs
# _gwt_teardown_all per repo in a subshell (caller cwd preserved).
# Args: <force> <keep_branch>
# Returns 0 if every repo succeeds (or nothing to do), 1 otherwise.
# ============================================================================
_gwt_teardown_recursive() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local force="$1" keep_branch="$2"
    local all_repos repo wt wts plan_repos="" repo_count=0 wt_count=0

    all_repos=$(_gwt_find_main_repos)
    if [ -z "$all_repos" ]; then
        ux_info "No git repositories found under $PWD."
        return 0
    fi

    # Snapshot the plan BEFORE tearing anything down: sibling worktree dirs
    # vanish while earlier repos are processed.
    ux_warning "Worktrees to tear down:"
    while IFS= read -r repo; do
        [ -n "$repo" ] || continue
        # First porcelain entry is the main worktree itself.
        wts="$(git -C "$repo" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | sed '1d')"
        [ -n "$wts" ] || continue
        plan_repos="${plan_repos}${repo}
"
        repo_count=$((repo_count + 1))
        ux_info "  Repository: $repo"
        while IFS= read -r wt; do
            ux_info "    $wt"
            wt_count=$((wt_count + 1))
        done <<EOF
$wts
EOF
    done <<EOF
$all_repos
EOF

    if [ "$repo_count" -eq 0 ]; then
        ux_info "No worktrees to tear down."
        return 0
    fi

    ux_warning "About to tear down $wt_count worktree(s) across $repo_count repositories."
    if [ "$force" != true ]; then
        if ! ux_confirm "Proceed with teardown?" "n"; then
            ux_info "Aborted."
            return 1
        fi
    fi

    local ok_repos=0 fail_repos=0 failed_list=""
    while IFS= read -r repo; do
        [ -n "$repo" ] || continue
        ux_header "Repository: $repo"
        # Split across lines for naming_check.sh (see _gwt_teardown_all).
        if ( cd "$repo" \
             && _gwt_teardown_all "$force" "$keep_branch" true ); then
            ok_repos=$((ok_repos + 1))
        else
            fail_repos=$((fail_repos + 1))
            failed_list="${failed_list}${repo}
"
        fi
    done <<EOF
$plan_repos
EOF

    ux_header "Recursive teardown summary"
    ux_info "  Repositories succeeded: $ok_repos"
    ux_info "  Repositories failed:    $fail_repos"
    if [ "$fail_repos" -gt 0 ]; then
        ux_info "  Failed repositories:"
        while IFS= read -r repo; do
            [ -n "$repo" ] || continue
            ux_info "    $repo"
        done <<EOF
$failed_list
EOF
        return 1
    fi
    ux_success "All repositories torn down."
    return 0
}
