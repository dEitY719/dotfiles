#!/bin/sh
# shellcheck shell=bash
# shell-common/functions/gh_flow.sh
# gh-flow — fire-and-forget N-parallel GitHub issue → PR automation.
# Design: docs/feature/gh-flow-automation/design.md

# ============================================================================
# State helpers
# ============================================================================

_gh_flow_state_root() {
    printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/gh-flow"
}

_gh_flow_repo_name() {
    basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null
}

_gh_flow_issue_dir() {
    # $1 = issue number
    local _root _name
    _root=$(_gh_flow_state_root)
    _name=$(_gh_flow_repo_name)
    printf '%s/%s/%s' "$_root" "$_name" "$1"
}

_gh_flow_set_state() {
    # $1 = issue-dir path, $2 = state
    # Takes a dir (not an issue number) so callers inside a worktree are
    # not affected by cwd — otherwise _gh_flow_issue_dir recomputes via
    # `git rev-parse --show-toplevel` and silently writes to a different
    # location after the worker cd's into its worktree.
    mkdir -p "$1"
    printf '%s\n' "$2" >"$1/state"
}

_gh_flow_get_state() {
    # $1 = issue; prints state or "nonexistent"
    local _dir
    _dir=$(_gh_flow_issue_dir "$1")
    if [ -f "$_dir/state" ]; then
        cat "$_dir/state"
    else
        printf 'nonexistent'
    fi
}

# ============================================================================
# Post-condition helpers (worker uses these to verify each step did real work)
# ============================================================================

# Returns 0 if the current tree has something /gh-commit could commit:
# staged, unstaged, or untracked changes. (Runs inside the worktree.)
_gh_flow_has_work_for_commit() {
    [ -n "$(git status --porcelain 2>/dev/null | head -n1)" ]
}

# Returns 0 if the current branch has at least one commit ahead of
# the upstream default branch (origin/HEAD). Used to verify /gh-commit.
_gh_flow_has_branch_commits() {
    local _base _count
    _base="$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null | sed 's|^refs/remotes/||')"
    if [ -z "$_base" ]; then
        _base="origin/main"
    fi
    _count="$(git rev-list --count "HEAD" "^$_base" 2>/dev/null || echo 0)"
    [ "${_count:-0}" -gt 0 ]
}

# ============================================================================
# status / prune subcommands
# ============================================================================

