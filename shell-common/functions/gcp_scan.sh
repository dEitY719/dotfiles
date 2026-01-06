#!/bin/sh
# shell-common/functions/gcp_scan.sh
#
# Portable cherry-pick scanner - works in bash, zsh, and other POSIX shells
# Intelligently identifies and cherry-picks missing commits
#
# Usage:
#   gcp_scan [--author=<name|all>]         # defaults: main <- upstream/main, author=dEitY719
#   gcp_scan develop origin --author=all   # custom branches + show all commits
#
# Note: git cherry marks commits as:
#   '+' = present in source, missing in base (will be cherry-picked)
#   '-' = already merged in base
#

gcp_scan() {
    local base="main"
    local source="upstream/main"
    local author="dEitY719"
    local arg1="" arg2=""

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
    local duplicate_count=0

    while IFS= read -r sha; do
        [ -z "$sha" ] && continue
        local subject
        subject=$(git show -s --format='%s' "$sha")

        # Check if base branch has a commit with same subject (search recent 200 commits)
        if git log "$base" -n 200 --format='%s' 2>/dev/null | grep -Fqx "$subject"; then
            duplicate_list="${duplicate_list}${sha}"$'\n'
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

    # Calculate range (Oldest..Newest)
    local first_sha
    first_sha=$(echo "$selected_list" | head -n 1)
    local last_sha
    last_sha=$(echo "$selected_list" | tail -n 1)
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
        echo ""
        echo "=== Analysis Result ==="
        echo "  Missing (all authors): $total_count"
        echo "  Author filter: $author -> $count commit(s)"
        if [ $duplicate_count -gt 0 ]; then
            echo "  Duplicates (already applied): $duplicate_count"
        fi
        echo "  Suggested Range: $range_str"
        if [ $is_contiguous -eq 1 ]; then
            echo "✓ Range is contiguous (clean cherry-pick)."
        else
            echo "⚠ Range is NOT contiguous (contains $((range_count - count)) other commits in between)."
        fi
    fi

    # Display Commits
    echo ""
    if type ux_section >/dev/null 2>&1; then
        ux_section "Commit List"
    else
        echo "=== Commit List ==="
    fi
    echo "Commits to cherry-pick:"
    {
        local line_num=1
        echo "$selected_list" | while IFS= read -r sha; do
            [ -z "$sha" ] && continue
            local subject
            subject=$(git show -s --format='%s' "$sha")

            # Check if this is a duplicate
            local is_dup=0
            if git log "$base" -n 200 --format='%s' 2>/dev/null | grep -Fqx "$subject"; then
                is_dup=1
            fi

            local line
            line=$(git log --no-walk --format="%C(auto)%h %C(green)%ad %C(blue)%an%C(auto)%d %s" --date=short "$sha")

            if [ $is_dup -eq 1 ]; then
                echo "${line} [DUPLICATE - Already in $base]"
            else
                echo "$line"
            fi
        done | nl -w 2 -s '. '
    }

    echo ""
    # Interactive Confirmation
    if type ux_confirm >/dev/null 2>&1; then
        if ux_confirm "Do you want to cherry-pick these $count commits?" "n"; then
            echo ""
            if [ $is_contiguous -eq 1 ] && [ $duplicate_count -eq 0 ]; then
                if type ux_info >/dev/null 2>&1; then
                    ux_info "Executing: git cherry-pick $range_str"
                fi
                if git cherry-pick "$range_str"; then
                    if type ux_success >/dev/null 2>&1; then
                        ux_success "Cherry-pick complete!"
                    fi
                else
                    if type ux_error >/dev/null 2>&1; then
                        ux_error "Cherry-pick encountered conflicts. Resolve manually and run:"
                        ux_error "  git cherry-pick --continue"
                    fi
                    return 1
                fi
            else
                # Non-contiguous OR has duplicates: cherry-pick individually for better control
                if [ $duplicate_count -gt 0 ]; then
                    if type ux_warning >/dev/null 2>&1; then
                        ux_warning "Duplicates detected. Cherry-picking individually with auto-skip for duplicates..."
                    fi
                elif [ $is_contiguous -eq 0 ]; then
                    if type ux_warning >/dev/null 2>&1; then
                        ux_warning "Non-contiguous range detected. Cherry-picking individually..."
                    fi
                fi
                local picked=0
                local skipped=0
                echo "$selected_list" | while IFS= read -r sha; do
                    [ -z "$sha" ] && continue
                    local subject
                    subject=$(git show -s --format='%s' "$sha")

                    # Check if this commit is a duplicate (already in base)
                    local is_dup=0
                    if git log "$base" -n 200 --format='%s' 2>/dev/null | grep -Fqx "$subject"; then
                        is_dup=1
                    fi

                    if [ $is_dup -eq 1 ]; then
                        if type ux_warning >/dev/null 2>&1; then
                            ux_warning "Skipping $sha (already in $base)..."
                        fi
                        skipped=$((skipped + 1))
                    else
                        if type ux_info >/dev/null 2>&1; then
                            ux_info "Cherry-picking $sha..."
                        fi
                        if git cherry-pick "$sha"; then
                            picked=$((picked + 1))
                        else
                            if type ux_error >/dev/null 2>&1; then
                                ux_error "Failed at $sha. Resolve and run: git cherry-pick --continue"
                            fi
                            return 1
                        fi
                    fi
                done
                if type ux_success >/dev/null 2>&1; then
                    ux_success "Cherry-picked $picked/$count commits successfully! (Skipped $skipped duplicates)"
                fi
            fi
        else
            if type ux_info >/dev/null 2>&1; then
                ux_info "Cancelled. You can use the range above manually: git cherry-pick $range_str"
            fi
        fi
    fi
}

# Quick shorthand for gcp_scan
alias gcs='gcp_scan'

