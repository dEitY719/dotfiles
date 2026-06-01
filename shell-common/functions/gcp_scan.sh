#!/bin/sh
# shell-common/functions/gcp_scan.sh
#
# Portable cherry-pick scanner - works in bash, zsh, and other POSIX shells
# Intelligently identifies and cherry-picks missing commits.
#
# Exposed via the gcp dispatcher (Type 2A — see gcp.sh and
# docs/.ssot/command-design-pattern.md §4):
#
#   gcp scan [base] [src] [--author=<name|all>]
#
# The deprecated 'gcp_scan' / 'gcp-scan' forms remain available as aliases
# (defined in gcp.sh) for backward compatibility — issue #697.
#
# Note: git cherry marks commits as:
#   '+' = present in source, missing in base (will be cherry-picked)
#   '-' = already merged in base
#
# Redundant-commit handling (issue #913, supersedes #903/#907/#908/#910):
# every candidate is run through `_gcp_scan_preflight_is_noop` BEFORE any real
# cherry-pick. The probe uses git's own merge engine (`cherry-pick -n`) so it
# is immune to the context-drift failures (comment rewrites, refactors) that
# broke the earlier file-compare / reverse-patch heuristics. The contiguous
# "range cherry-pick" shortcut is gone — every commit is iterated individually
# so the pre-flight is never bypassed.
#

case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac

_gcp_scan_is_empty_cherry_pick() {
    # True when cherry-pick is in progress, has no conflicts, and results in an empty commit
    # (git suggests: git cherry-pick --skip).
    git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1 || return 1
    git ls-files -u 2>/dev/null | grep -q . && return 1
    git diff --quiet >/dev/null 2>&1 || return 1
    git diff --cached --quiet >/dev/null 2>&1 || return 1
    return 0
}

_gcp_scan_preflight_is_noop() {
    # True (0) when cherry-picking commit $1 onto HEAD would add nothing — the
    # commit is already absorbed in HEAD (issue #913). Probes with git's own
    # merge engine instead of textual heuristics, so it survives context drift:
    #
    #   * Clean apply, empty staged diff  -> already in HEAD            -> noop.
    #   * Conflict that, once every conflicted file is reset to HEAD,
    #     leaves an empty staged diff     -> only context drifted       -> noop.
    #   * Anything that leaves a non-empty staged diff (a clean change, or a
    #     conflict carrying genuinely new content) -> real work         -> keep.
    #
    # The probe is NON-DESTRUCTIVE: a dirty working tree is stashed first and
    # popped at the end, and the index/tree are restored with `git reset --hard`
    # (a `cherry-pick -n` never records sequencer state, so no --abort needed).
    local sha="$1" result=1 had_stash=0 conflicted f
    if ! git diff --quiet || ! git diff --cached --quiet; then
        git stash push -q --include-untracked -m "gcp_preflight_probe" && had_stash=1
    fi
    if git cherry-pick -n "$sha" >/dev/null 2>&1; then
        git diff --cached --quiet && result=0
    else
        conflicted=$(git diff --name-only --diff-filter=U)
        echo "$conflicted" | while IFS= read -r f; do
            [ -z "$f" ] && continue
            git checkout HEAD -- "$f"
        done
        git add -A
        git diff --cached --quiet && result=0
    fi
    git reset --hard HEAD >/dev/null 2>&1
    [ "$had_stash" -eq 1 ] && git stash pop -q >/dev/null 2>&1
    return $result
}

_gcp_scan_dup_base_sha() {
    # Look up the base-branch SHA that a duplicate source SHA matches.
    # $1 = candidate source SHA; $2 = duplicate map ("SRC_SHA BASE_SHA" lines).
    # Prints the matching base SHA (or nothing) — issue #811 F-3. Pure shell
    # (here-doc `while read`, no awk fork) per PR #812 review.
    local target="$1"
    local src_sha base_sha
    while read -r src_sha base_sha; do
        if [ "$src_sha" = "$target" ]; then
            printf '%s\n' "$base_sha"
            return 0
        fi
    done <<EOF
$2
EOF
}

