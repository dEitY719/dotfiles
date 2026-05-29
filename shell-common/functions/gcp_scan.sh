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

_gcp_scan_dup_base_sha() {
    # Look up the base-branch SHA that a duplicate source SHA matches.
    # $1 = candidate source SHA; $2 = duplicate map ("SRC_SHA BASE_SHA" lines).
    # Prints the matching base SHA (or nothing) — issue #811 F-3.
    printf '%s\n' "$2" | awk -v s="$1" '$1 == s { print $2; exit }'
}

_gcp_scan() {
    # zsh compatibility: emulate POSIX sh to ensure consistent behavior
    if [ -n "${ZSH_VERSION-}" ]; then
        emulate -L sh
    fi

    # zsh/bash compatibility: disable debug tracing
    local _xtrace_set=0
    case $- in *x*) _xtrace_set=1; esac
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

    # Check for duplicate commits (same subject already in base branch)
    local final_selected_list=""
    local duplicate_list=""
    local duplicate_map=""
    local duplicate_count=0

    while IFS= read -r sha; do
        [ -z "$sha" ] && continue
        local subject
        subject=$(git show -s --format='%s' "$sha")

        # Check if base branch has a commit with same subject (search recent
        # 200 commits). Capture the matching base SHA so the individual
        # cherry-pick loop can report what each dup was already applied as
        # (issue #811 F-1/F-3). Exact subject match preserved via tab split.
        local match_base_sha
        match_base_sha=$(git log "$base" -n 200 --format='%H%x09%s' 2>/dev/null \
            | while IFS="$(printf '\t')" read -r _b_sha _b_subj; do
                if [ "$_b_subj" = "$subject" ]; then
                    printf '%s\n' "$_b_sha"
                    break
                fi
            done)
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

    # Calculate range (Oldest..Newest) from non-duplicate commits only
    local first_sha
    first_sha=$(echo "$final_selected_list" | head -n 1)
    local last_sha
    last_sha=$(echo "$final_selected_list" | tail -n 1)
    local range_str="${first_sha}^..${last_sha}"

    # Verify contiguity
    local range_count
    range_count=$(git rev-list --count "$range_str")
    local is_contiguous=0
    if [ "$range_count" -eq "$count" ]; then
        is_contiguous=1
    fi

    # Display Summary
    if type ux_section >/dev/null 2>&1; then
        ux_section "Analysis Result"
        ux_bullet "Missing (all authors): $total_count"
        ux_bullet "Author filter: $author -> $count commit(s)"
        if [ $duplicate_count -gt 0 ]; then
            ux_bullet "Duplicates (already applied): $duplicate_count"
        fi
        ux_bullet "Suggested Range: $range_str"
        if [ $is_contiguous -eq 1 ]; then
            ux_success "Range is contiguous (clean cherry-pick)."
        else
            ux_warning "Range is NOT contiguous (contains $((range_count - count)) other commits in between)."
        fi
    else

        echo "=== Analysis Result ==="
        ux_bullet "Missing (all authors): $total_count"
        ux_bullet "Author filter: $author -> $count commit(s)"
        if [ $duplicate_count -gt 0 ]; then
            ux_bullet "Duplicates (already applied): $duplicate_count"
        fi
        ux_bullet "Suggested Range: $range_str"
        if [ $is_contiguous -eq 1 ]; then
            echo "✓ Range is contiguous (clean cherry-pick)."
        else
            echo "⚠ Range is NOT contiguous (contains $((range_count - count)) other commits in between)."
        fi
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
    if type ux_confirm >/dev/null 2>&1; then
        if ux_confirm "Do you want to cherry-pick these $count commits?" "n"; then

            if [ $is_contiguous -eq 1 ]; then
                if type ux_info >/dev/null 2>&1; then
                    ux_info "Executing: git cherry-pick $range_str"
                fi
                if git cherry-pick "$range_str"; then
                    if type ux_success >/dev/null 2>&1; then
                        ux_success "Cherry-pick complete!"
                    fi
                else
                    # Some environments treat an empty pick as an error (exit 1) and require --skip.
                    # Auto-skip empty commits when there are no conflicts.
                    while _gcp_scan_is_empty_cherry_pick; do
                        if type ux_warning >/dev/null 2>&1; then
                            ux_warning "Empty commit encountered during cherry-pick sequence; skipping..."
                        fi
                        if ! git cherry-pick --skip; then
                            break
                        fi
                    done
                    if ! git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1; then
                        if type ux_success >/dev/null 2>&1; then
                            ux_success "Cherry-pick complete! (Skipped empty commit(s))"
                        fi
                        return 0
                    fi
                    if type ux_error >/dev/null 2>&1; then
                        ux_error "Cherry-pick encountered conflicts. Resolve manually and run:"
                        ux_error "  git cherry-pick --continue"
                    fi
                    return 1
                fi
            else
                # Non-contiguous: cherry-pick individually for better control.
                # Iterate the full author-filtered list (selected_list) — not
                # the dup-pruned final_selected_list — so dup commits detected
                # in Stage-1 are explicitly skipped *with a log line* instead
                # of being silently dropped (issue #811 F-1/F-2).
                if type ux_warning >/dev/null 2>&1; then
                    ux_warning "Non-contiguous range detected. Cherry-picking individually..."
                fi
                local picked=0
                local empty_skipped=0
                local dup_skipped=0
                while IFS= read -r sha; do
                    [ -z "$sha" ] && continue
                    # F-2/F-3: a Stage-1 duplicate is skipped without a
                    # cherry-pick attempt, naming the base SHA it matches.
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
                    if type ux_info >/dev/null 2>&1; then
                        ux_info "Cherry-picking $sha..."
                    fi
                    if git cherry-pick "$sha"; then
                        picked=$((picked + 1))
                    else
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
                        # If we successfully skipped, move on.
                        if ! git rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1; then
                            continue
                        fi
                        if type ux_error >/dev/null 2>&1; then
                            ux_error "Failed at $sha. Resolve and run: git cherry-pick --continue"
                        fi
                        return 1
                    fi
                done <<EOF
$selected_list
EOF
                # F-4: reaching here means no unresolved conflict (a real
                # conflict returns 1 above), so report 0 conflicts.
                if type ux_success >/dev/null 2>&1; then
                    ux_success "$picked applied, $dup_skipped skipped (dup), 0 conflicts"
                    if [ "$empty_skipped" -gt 0 ]; then
                        ux_info "($empty_skipped empty commit(s) also skipped)"
                    fi
                else
                    echo "✓ $picked applied, $dup_skipped skipped (dup), 0 conflicts"
                    if [ "$empty_skipped" -gt 0 ]; then
                        echo "  ($empty_skipped empty commit(s) also skipped)"
                    fi
                fi
            fi
        else
            if type ux_info >/dev/null 2>&1; then
                ux_info "Cancelled. You can use the range above manually: git cherry-pick $range_str"
            fi
        fi
    fi

    # Restore tracing if it was enabled
    if [ $_xtrace_set -eq 1 ]; then
        set -x
    fi
}

# Note: 'gcp_scan' / 'gcp-scan' aliases live in gcp.sh and route through
# the dispatcher (issue #697). Do not add them here.