# List all known gh-flow entries for the current repo. No args.
# Output: a table of issue / state / pid-liveness / worktree path. Non-fatal
# if there are no entries.
_gh_flow_status() {
    local _root _name _repo_dir _entry _issue _state _pid _wt _pid_state
    _root=$(_gh_flow_state_root)
    _name=$(_gh_flow_repo_name)
    if [ -z "$_name" ]; then
        ux_error "gh-flow status: not inside a git repo"
        return 1
    fi
    _repo_dir="$_root/$_name"

    ux_header "gh-flow status - $_name"
    if [ ! -d "$_repo_dir" ]; then
        ux_info "no state — no workers have ever run in this repo"
        return 0
    fi

    local _found=0
    ux_table_header "ISSUE" "STATE" "PID / WORKTREE"
    for _entry in "$_repo_dir"/*/; do
        [ -d "$_entry" ] || continue
        _issue="$(basename "$_entry")"
        _state="$(cat "$_entry/state" 2>/dev/null || printf 'unknown')"
        _pid="$(cat "$_entry/pid" 2>/dev/null || printf '')"
        _wt="$(cat "$_entry/worktree.path" 2>/dev/null || printf '')"

        if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
            _pid_state="pid=$_pid (alive)"
        elif [ -n "$_pid" ]; then
            _pid_state="pid=$_pid (dead)"
        else
            _pid_state="-"
        fi

        if [ -n "$_wt" ]; then
            ux_table_row "#$_issue" "$_state" "$_pid_state  $_wt"
        else
            ux_table_row "#$_issue" "$_state" "$_pid_state"
        fi
        _found=1
    done
    if [ "$_found" = "0" ]; then
        ux_info "no state entries under $_repo_dir"
    fi
    ux_info ""
    ux_info "Run 'gh-flow prune' to clean done entries and list failed worktrees."
}

# Remove state dirs whose state is 'done'; report still-present worktrees for
# 'failed:*' entries. Args: [--force] → with --force, also 'gwt teardown
# --force' each failed worktree.
_gh_flow_prune() {
    local _force=0
    case "${1:-}" in
        --force|-f) _force=1 ;;
        '') : ;;
        *)
            ux_error "gh-flow prune: unknown arg '$1' (only --force is accepted)"
            return 1
            ;;
    esac

    local _root _name _repo_dir _entry _issue _state _wt
    _root=$(_gh_flow_state_root)
    _name=$(_gh_flow_repo_name)
    if [ -z "$_name" ]; then
        ux_error "gh-flow prune: not inside a git repo"
        return 1
    fi
    _repo_dir="$_root/$_name"

    ux_header "gh-flow prune - $_name"
    if [ ! -d "$_repo_dir" ]; then
        ux_info "nothing to prune"
        return 0
    fi

    local _removed=0 _failed=0 _torn_down=0
    for _entry in "$_repo_dir"/*/; do
        [ -d "$_entry" ] || continue
        _issue="$(basename "$_entry")"
        _state="$(cat "$_entry/state" 2>/dev/null || printf '')"
        _wt="$(cat "$_entry/worktree.path" 2>/dev/null || printf '')"

        case "$_state" in
            done)
                rm -rf "$_entry"
                ux_success "removed state for #$_issue (done)"
                _removed=$((_removed + 1))
                ;;
            failed:*)
                _failed=$((_failed + 1))
                if [ "$_force" = "1" ] && [ -n "$_wt" ] && [ -d "$_wt" ]; then
                    ux_warning "#$_issue $_state — tearing down $_wt"
                    if (cd "$_wt" && gwt teardown --force); then
                        rm -rf "$_entry"
                        _torn_down=$((_torn_down + 1))
                    else
                        ux_error "  gwt teardown failed for $_wt; leaving state dir intact"
                    fi
                else
                    ux_warning "#$_issue $_state"
                    if [ -n "$_wt" ] && [ -d "$_wt" ]; then
                        ux_bullet_sub "worktree: $_wt"
                        ux_bullet_sub "cleanup: cd $_wt && gwt teardown --force"
                    fi
                fi
                ;;
        esac
    done

    ux_info ""
    if [ "$_force" = "1" ]; then
        ux_success "pruned $_removed done entr(ies), torn down $_torn_down failed worktree(s); $((_failed - _torn_down)) failure(s) still need attention"
    else
        ux_success "pruned $_removed done entr(ies); $_failed failure(s) need attention (pass --force to gwt teardown them)"
    fi
}

# ============================================================================
# Help
# ============================================================================

gh_flow_help() {
    ux_header "gh-flow - fire-and-forget GitHub issue → PR automation"
    ux_info "Usage:"
    ux_bullet "gh-flow <issue-number>...       spawn N parallel workers"
    ux_bullet "gh-flow status                  show state of known issues in this repo"
    ux_bullet "gh-flow prune [--force]         clean 'done' state; list 'failed:*' worktrees"
    ux_bullet "gh-flow -h|--help|help          this help"
    ux_info ""
    ux_info "Spawn pipeline (each worker runs these sequentially):"
    ux_bullet "gwt spawn → /gh-issue-implement → /gh-commit → /gh-pr"
    ux_bullet "poll reviews → /gh-pr-reply (once, if comments)"
    ux_bullet "poll for APPROVED → /gh-pr-merge → gwt teardown"
    ux_info ""
    ux_info "Examples:"
    ux_bullet "gh-flow 13                  # single issue"
    ux_bullet "gh-flow 13 42 88            # 3 issues in parallel"
    ux_bullet "gh-flow status              # who's still running, who failed"
    ux_bullet "gh-flow prune               # remove 'done' state dirs; print hints for failures"
    ux_bullet "gh-flow prune --force       # also gwt teardown failed worktrees"
    ux_info ""
    ux_info "State directory: ~/.local/state/gh-flow/<repo>/<issue>/"
    ux_bullet_sub "state         - current step"
    ux_bullet_sub "pid           - worker process id"
    ux_bullet_sub "worktree.path - git worktree path"
    ux_bullet_sub "pr.number     - PR number"
    ux_bullet_sub "reply.done    - marker (present if reply already ran)"
    ux_bullet_sub "log           - full stdout+stderr"
    ux_info ""
    ux_info "Failure isolation:"
    ux_bullet "One worker failure does not affect others."
    ux_bullet "Failed worker leaves worktree intact; state shows 'failed:<step>'."
    ux_bullet "Distinct failure states: failed:implementing, failed:committing,"
    ux_bullet_sub "failed:opening-pr, failed:replying, failed:merging, failed:tearing-down."
    ux_info ""
    ux_info "Preconditions:"
    ux_bullet "Run from main repo (not inside a worktree)"
    ux_bullet "gh CLI authenticated, claude CLI on PATH, gwt loaded"
}

