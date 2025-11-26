#!/usr/bin/env bash
set -euo pipefail

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

TARGET_DIR=${1:-.}
if [[ ! -d $TARGET_DIR ]]; then
    echo "error: '${TARGET_DIR}' is not a directory" >&2
    exit 1
fi

TARGET_DIR=$(realpath "$TARGET_DIR")

if ! git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "error: '${TARGET_DIR}' is not inside a git repository" >&2
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

duration_label=$(printf '%02d days' "$duration_days")

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
        loc=$(cd "$TARGET_DIR" && git ls-files -z --cached --others --exclude-standard -- "*.${ext}" | (grep -z -vE "(^|/)\.venv/" || true) | xargs -0 cat | wc -l)
    fi

    counts[$ext]=$count
    locs[$ext]=$loc
    total_files=$((total_files + count))
    total_loc=$((total_loc + loc))
done

printf 'total git commit: %s | %s ~ %s (%s) | %s commits per day\n' \
    "${git_commits}" "$start_date" "$end_date" "$duration_label" "$avg_commits_per_day"
printf 'total files: %s (LOC: %s)\n' "$(format_number "$total_files")" "$(format_number "$total_loc")"
for ext in "${exts[@]}"; do
    printf '  .%s: %s (LOC: %s)\n' "$ext" "$(format_number "${counts[$ext]}")" "$(format_number "${locs[$ext]}")"
done