_gcp_scan() {
    # zsh compatibility: emulate POSIX sh to ensure consistent behavior
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    # zsh/bash compatibility: disable debug tracing
    local _xtrace_set=0
    case $- in *x*) _xtrace_set=1 ;; esac
    set +x 2>/dev/null

    local base="main"
    local source="upstream/main"
    local author="dEitY719"
    local arg1="" arg2=""

    # Check for incomplete cherry-pick
    if git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1; then
        if type ux_error >/dev/null 2>&1; then
            ux_error "Cherry-pick currently in progress!"
            ux_error "Please resolve it first:"
            ux_error "  git cherry-pick --continue  (or)"
            ux_error "  git cherry-pick --abort"
        else
            echo "Error: Cherry-pick currently in progress!" >&2
            echo "Please resolve it first:" >&2
            echo "  git cherry-pick --continue  (or)" >&2
            echo "  git cherry-pick --abort" >&2
        fi
        return 1
    fi

    # Parse arguments (simpler than bash array approach, works in all shells)
    while [ $# -gt 0 ]; do
        case "$1" in
        --author=*)
            author="${1#--author=}"
            ;;
        --author)
            if [ -n "${2-}" ]; then
                author="$2"
                shift
            else
                if type ux_error >/dev/null 2>&1; then
                    ux_error "--author requires a value"
                else
                    echo "Error: --author requires a value" >&2
                fi
                return 1
            fi
            ;;
        *)
            # Store positional arguments without array syntax
            if [ -z "$arg1" ]; then
                arg1="$1"
            elif [ -z "$arg2" ]; then
                arg2="$1"
            fi
            ;;
        esac
        shift
    done

    # Apply positional arguments
    if [ -n "$arg1" ]; then
        base="$arg1"
    fi
    if [ -n "$arg2" ]; then
        source="$arg2"
    fi

    # Use ux_header if available
    if type ux_header >/dev/null 2>&1; then
        ux_header "Scanning for missing commits from '$source' in '$base'..."
    else
        echo "=== Scanning for missing commits from '$source' in '$base'... ==="
    fi

    # Verify branches exist
    if ! git rev-parse --verify "$base" >/dev/null 2>&1; then
        if type ux_error >/dev/null 2>&1; then
            ux_error "Base branch '$base' does not exist."
        else
            echo "Error: Base branch '$base' does not exist." >&2
        fi
        return 1
    fi
    if ! git rev-parse --verify "$source" >/dev/null 2>&1; then
        if type ux_error >/dev/null 2>&1; then
            ux_error "Source branch '$source' does not exist."
        else
            echo "Error: Source branch '$source' does not exist." >&2
        fi
        return 1
    fi

    # Find missing commits (present in source, missing in base)
    local missing_list
    missing_list=$(git cherry "$base" "$source" | grep "^+" | awk '{print $2}')

    if [ -z "$missing_list" ]; then
        if type ux_success >/dev/null 2>&1; then
            ux_success "No missing commits found! '$base' is up to date with '$source'."
        else
            echo "✓ No missing commits found! '$base' is up to date with '$source'."
        fi
        return 0
    fi

    local total_count
    total_count=$(echo "$missing_list" | wc -l)
    local author_lc
    author_lc=$(printf '%s' "$author" | tr '[:upper:]' '[:lower:]')

    # Filter by author unless explicitly showing all
    local selected_list=""
    if [ "$author_lc" = "all" ]; then
        selected_list="$missing_list"
    else
        while IFS= read -r sha; do
            [ -z "$sha" ] && continue
            local commit_author
            commit_author=$(git show -s --format='%an' "$sha")
            if [ "$(printf '%s' "$commit_author" | tr '[:upper:]' '[:lower:]')" = "$author_lc" ]; then
                if [ -z "$selected_list" ]; then
                    selected_list="$sha"
                else
                    selected_list="${selected_list}"$'\n'"$sha"
                fi
            fi
        done <<EOF