# ============================================================================
# Orchestrator
# ============================================================================

gh_flow() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    case "${1:-}" in
        ""|-h|--help|help)
            gh_flow_help
            return 0
            ;;
        status)
            shift
            _gh_flow_status "$@"
            return $?
            ;;
        prune)
            shift
            _gh_flow_prune "$@"
            return $?
            ;;
    esac

    # Preconditions
    if ! _have git; then
        ux_error "git not found"
        return 1
    fi
    if ! _have gh; then
        ux_error "gh CLI not found"
        return 1
    fi
    if ! _have claude; then
        ux_error "claude CLI not found"
        return 1
    fi
    if ! command -v gwt >/dev/null 2>&1; then
        ux_error "gwt function not loaded (source shell-common first)"
        return 1
    fi

    # Must be in main repo (not a worktree)
    local _git_dir _git_common
    _git_dir="$(git rev-parse --git-dir 2>/dev/null)"
    _git_common="$(git rev-parse --git-common-dir 2>/dev/null)"
    if [ -z "$_git_dir" ]; then
        ux_error "not inside a git repo"
        return 1
    fi
    if [ "$_git_dir" != "$_git_common" ]; then
        ux_error "gh-flow must run from the main repo, not a worktree"
        ux_info "cd to the main repo and retry"
        return 1
    fi

    # Validate each arg is a positive integer
    local _issue
    for _issue in "$@"; do
        case "$_issue" in
            ''|*[!0-9]*)
                ux_error "invalid issue number: '$_issue' (must be positive integer)"
                ux_info "subcommands: status, prune; or pass one or more issue numbers"
                return 1
                ;;
        esac
    done

    ux_header "gh-flow: spawning $# worker(s)"
    for _issue in "$@"; do
        _gh_flow_spawn_worker "$_issue"
    done
    ux_success "All workers detached. Your shell is free. Results will appear on the kanban."
}

_gh_flow_spawn_worker() {
    local _issue="$1"
    local _dir _log _state _pid
    _dir=$(_gh_flow_issue_dir "$_issue")
    mkdir -p "$_dir"
    _log="$_dir/log"

    # Idempotency check
    _state=$(_gh_flow_get_state "$_issue")
    case "$_state" in
        done)
            ux_info "#$_issue already done, skipping"
            return 0
            ;;
        spawning|implementing|committing|opening-pr|polling|replying|merging|tearing-down)
            if [ -f "$_dir/pid" ]; then
                _pid="$(cat "$_dir/pid")"
                if kill -0 "$_pid" 2>/dev/null; then
                    ux_warning "#$_issue already running (pid=$_pid), skipping"
                    return 0
                fi
            fi
            ux_info "#$_issue was in-progress but pid is dead — resuming with a new worker"
            ;;
    esac

    # Rotate previous log (keep one .prev for debugging)
    if [ -f "$_log" ]; then
        mv "$_log" "$_log.prev" 2>/dev/null || true
    fi

    # Fork detached worker. DOTFILES_FORCE_INIT=1 forces full shell-common
    # loading in the non-interactive subshell so `gwt`, `ux_*`, and helpers
    # resolve. The subshell sources ~/.bashrc then calls _gh_flow_worker.
    # shellcheck disable=SC2016
    nohup env DOTFILES_FORCE_INIT=1 bash -c '
        . "$HOME/.bashrc" 2>/dev/null || true
        _gh_flow_worker "$1"
    ' -- "$_issue" >"$_log" 2>&1 &
    _pid=$!
    disown "$_pid" 2>/dev/null || true
    printf '%s\n' "$_pid" >"$_dir/pid"
    ux_info "#$_issue → pid=$_pid  log=$_log"
}

