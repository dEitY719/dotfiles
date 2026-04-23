#!/bin/sh
# shell-common/functions/git_worktree.sh
# Git worktree management functions (split from git.sh)

# Override Oh My Zsh's gwt alias (zsh only)
unalias gwt 2>/dev/null || true

# ============================================================================
# gwt-help — compact help (canonical)
# Usage: gwt-help [section]
# ============================================================================
_gwt_help_summary() {
    ux_info "Usage: gwt-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "add: gwt add <path> [branch] [start]"
    ux_bullet_sub "list: gwt list | gwt ls"
    ux_bullet_sub "remove: gwt remove <path|agent|all> [--force]"
    ux_bullet_sub "prune: gwt prune"
    ux_bullet_sub "spawn: gwt spawn <name> [--task slug] [--base ref] [--tmux]"
    ux_bullet_sub "teardown: gwt teardown [--force] [--keep-branch]"
    ux_bullet_sub "details: gwt-help <section> (example: gwt-help spawn)"
}

_gwt_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "add"
    ux_bullet_sub "list"
    ux_bullet_sub "remove"
    ux_bullet_sub "prune"
    ux_bullet_sub "spawn"
    ux_bullet_sub "teardown"
}

_gwt_help_rows_add() {
    ux_table_row "syntax" "gwt add <path> [<new-branch> [<start-point>]]" "Create git-crypt-safe worktree"
    ux_table_row "behavior" "Sparse checkout excludes encrypted paths" "Keeps encrypted layout safe"
}

_gwt_help_rows_list() {
    ux_table_row "syntax" "gwt list | gwt ls" "List linked worktrees"
    ux_table_row "output" "path | commit | branch" "Adds remove hint when count > 1"
}

_gwt_help_rows_remove() {
    ux_table_row "syntax" "gwt remove <path|name|all> [--force]" "Remove worktree + branch"
    ux_table_row "name mode" "<name> matches *-<name>-*" "Batch remove by worktree name"
    ux_table_row "all mode" "all removes non-main worktrees" "Batch cleanup"
    ux_table_row "force" "--force" "Force remove and branch delete"
}

_gwt_help_rows_prune() {
    ux_table_row "syntax" "gwt prune" "Run: git worktree prune"
}

_gwt_help_rows_spawn() {
    ux_table_row "syntax" "gwt spawn <name> [--task <slug>] [--base <ref>] [--tmux [--agent <agent>]]" "Create named worktree"
    ux_table_row "context" "Run from main repo only" "Fails inside a worktree"
    ux_table_row "name" "Free-form slug (required)" "e.g. issue-11, login-fix"
    ux_table_row "--agent" "AI agent for tmux pane (default: claude)" "claude, codex, gemini, opencode, cursor, copilot"
    ux_table_row "--tmux" "Runs <agent>-yolo in pane" "Decoupled from worktree <name>"
    ux_table_row "example" "gwt spawn issue-11 --tmux --agent codex" "Free-form name + codex agent"
}

_gwt_help_rows_teardown() {
    ux_table_row "syntax" "gwt teardown [--force] [--keep-branch]" "Cleanup current AI worktree"
    ux_table_row "context" "Run inside a worktree" "Syncs main repo after cleanup"
    ux_table_row "flags" "--force / --keep-branch" "Discard changes / keep branch"
}

_gwt_help_render_section() {
    ux_section "$1"
    "$2"
}

_gwt_help_section_rows() {
    case "$1" in
        add)
            _gwt_help_rows_add
            ;;
        list|ls)
            _gwt_help_rows_list
            ;;
        remove|rm)
            _gwt_help_rows_remove
            ;;
        prune)
            _gwt_help_rows_prune
            ;;
        spawn)
            _gwt_help_rows_spawn
            ;;
        teardown)
            _gwt_help_rows_teardown
            ;;
        *)
            ux_error "Unknown gwt-help section: $1"
            ux_info "Try: gwt-help --list"
            return 1
            ;;
    esac
}