$missing_list
EOF
    fi

    if [ -z "$selected_list" ]; then
        if type ux_warning >/dev/null 2>&1; then
            ux_warning "No missing commits match author '$author'."
            ux_info "Use --author=all to show all missing commits."
        else
            echo "⚠ No missing commits match author '$author'." >&2
            echo "ℹ Use --author=all to show all missing commits." >&2
        fi
        return 0
    fi

    local count
    count=$(echo "$selected_list" | wc -l)

    # Stage-1: subject-based duplicate detection (same subject already in base).
    local final_selected_list=""
    local duplicate_list=""
    local duplicate_map=""
    local duplicate_count=0

    # Cache the base branch's recent subjects ONCE (PR #812 review): running
    # `git log` per source commit was an O(N) process-fork bottleneck. The
    # per-commit lookup below is then a pure-shell here-doc `while read`
    # (no git/awk fork, no pipe subshell).
    local base_log tab
    base_log=$(git log "$base" -n 200 --format='%H%x09%s' 2>/dev/null)
    tab=$(printf '\t')

    while IFS= read -r sha; do
        [ -z "$sha" ] && continue
        local subject
        subject=$(git show -s --format='%s' "$sha")

        # Find a base commit with the same subject and capture its SHA so the
        # individual cherry-pick loop can report what each dup was already
        # applied as (issue #811 F-1/F-3). Exact subject match via tab split.
        local match_base_sha="" _b_sha _b_subj
        while IFS="$tab" read -r _b_sha _b_subj; do
            if [ "$_b_subj" = "$subject" ]; then
                match_base_sha="$_b_sha"
                break
            fi
        done <<EOF
$base_log
EOF
        if [ -n "$match_base_sha" ]; then
            duplicate_list="${duplicate_list}${sha}"$'\n'
            duplicate_map="${duplicate_map}${sha} ${match_base_sha}"$'\n'
            duplicate_count=$((duplicate_count + 1))
        else
            if [ -z "$final_selected_list" ]; then
                final_selected_list="$sha"
            else
                final_selected_list="${final_selected_list}"$'\n'"${sha}"
            fi
        fi
    done <<EOF
$selected_list
EOF

    # Update count if duplicates exist
    if [ $duplicate_count -gt 0 ]; then
        count=$((count - duplicate_count))
    fi

    # Early return: all commits are duplicates (already applied)
    if [ $count -eq 0 ]; then
        if type ux_section >/dev/null 2>&1; then
            ux_section "Analysis Result"
            ux_bullet "Missing (all authors): $total_count"
            ux_bullet "Author filter: $author -> 0 new commit(s)"
            ux_bullet "Duplicates (already applied): $duplicate_count"
        else
            echo "=== Analysis Result ==="
            echo "  Missing (all authors): $total_count"
            echo "  Author filter: $author -> 0 new commit(s)"
            echo "  Duplicates (already applied): $duplicate_count"
        fi
        if type ux_success >/dev/null 2>&1; then
            ux_success "All matching commits are already applied to '$base'. Nothing to do."
        else
            echo "✓ All matching commits are already applied to '$base'. Nothing to do."
        fi
        return 0
    fi

    # Calculate the (informational) range from non-duplicate commits only.
    local first_sha
    first_sha=$(echo "$final_selected_list" | head -n 1)
    local last_sha
    last_sha=$(echo "$final_selected_list" | tail -n 1)
    local range_str="${first_sha}^..${last_sha}"

    # Display Summary
    if type ux_section >/dev/null 2>&1; then
        ux_section "Analysis Result"
        ux_bullet "Missing (all authors): $total_count"
        ux_bullet "Author filter: $author -> $count commit(s)"
        if [ $duplicate_count -gt 0 ]; then
            ux_bullet "Duplicates (already applied): $duplicate_count"
        fi
        ux_bullet "Suggested Range: $range_str"
    else
        echo "=== Analysis Result ==="
        echo "  Missing (all authors): $total_count"
        echo "  Author filter: $author -> $count commit(s)"
        if [ $duplicate_count -gt 0 ]; then
            echo "  Duplicates (already applied): $duplicate_count"
        fi
        echo "  Suggested Range: $range_str"
    fi

    # Display Commits
    if type ux_section >/dev/null 2>&1; then
        ux_section "Commit List"
    else
        echo "=== Commit List ==="
    fi
    if type ux_info >/dev/null 2>&1; then
        ux_info "Commits to cherry-pick:"
    else
        echo "Commits to cherry-pick:"
    fi

    local line_num=0
    while IFS= read -r sha; do
        [ -z "$sha" ] && continue
        line_num=$((line_num + 1))

        local line
        line=$(git log --no-walk --format="%C(auto)%h %C(green)%ad %C(blue)%an%C(auto)%d %s" --date=short "$sha")

        printf " %d. %s\n" "$line_num" "$line"
    done <<EOF