# ============================================================================
# Worker (runs in a detached bash subshell)
# ============================================================================

_gh_flow_worker() {
    local _issue="$1"
    local _dir _worktree _pr _spawn_name _decision _comments
    _dir=$(_gh_flow_issue_dir "$_issue")
    _spawn_name="issue-$_issue"

    printf '[gh-flow-worker] issue=#%s start=%s\n' "$_issue" "$(date -Iseconds 2>/dev/null || date)"

    # ---- Step 1: spawn worktree ----
    # Snapshot the worktree list before and after `gwt spawn` and diff them
    # to identify the new one. This avoids coupling to gwt's internal
    # branch-naming convention (previously: parsing `wt/<name>/<idx>`).
    local _wt_before _wt_after
    _gh_flow_set_state "$_dir" "spawning"
    _wt_before=$(git worktree list --porcelain 2>/dev/null | awk '$1=="worktree"{print $2}')
    if ! gwt spawn "$_spawn_name"; then
        _gh_flow_set_state "$_dir" "failed:spawning"
        printf '[gh-flow-worker] gwt spawn failed\n' >&2
        return 1
    fi

    _wt_after=$(git worktree list --porcelain 2>/dev/null | awk '$1=="worktree"{print $2}')
    _worktree=$(comm -13 \
        <(printf '%s\n' "$_wt_before" | sort) \
        <(printf '%s\n' "$_wt_after" | sort) \
        | head -n 1)

    if [ -z "$_worktree" ] || [ ! -d "$_worktree" ]; then
        _gh_flow_set_state "$_dir" "failed:spawning"
        printf '[gh-flow-worker] could not locate newly-created worktree\n' >&2
        return 1
    fi
    printf '%s\n' "$_worktree" >"$_dir/worktree.path"
    printf '[gh-flow-worker] worktree=%s\n' "$_worktree"

    # shellcheck disable=SC2164
    cd "$_worktree" || {
        _gh_flow_set_state "$_dir" "failed:spawning"
        return 1
    }

    # ---- Step 2a: implement (claude runs /gh-issue-implement) ----
    # The original single `/gh-issue-flow` call was unreliable under `claude -p`
    # (non-interactive): it often stopped after the implement phase and printed
    # a "Next: …" hint without running commit/PR. We invoke the 3 atomic skills
    # ourselves so each phase has a distinct state + post-condition check.
    _gh_flow_set_state "$_dir" "implementing"
    _gh_flow_set_project_status issue "$_issue" "In progress"
    if ! claude --dangerously-skip-permissions -p "/gh-issue-implement $_issue direct"; then
        _gh_flow_set_state "$_dir" "failed:implementing"
        printf '[gh-flow-worker] /gh-issue-implement failed\n' >&2
        return 1
    fi
    if ! _gh_flow_has_work_for_commit; then
        _gh_flow_set_state "$_dir" "failed:implementing"
        printf '[gh-flow-worker] /gh-issue-implement produced no changes\n' >&2
        return 1
    fi

    # ---- Step 2b: commit (claude runs /gh-commit) ----
    _gh_flow_set_state "$_dir" "committing"
    if ! claude --dangerously-skip-permissions -p "/gh-commit"; then
        _gh_flow_set_state "$_dir" "failed:committing"
        printf '[gh-flow-worker] /gh-commit failed\n' >&2
        return 1
    fi
    if ! _gh_flow_has_branch_commits; then
        _gh_flow_set_state "$_dir" "failed:committing"
        printf '[gh-flow-worker] /gh-commit left no new commit on branch\n' >&2
        return 1
    fi

    # ---- Step 2c: open PR (claude runs /gh-pr) ----
    _gh_flow_set_state "$_dir" "opening-pr"
    if ! claude --dangerously-skip-permissions -p "/gh-pr $_issue"; then
        _gh_flow_set_state "$_dir" "failed:opening-pr"
        printf '[gh-flow-worker] /gh-pr failed\n' >&2
        return 1
    fi
    _pr="$(gh pr view --json number --jq '.number' 2>/dev/null)"
    if [ -z "$_pr" ]; then
        _gh_flow_set_state "$_dir" "failed:opening-pr"
        printf '[gh-flow-worker] /gh-pr did not create a PR\n' >&2
        return 1
    fi
    printf '%s\n' "$_pr" >"$_dir/pr.number"
    printf '[gh-flow-worker] PR=#%s\n' "$_pr"
    # PR card auto-transition is not covered by any built-in workflow;
    # move it to "In review" explicitly so reviewers see it on the board.
    _gh_flow_set_project_status pr "$_pr" "In review"

    # ---- Step 3: poll for review / approval ----
    _gh_flow_set_state "$_dir" "polling"
    while true; do
        sleep 60

        _decision="$(gh pr view "$_pr" --json reviewDecision --jq '.reviewDecision // ""' 2>/dev/null)"
        if [ "$_decision" = "APPROVED" ]; then
            printf '[gh-flow-worker] approved\n'
            break
        fi

        # Reply once, only if comments/changes-requested exist and we haven't replied yet.
        if [ ! -f "$_dir/reply.done" ]; then
            _comments="$(gh pr view "$_pr" --json reviews \
                --jq '[.reviews[] | select(.state == "COMMENTED" or .state == "CHANGES_REQUESTED")] | length' \
                2>/dev/null)"
            if [ -n "$_comments" ] && [ "$_comments" -gt 0 ]; then
                _gh_flow_set_state "$_dir" "replying"
                printf '[gh-flow-worker] running /gh-pr-reply (%s review(s))\n' "$_comments"
                if claude --dangerously-skip-permissions -p "/gh-pr-reply"; then
                    touch "$_dir/reply.done"
                    _gh_flow_set_state "$_dir" "polling"
                else
                    _gh_flow_set_state "$_dir" "failed:replying"
                    printf '[gh-flow-worker] /gh-pr-reply failed\n' >&2
                    return 1
                fi
            fi
        fi
    done

    # ---- Step 4: merge ----
    _gh_flow_set_state "$_dir" "merging"
    if ! claude --dangerously-skip-permissions -p "/gh-pr-merge"; then
        _gh_flow_set_state "$_dir" "failed:merging"
        printf '[gh-flow-worker] /gh-pr-merge failed\n' >&2
        return 1
    fi

    # ---- Step 5: teardown (must run inside the worktree) ----
    _gh_flow_set_state "$_dir" "tearing-down"
    if ! gwt teardown --force; then
        _gh_flow_set_state "$_dir" "failed:tearing-down"
        printf '[gh-flow-worker] gwt teardown failed\n' >&2
        return 1
    fi

    _gh_flow_set_state "$_dir" "done"
    printf '[gh-flow-worker] done issue=#%s end=%s\n' "$_issue" "$(date -Iseconds 2>/dev/null || date)"
}