_gwt_help_full() {
    ux_header "Git Worktree Commands"

    _gwt_help_render_section "Add" _gwt_help_rows_add
    _gwt_help_render_section "List" _gwt_help_rows_list
    _gwt_help_render_section "Remove" _gwt_help_rows_remove
    _gwt_help_render_section "Prune" _gwt_help_rows_prune
    _gwt_help_render_section "Spawn" _gwt_help_rows_spawn
    _gwt_help_render_section "Teardown" _gwt_help_rows_teardown
}

gwt_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _gwt_help_summary
            ;;
        --list|list|section|sections)
            _gwt_help_list_sections
            ;;
        --all|all)
            _gwt_help_full
            ;;
        *)
            _gwt_help_section_rows "$1"
            ;;
    esac
}

# ============================================================================
# gwt — git worktree dispatcher
# Usage: gwt <subcommand> [args...]
# ============================================================================
gwt() {
    case "${1:-}" in
        add)      shift; git_worktree_add "$@" ;;
        list|ls)  shift; git_worktree_list "$@" ;;
        remove|rm) shift; git_worktree_remove "$@" ;;
        prune)    shift; git worktree prune "$@" ;;
        spawn)    shift; git_worktree_spawn "$@" ;;
        teardown) shift; git_worktree_teardown "$@" ;;
        -h|--help|help|"")
            ux_error "Usage: gwt <command> [args...]"
            ux_info "Run: gwt-help"
            return 1
            ;;
        *)
            ux_error "Unknown command: $1"
            ux_info "Run: gwt-help"
            return 1
            ;;
    esac
}

# ============================================================================
# Worktree list — formatted output with column headers and remove hint
# Usage: git_worktree_list
# ============================================================================
git_worktree_list() {
    local wt_output
    wt_output="$(git worktree list)"

    local wt_count
    wt_count=$(printf '%s\n' "$wt_output" | wc -l)

    ux_header "Git worktrees ($wt_count)"
    {
        printf '[path] [commit] [branch]\n'
        printf '%s\n' "$wt_output"
    } | column -t

    if [ "$wt_count" -gt 1 ]; then
        echo
        ux_info "To remove: gwt remove [path]"
    fi
}

# ============================================================================
# Worktree remove — remove worktree AND its associated branch
# Usage: git_worktree_remove <path> [--force]
# ============================================================================
git_worktree_remove() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    case "${1:-}" in
        -h|--help)
            ux_header "gwt remove - remove worktree and branch"
            ux_info "Usage: gwt remove <path|name|all> [--force]"
            ux_info ""
            ux_info "  <path>     full or relative worktree path"
            ux_info "  <name>     worktree name (free-form: issue-11, login-fix, ...)"
            ux_info "             removes ALL worktrees matching *-<name>-*"
            ux_info "  all        remove ALL non-main worktrees"
            ux_info "  --force    force remove + force delete unmerged branch"
            return 0
            ;;
        "")
            ux_error "Usage: gwt remove <path|name> [--force]"
            return 1
            ;;
    esac

    local target="$1"
    local force=false
    [ "${2:-}" = "--force" ] && force=true

    # "all" — remove every non-main worktree
    if [ "$target" = "all" ]; then
        local main_wt
        main_wt="$(git worktree list --porcelain | head -1)"
        main_wt="${main_wt#worktree }"

        local all_wts="" all_count=0
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
$(git worktree list --porcelain)
EOF

        if [ "$all_count" -eq 0 ]; then
            ux_info "No extra worktrees to remove."
            return 0
        fi

        ux_warning "This will remove $all_count worktree(s):"
        while IFS= read -r wt; do
            [ -n "$wt" ] || continue
            ux_info "  $wt"
        done <<EOF
$all_wts
EOF

        if [ "$force" != true ]; then
            printf 'Proceed? [y/N] '
            read -r answer
            case "$answer" in
                [yY]*) ;;
                *) ux_info "Aborted."; return 0 ;;
            esac
        fi

        local fail_count=0
        while IFS= read -r wt; do
            [ -n "$wt" ] || continue
            _gwt_remove_one "$wt" "$force" || fail_count=$((fail_count + 1))
        done <<EOF
