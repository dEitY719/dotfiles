#!/bin/bash
set -euo pipefail

# Initialize common tools environment
# This assumes the script is run from the dotfiles repo, or ux_lib is in a known path.
# For portability, let's determine the script's own directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load initialization (which includes UX library)
source "$(dirname "$0")/init.sh" || exit 1

format_number() {
    local num=$1
    local sign=""
    if [[ $num == -* ]]; then
        sign="-"
        num=${num#-}
    fi
    local formatted=""
    while [[ ${#num} -gt 3 ]]; do
        local chunk=${num: -3}
        formatted=",${chunk}${formatted}"
        num=${num:0:-3}
    done
    formatted="${num}${formatted}"
    printf '%s%s' "$sign" "$formatted"
}

main() {
TARGET_DIR=${1:-.}
if [[ ! -d $TARGET_DIR ]]; then
    ux_error "'${TARGET_DIR}' is not a directory" >&2
    exit 1
fi

TARGET_DIR=$(realpath "$TARGET_DIR")

if ! git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ux_error "'${TARGET_DIR}' is not a git repository" >&2
    exit 1
fi

git_commits=$(git -C "$TARGET_DIR" rev-list --count HEAD)

start_date="-"
end_date="-"
duration_days=0
avg_commits_per_day="0.00"

if (( git_commits > 0 )); then
    start_commit=$(git -C "$TARGET_DIR" rev-list HEAD | tail -n 1)
    start_date=$(git -C "$TARGET_DIR" show -s --format=%cs "$start_commit")
    end_date=$(git -C "$TARGET_DIR" log -1 --format=%cs)
    if [[ -n $start_date && -n $end_date ]]; then
        start_epoch=$(date -d "$start_date" +%s)
        end_epoch=$(date -d "$end_date" +%s)
        if (( end_epoch >= start_epoch )); then
            duration_days=$(( (end_epoch - start_epoch) / 86400 ))
        fi
        days_for_avg=$duration_days
        if (( days_for_avg < 1 )); then
            days_for_avg=1
        fi
        avg_commits_per_day=$(awk -v commits="$git_commits" -v days="$days_for_avg" 'BEGIN { printf "%.2f", commits / days }')
    fi
fi

declare -a exts=(py js css tsx)
declare -A counts
declare -A locs

total_files=0
total_loc=0

for ext in "${exts[@]}"; do
    # Use git ls-files to respect .gitignore
    # Explicitly filter out .venv directory (anchored at start or inside path)
    # ( ... || true ) is needed because grep exits with 1 if no lines match, which triggers set -e with pipefail
    count=$(git -C "$TARGET_DIR" ls-files --cached --others --exclude-standard -- "*.${ext}" | (grep -vE "(^|/)\.venv/" || true) | wc -l)
    
    loc=0
    if (( count > 0 )); then
        # Calculate LOC using -z for safety with special characters
        # grep -z filters null-terminated stream
        loc=$(cd "$TARGET_DIR" && git ls-files -z --cached --others --exclude-standard -- "*.${ext}" | (grep -z -vE "(^|/)\.venv/" || true) | xargs -0 cat 2>/dev/null | wc -l)
    fi

    counts[$ext]=$count
    locs[$ext]=$loc
    total_files=$((total_files + count))
    total_loc=$((total_loc + loc))
done

# Test Statistics (Heuristic: count 'def test_' in python test files)
test_count=0
# check if any python files exist first to avoid unnecessary work
if [[ ${counts[py]} -gt 0 ]]; then
    test_count=$(cd "$TARGET_DIR" && git ls-files -z --cached --others --exclude-standard -- "*.py" \
        | (grep -z -vE "(^|/)\.venv/" || true) \
        | (grep -z -E "test_.*\.py$|.*_test\.py$" || true) \
        | (xargs -0 grep -h "def test_" 2>/dev/null || true) \
        | wc -l)
fi


# --- Display ---
clear
ux_header "Repository Statistics: $(basename "$TARGET_DIR")"

# Git Commit Statistics
ux_section "Git Commit Statistics"
ux_table_row "Total Commits" "$(format_number "$git_commits")"
ux_table_row "Project Period" "${start_date} ~ ${end_date} (${duration_days} days)"
ux_table_row "Commit Rate" "${avg_commits_per_day} commits/day"

# Test Statistics
if (( test_count > 0 )); then
    ux_section "Test Statistics"
    ux_table_row "Estimated Tests" "$(format_number "$test_count")"
fi

# File Statistics
ux_section "File & Code Statistics"
ux_table_row "${UX_BOLD}Total Files${UX_RESET}" "$(format_number "$total_files")"
ux_table_row "${UX_BOLD}Total LOC${UX_RESET}" "$(format_number "$total_loc")"
echo ""
ux_table_header "Extension" "Files" "Lines of Code"
for ext in "${exts[@]}"; do
    count=${counts[$ext]}
    loc=${locs[$ext]}
    if (( count > 0 )); then
        ux_table_row ".${ext}" "$(format_number "$count")" "$(format_number "$loc")"
    fi
done
echo ""
}

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