# ============================================================================
# Project board Status sync
# ============================================================================
# Push a projectV2 Status transition for an Issue or PR. Auto-discovers every
# projectV2 the target belongs to; for each project that has a "Status" field
# with an option matching $3, updates the item's Status to that option.
#
# Failure is always quiet (returns 0) — the worker's primary job is
# implement/commit/PR, not board bookkeeping. Opt out with
# GH_FLOW_PROJECT_STATUS_SYNC=0.
#
# Usage: _gh_flow_set_project_status <issue|pr> <number> <status-name>
#   _gh_flow_set_project_status issue 42 "In progress"
#   _gh_flow_set_project_status pr    17 "In review"

_gh_flow_set_project_status() {
    local _kind="$1" _num="$2" _target="$3"
    local _owner _repo _q_field _triples _proj _item _field _option

    if [ "${GH_FLOW_PROJECT_STATUS_SYNC-1}" = "0" ]; then
        return 0
    fi
    if [ -z "$_kind" ] || [ -z "$_num" ] || [ -z "$_target" ]; then
        return 0
    fi

    case "$_kind" in
        issue) _q_field='issue' ;;
        pr) _q_field='pullRequest' ;;
        *)
            printf '[gh-flow-worker] project-status: invalid kind=%s, skipping\n' "$_kind" >&2
            return 0
            ;;
    esac

    # Single `gh repo view` call — two forks were redundant.
    if ! read -r _owner _repo <<EOF