$all_wts
EOF
        [ "$fail_count" -eq 0 ] && return 0 || return 1
    fi

    # If target is an existing path, remove directly.
    # Otherwise treat it as a worktree name and resolve to *-<name>-* worktrees.
    if [ -d "$target" ] || [ -e "$target" ]; then
        _gwt_remove_one "$target" "$force"
        return $?
    fi

    # Resolve worktree name to path(s)
    local project parent matches=""
    project="$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")"
    parent="$(dirname "$(git rev-parse --show-toplevel 2>/dev/null)")"
    local match_count=0

    for dir in "$parent/${project}-${target}"-*/; do
        if [ -d "$dir" ]; then
            matches="${matches}${dir%/}
"
            match_count=$((match_count + 1))
        fi
    done

    if [ "$match_count" -eq 0 ]; then
        # Fallback: check for registered but missing worktrees (orphan cleanup)
        local wt_registered=""
        wt_registered="$(git worktree list --porcelain | while IFS= read -r line; do
            case "$line" in
                "worktree "*"-${target}-"*) printf '%s\n' "${line#worktree }" ;;
            esac
        done)"

        if [ -n "$wt_registered" ]; then
            git worktree prune
            ux_success "Pruned stale worktree refs for '$target'"
            git for-each-ref --format='%(refname:short)' "refs/heads/wt/${target}/" | while IFS= read -r branch; do
                if git branch -d "$branch" 2>/dev/null; then
                    ux_success "Branch deleted: $branch"
                elif [ "$force" = true ]; then
                    git branch -D "$branch" 2>/dev/null
                    ux_success "Branch force-deleted: $branch"
                else
                    ux_warning "Branch '$branch' not fully merged. Use --force to delete."
                fi
            done
            return 0
        fi

        ux_error "No worktree found: $target"
        ux_info "  No *-${target}-* worktrees exist."
        ux_info "  Run 'gwt list' to see available worktrees."
        return 1
    fi

    # Remove each matched worktree
    while IFS= read -r wt_path; do
        [ -n "$wt_path" ] || continue
        _gwt_remove_one "$wt_path" "$force"
    done <<EOF
$matches
EOF
}

# Internal: remove a single worktree + its branch
_gwt_remove_one() {
    local wt_path="$1" force="$2"

    # Detect branch before removing worktree
    local branch=""
    if [ -d "$wt_path" ]; then
        branch="$(git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null)" || true
    fi

    # Remove worktree
    if ! git worktree remove "$wt_path" 2>/dev/null; then
        if [ "$force" = true ]; then
            git worktree remove --force "$wt_path" || { ux_error "Failed to remove: $wt_path"; return 1; }
        else
            ux_error "Cannot remove: $wt_path"
            ux_info "  Use: gwt remove $wt_path --force"
            return 1
        fi
    fi
    git worktree prune

    ux_success "Worktree removed: $wt_path"

    # Delete branch (skip main/master)
    if [ -n "$branch" ] && [ "$branch" != "main" ] && [ "$branch" != "master" ] && [ "$branch" != "HEAD" ]; then
        if git branch -d "$branch" 2>/dev/null; then
            ux_success "Branch deleted: $branch"
        elif [ "$force" = true ]; then
            git branch -D "$branch" 2>/dev/null
            ux_success "Branch force-deleted: $branch"
        else
            ux_warning "Branch '$branch' not fully merged. Use --force to delete."
        fi
    fi
}