$final_selected_list
EOF

    # Interactive Confirmation
    if ! type ux_confirm >/dev/null 2>&1; then
        return 0
    fi
    if ! ux_confirm "Do you want to cherry-pick these $count commits?" "n"; then
        if type ux_info >/dev/null 2>&1; then
            ux_info "Cancelled. You can use the range above manually: git cherry-pick $range_str"
        fi
        # Restore tracing if it was enabled
        if [ $_xtrace_set -eq 1 ]; then
            set -x
        fi
        return 0
    fi

    # Always iterate individually (issue #913): the contiguous range shortcut
    # is gone so the no-op pre-flight below can NEVER be bypassed. Iterate the
    # full author-filtered list (selected_list) — not the dup-pruned
    # final_selected_list — so Stage-1 dups are skipped *with a log line*
    # instead of being silently dropped (issue #811 F-1/F-2).
    local picked=0
    local empty_skipped=0
    local noop_skipped=0
    local dup_skipped=0
    while IFS= read -r sha; do
        [ -z "$sha" ] && continue

        # Stage-1 subject duplicate: skip without a cherry-pick attempt,
        # naming the base SHA it matches (issue #811 F-2/F-3).
        local dup_base_sha
        dup_base_sha=$(_gcp_scan_dup_base_sha "$sha" "$duplicate_map")
        if [ -n "$dup_base_sha" ]; then
            if type ux_info >/dev/null 2>&1; then
                ux_info "Skipping ${sha} — already applied as ${dup_base_sha} (duplicate subject)"
            else
                echo "ℹ Skipping ${sha} — already applied as ${dup_base_sha} (duplicate subject)"
            fi
            dup_skipped=$((dup_skipped + 1))
            continue
        fi

        # No-op pre-flight (issue #913): merge-probe the commit onto HEAD. If it
        # adds nothing — already in HEAD, or a pure context-drift conflict that
        # resolves to HEAD — skip it. Catches the recurring 092d0512 case the
        # subject-based Stage-1 misses, BEFORE any real cherry-pick conflicts.
        if _gcp_scan_preflight_is_noop "$sha"; then
            if type ux_info >/dev/null 2>&1; then
                ux_info "Skipping ${sha} — already in HEAD (no-op pre-flight)"
            else
                echo "ℹ Skipping ${sha} — already in HEAD (no-op pre-flight)"
            fi
            noop_skipped=$((noop_skipped + 1))
            continue
        fi

        if type ux_info >/dev/null 2>&1; then
            ux_info "Cherry-picking $sha..."
        fi
        if git cherry-pick "$sha"; then
            picked=$((picked + 1))
        else
            # Defensive: a commit that becomes empty against HEAD (no conflict)
            # still needs an explicit --skip in some git versions.
            while _gcp_scan_is_empty_cherry_pick; do
                if type ux_warning >/dev/null 2>&1; then
                    ux_warning "Empty commit at $sha; skipping..."
                fi
                if git cherry-pick --skip; then
                    empty_skipped=$((empty_skipped + 1))
                    break
                fi
                break
            done
            if ! git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1; then
                continue
            fi
            # Genuine conflict (the pre-flight already excluded redundant ones):
            # leave it in place with git's own conflict output for the user.
            if type ux_error >/dev/null 2>&1; then
                ux_error "Failed at $sha. Resolve and run: git cherry-pick --continue"
            fi
            return 1
        fi
    done <<EOF
$selected_list
EOF

    # Reaching here means no unresolved conflict (a real conflict returns 1
    # above), so report 0 conflicts.
    if type ux_success >/dev/null 2>&1; then
        ux_success "$picked applied, $dup_skipped skipped (dup), 0 conflicts"
        if [ "$noop_skipped" -gt 0 ]; then
            ux_info "($noop_skipped commit(s) skipped — already in HEAD, no-op pre-flight)"
        fi
        if [ "$empty_skipped" -gt 0 ]; then
            ux_info "($empty_skipped empty commit(s) also skipped)"
        fi
    else
        echo "✓ $picked applied, $dup_skipped skipped (dup), 0 conflicts"
        if [ "$noop_skipped" -gt 0 ]; then
            echo "  ($noop_skipped commit(s) skipped — already in HEAD, no-op pre-flight)"
        fi
        if [ "$empty_skipped" -gt 0 ]; then
            echo "  ($empty_skipped empty commit(s) also skipped)"
        fi
    fi

    # Restore tracing if it was enabled
    if [ $_xtrace_set -eq 1 ]; then
        set -x
    fi
}

# Note: 'gcp_scan' / 'gcp-scan' aliases live in gcp.sh and route through
# the dispatcher (issue #697). Do not add them here.