$(gh repo view --json owner,name --jq '"\(.owner.login) \(.name)"' 2>/dev/null)
EOF
    then
        printf '[gh-flow-worker] project-status: could not determine owner/repo, skipping\n' >&2
        return 0
    fi
    if [ -z "$_owner" ] || [ -z "$_repo" ]; then
        printf '[gh-flow-worker] project-status: could not determine owner/repo, skipping\n' >&2
        return 0
    fi

    # Single query: find every projectV2 item for this issue/PR along with
    # the project's Status field and the target option (if it exists there).
    _triples=$(gh api graphql \
        -f query="
          query(\$owner: String!, \$repo: String!, \$number: Int!, \$target: String!) {
            repository(owner: \$owner, name: \$repo) {
              ${_q_field}(number: \$number) {
                projectItems(first: 10) {
                  nodes {
                    id
                    project {
                      id
                      field(name: \"Status\") {
                        ... on ProjectV2SingleSelectField {
                          id
                          options(names: [\$target]) { id name }
                        }
                      }
                    }
                  }
                }
              }
            }
          }" \
        -f owner="$_owner" -f repo="$_repo" -F number="$_num" -f target="$_target" \
        --jq ".data.repository.${_q_field}.projectItems.nodes[]
              | select(.project.field.options? | length > 0)
              | \"\(.project.id)|\(.id)|\(.project.field.id)|\(.project.field.options[0].id)\"" \
        2>/dev/null) || {
        printf '[gh-flow-worker] project-status: query failed for %s #%s (target=%s)\n' \
            "$_kind" "$_num" "$_target" >&2
        return 0
    }

    if [ -z "$_triples" ]; then
        printf '[gh-flow-worker] project-status: %s #%s not in any project with "%s" option\n' \
            "$_kind" "$_num" "$_target" >&2
        return 0
    fi

    # Avoid subshell — keep heredoc pattern instead of pipe (zsh/bash tracing).
    while IFS='|' read -r _proj _item _field _option; do
        [ -z "$_proj" ] && continue
        # GraphQL variables ($proj, $item, ...) are NOT shell vars — they
        # are bound via the -f flags below, so single quotes are intended.
        # shellcheck disable=SC2016
        if gh api graphql \
            -f query='
              mutation($proj: ID!, $item: ID!, $field: ID!, $option: String!) {
                updateProjectV2ItemFieldValue(input: {
                  projectId: $proj
                  itemId: $item
                  fieldId: $field
                  value: { singleSelectOptionId: $option }
                }) { clientMutationId }
              }' \
            -f proj="$_proj" -f item="$_item" -f field="$_field" -f option="$_option" \
            >/dev/null 2>&1; then
            printf '[gh-flow-worker] project-status: %s #%s -> "%s"\n' "$_kind" "$_num" "$_target"
        else
            printf '[gh-flow-worker] project-status: mutation failed for %s #%s (target=%s)\n' \
                "$_kind" "$_num" "$_target" >&2
        fi
    done <<EOF
$_triples
EOF

    return 0
}

# ============================================================================
# Aliases (hyphenated command names per shell-common convention)
# ============================================================================

alias gh-flow='gh_flow'
alias gh-flow-help='gh_flow_help'