git_worktree_add() {
    case "${1:-}" in
        -h|--help)
            ux_header "gwt add - git-crypt safe worktree"
            ux_info "Usage: gwt add <path> [<new-branch> [<start-point>]]"
            ux_info "  Creates a worktree with git-crypt encrypted files excluded"
            return 0
            ;;
        "")
            ux_error "Usage: gwt add <path> [<new-branch> [<start-point>]]"
            return 1
            ;;
    esac

    local wt_path="$1"
    local branch="$2"
    local start_point="$3"

    # Build worktree add command
    if [ -n "$branch" ] && [ -n "$start_point" ]; then
        git worktree add --no-checkout -b "$branch" "$wt_path" "$start_point"
    elif [ -n "$branch" ]; then
        git worktree add --no-checkout -b "$branch" "$wt_path"
    else
        git worktree add --no-checkout "$wt_path"
    fi || return 1

    # Sparse-checkout: include everything except git-crypt encrypted files
    # Dynamically parse .gitattributes for filter=git-crypt patterns
    local repo_root excludes="" exclude_display=""
    repo_root="$(git rev-parse --show-toplevel)"
    if [ -f "$repo_root/.gitattributes" ]; then
        while IFS= read -r line; do
            case "$line" in
                *filter=git-crypt*)
                    local pattern
                    pattern="$(printf '%s' "$line" | awk '{print $1}')"
                    excludes="${excludes}!/${pattern}\n"
                    exclude_display="${exclude_display} ${pattern}"
                    ;;
            esac
        done < "$repo_root/.gitattributes"
    fi

    git -C "$wt_path" sparse-checkout init --no-cone
    printf "/*\n${excludes}" | git -C "$wt_path" sparse-checkout set --stdin

    git -C "$wt_path" checkout || {
        ux_error "Checkout failed in worktree: $wt_path"
        return 1
    }

    ux_success "Worktree ready: $wt_path"
    if [ -n "$exclude_display" ]; then
        ux_info "  git-crypt excluded:${exclude_display}"
    fi
}

# ============================================================================
# Worktree spawn — auto-index, auto-branch, log
# Usage: git_worktree_spawn <name> [--task <slug>] [--base <ref>] [--tmux]
# ============================================================================
_git_worktree_spawn_show_help() {
    ux_header "gwt spawn - create a named worktree"
    ux_info "Usage: gwt spawn <name> [--task <slug>] [--base <ref>] [--tmux [--agent <agent>]]"
    ux_info ""
    ux_info "Arguments:"
    ux_info "  <name>           Free-form worktree name (required)."
    ux_info "                   Safe chars only: no '/', no spaces, no leading dash."
    ux_info "                   Examples: issue-11, login-fix, feature-x"
    ux_info "  --task <slug>    Add task slug to branch name"
    ux_info "  --base <ref>     Base branch/commit (default: origin/main)"
    ux_info "  --tmux           Auto-create tmux session/window with 3-pane layout"
    ux_info "  --agent <agent>  AI agent to run in the tmux pane (default: claude)"
    ux_info "                   Known: claude, codex, gemini, opencode, cursor, copilot"
    ux_info "                   Window name and 'yolo' command follow --agent,"
    ux_info "                   so worktree <name> can be any free-form slug."
    ux_info ""
    ux_info "Examples:"
    ux_info "  gwt spawn issue-11                           # ../<proj>-issue-11-1  wt/issue-11/1"
    ux_info "  gwt spawn login-fix --task auth              # ../<proj>-login-fix-1 wt/login-fix/1-auth"
    ux_info "  gwt spawn issue-11 --tmux                    # tmux window 'claude' runs 'claude-yolo'"
    ux_info "  gwt spawn issue-11 --tmux --agent codex      # tmux window 'codex'  runs 'codex-yolo'"
}

git_worktree_spawn() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local task="" base="" name="" use_tmux=0 agent="claude"

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                _git_worktree_spawn_show_help
                return 0
                ;;
            --task) task="$2"; shift 2 ;;
            --base) base="$2"; shift 2 ;;
            --agent) agent="$2"; shift 2 ;;
            --tmux) use_tmux=1; shift ;;
            -*)
                ux_error "Unknown option: $1"
                echo ""
                _git_worktree_spawn_show_help
                return 1
                ;;
            *)
                if [ -n "$name" ]; then
                    ux_error "Multiple names given: '$name', '$1' (only one allowed)"
                    echo ""
                    _git_worktree_spawn_show_help
                    return 1
                fi
                name="$1"
                shift
                ;;
        esac
    done

    # Name is required
    if [ -z "$name" ]; then
        ux_error "<name> is required"
        echo ""
        _git_worktree_spawn_show_help
        return 1
    fi

    # Validate name: no path separators, no spaces, no leading dash
    case "$name" in
        -* | */* | *" "*)
            ux_error "Invalid name: '$name' (no '/', no spaces, no leading dash)"
            return 1
            ;;
    esac

    # Validate --tmux dependency
    if [ "$use_tmux" = 1 ] && ! command -v tmux >/dev/null 2>&1; then
        ux_error "tmux is not installed (required for --tmux)"
        return 1
    fi

    # Validate --agent: must be a known AI agent (only when tmux will use it)
    if [ "$use_tmux" = 1 ] && ! _ts_known_agent "$agent"; then
        ux_error "Unknown agent: $agent"
        ux_info "Available: claude, codex, gemini, opencode, cursor, copilot"
        return 1
    fi

    # Must be inside a git repo, NOT a worktree
    local git_common git_dir
    git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || {
        ux_error "Not inside a git repository"; return 1
    }
    git_dir="$(git rev-parse --git-dir)"
    if [ "$git_dir" != "$git_common" ]; then
        ux_error "Cannot spawn from inside a worktree. Run from the main repo."
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

    local wt_path="${parent}/${project}-${name}-${next_index}"

    # Branch name
    local branch
    if [ -n "$task" ]; then
        local slug
        slug=$(printf '%s' "$task" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-30)
        branch="wt/${name}/${next_index}-${slug}"
    else
        branch="wt/${name}/${next_index}"
    fi

    # Base ref
    if [ -z "$base" ]; then
        if git rev-parse --verify --quiet "origin/main" >/dev/null 2>&1; then
            base="origin/main"
        elif git rev-parse --verify --quiet "main" >/dev/null 2>&1; then
            base="main"
        else
            base="HEAD"
        fi
    fi

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

    # --- Optional tmux integration ---
    if [ "$use_tmux" = 1 ]; then
        _tmux_add_agent_window "$project" "$agent" "$wt_path"
        ux_info "  tmux:   session '$project', window '$agent' (runs ${agent}-yolo)"
        if [ -z "$TMUX" ]; then
            tmux attach -t "$project"
        else
            tmux switch-client -t "${project}:${agent}" 2>/dev/null || true
        fi
    else
        ux_info ""
        ux_info "  cd $wt_path"
    fi
}

# ============================================================================
# Internal: check if current HEAD's commits are safe to discard
# Returns 0 (safe) if: upstream matches, or HEAD is in origin/main,
# or all patches are already in origin/main (rebase/squash merge).
# ============================================================================
_gwt_commits_safe() {
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

    # 3. All patches already applied via rebase/squash merge (patch-id comparison)
    # git cherry marks already-applied commits with '-', unapplied with '+'.
    # If grep finds no '+' line, every HEAD commit is patch-id-equivalent to
    # something already in main_ref → safe.
    if ! git cherry "$main_ref" HEAD 2>/dev/null | grep -q '^+'; then
        return 0
    fi

    # 4. Upstream exists but remote branch was deleted (PR merged + branch auto-deleted)
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
# Internal: check if a branch's patches are in target (rebase/squash merge)
# Usage: _gwt_branch_merged <branch> <target>
# Returns 0 if all patches in <branch> are already in <target>.
# ============================================================================
_gwt_branch_merged() {
    local branch="$1" target="$2"
    # No '+' line from git cherry → all patches already in target.
    ! git cherry "$target" "$branch" 2>/dev/null | grep -q '^+'
}

# ============================================================================
# Internal: pick the best merge-detection target. Prefer origin/<main> if
# fetched, else fall back to local <main> (stale detection better than none).
# Usage: _gwt_merge_target <main_branch>
# ============================================================================
_gwt_merge_target() {
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
    local branch="$1"
    local main_ref="origin/main"
    git rev-parse --verify --quiet "$main_ref" >/dev/null 2>&1 || main_ref="origin/master"

    local upstream ahead
    upstream="$(git rev-parse --abbrev-ref '@{u}' 2>/dev/null || echo "(none)")"
    ahead="$(git rev-list --count "$main_ref"..HEAD 2>/dev/null || echo "?")"

    ux_error "Unpushed commits on '$branch' ($ahead ahead of $main_ref, upstream: $upstream)."
    ux_info "  Push:   git push -u origin $branch"
    ux_info "  Or:     gwt teardown --force   # discard the unpushed commits"
    if [ "$ahead" != "?" ] && [ "$ahead" != "0" ]; then
        ux_info "  Unpushed commits (newest first):"
        git log --no-color --format='    %h %s' "$main_ref"..HEAD 2>/dev/null | head -10
    fi
}

# ============================================================================
# Worktree teardown — remove worktree, sync main, delete branch, log
# Usage: git_worktree_teardown [--force] [--keep-branch]
# ============================================================================
git_worktree_teardown() {
    # zsh compatibility
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    local force=false keep_branch=false

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                ux_header "gwt teardown - AI worktree cleanup"
                ux_info "Usage: gwt teardown [--force] [--keep-branch]"
                ux_info ""
                ux_info "Options:"
                ux_info "  --force        discard uncommitted changes and force remove"
                ux_info "  --keep-branch  keep the branch after removing worktree"
                return 0
                ;;
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
                    ux_error "Not inside a git repository"
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
                fi
                return 1
                ;;
        esac
    done

    # Must be inside a worktree
    local git_common git_dir
    git_common="$(git rev-parse --git-common-dir 2>/dev/null)" || {
        ux_error "Not inside a git repository"; return 1
    }
    git_dir="$(git rev-parse --git-dir)"
    if [ "$git_dir" = "$git_common" ]; then
        ux_error "Not inside a worktree. Nothing to tear down."
        return 1
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

    # Pre-flight: unpushed commits.
    # (A) Capture fetch stderr so failures surface the actual cause, not a
    # misleading "network?" blurb. Real reason (auth, hook, URL, etc.) wins.
    local _gwt_fetch_err_file="${TMPDIR:-/tmp}/gwt-fetch.$$.err"
    if ! git fetch origin 2>"$_gwt_fetch_err_file" >/dev/null; then
        ux_warning "git fetch origin failed — merge status check may be stale."
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

    # Collect info before leaving
    local wt_path branch wt_name main_repo
    wt_path="$(git rev-parse --show-toplevel)"
    branch="$(git rev-parse --abbrev-ref HEAD)"
    wt_name="$(basename "$wt_path")"
    main_repo="$(dirname "$git_common")"

    # Switch to main repo
    cd "$main_repo" || { ux_error "Cannot cd to $main_repo"; return 1; }

    # Remove worktree
    if ! git worktree remove "$wt_path" 2>/dev/null; then
        if [ "$force" = true ]; then
            git worktree remove --force "$wt_path" || { ux_error "Failed to remove worktree"; return 1; }
        else
            ux_error "Cannot remove worktree. Use --force to override."
            return 1
        fi
    fi
    git worktree prune

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
            ux_info "  Local '$main_branch' has diverged from origin/$main_branch."
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

    # Delete branch
    if [ "$keep_branch" = true ]; then
        ux_info "Branch kept: $branch (--keep-branch)"
    elif git branch -d "$branch" 2>/dev/null; then
        : # deleted successfully (fast-forward or true merge)
    elif _gwt_branch_merged "$branch" "$merge_target"; then
        # Rebase/squash merge: commits are in main_ref but SHAs differ.
        git branch -D "$branch" 2>/dev/null
        ux_success "Branch deleted (rebase-merged): $branch"
    elif [ "$force" = true ]; then
        git branch -D "$branch" 2>/dev/null
        ux_success "Branch force-deleted: $branch"
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

alias gwt-help='gwt_help'
