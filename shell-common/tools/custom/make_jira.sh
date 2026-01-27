#!/bin/bash
# make_jira.sh - Generate weekly Jira reports from work logs
#
# Simple version handling both:
# - post-commit: [date time] [KEY] | main | hours | source (+ category on next line)
# - work-log CLI: [date time] [KEY] | type | category | hours | source

# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

WORK_LOG_FILE="${HOME}/work_log.txt"
if [ -f "${HOME}/dotfiles/shell-common/data/work_log.txt" ]; then
    WORK_LOG_FILE="${HOME}/dotfiles/shell-common/data/work_log.txt"
fi

OUTPUT_DIR="${HOME}/para/archive/rca-knowledge/docs/jira-records"

# ═══════════════════════════════════════════════════════════════════════════
# Main Logic
# ═══════════════════════════════════════════════════════════════════════════

main() {
    local target_week="${1:-current}"
    local target_key="${2:-}"

    # Get week range
    local week_start week_end
    if [ "$target_week" = "current" ]; then
        # Calculate current week (Mon-Sun)
        local today
        today=$(date +%Y-%m-%d)
        local dow
        dow=$(date +%u)  # 1=Mon, 7=Sun

        week_start=$(date -d "$today -$((dow-1)) days" +%Y-%m-%d)
        week_end=$(date -d "$today +$((7-dow)) days" +%Y-%m-%d)
        target_week=$(date -d "$today" +%G-W%V)
    else
        # Parse YYYY-W## format
        local year="${target_week:0:4}"
        local week="${target_week:6:2}"

        # Simple calculation: Jan 4 is always in week 1
        local jan4="$year-01-04"
        local day_of_week
        day_of_week=$(date -d "$jan4" +%u)

        # Monday of week 1
        local week1_mon=$(date -d "$jan4 -$((day_of_week-1)) days" +%Y-%m-%d)

        # Monday of target week
        week_start=$(date -d "$week1_mon +$((week-1)) weeks" +%Y-%m-%d)
        week_end=$(date -d "$week_start +6 days" +%Y-%m-%d)
    fi

    echo "=== Jira Report: $target_week ($week_start ~ $week_end) ==="
    echo ""

    if [ ! -f "$WORK_LOG_FILE" ]; then
        echo "Error: work_log.txt not found" >&2
        return 1
    fi

    # Parse work log entries
    local entry_count=0
    local total_hours=0
    declare -A entries  # key -> "hours|categories"

    # Read file line by line
    local prev_date prev_key prev_hours prev_cat

    while IFS= read -r line; do
        # Skip empty lines and category-only lines
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue

        # Handle category line (starts with spaces, contains "Category:")
        if [[ "$line" =~ Category:\ ([A-Za-z]+) ]] && [[ "$line" =~ ^[[:space:]] ]]; then
            local cat="${BASH_REMATCH[1]}"
            [ -n "$prev_key" ] && prev_cat="$cat"
            continue
        fi

        # Skip lines starting with spaces (other than category)
        [[ "$line" =~ ^[[:space:]] ]] && continue

        # Entry line: [YYYY-MM-DD HH:MM:SS] [KEY] | ...
        if [[ "$line" =~ ^\[([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
            local date="${BASH_REMATCH[1]}"

            # Check if date is in range
            if [[ "$date" < "$week_start" ]] || [[ "$date" > "$week_end" ]]; then
                continue
            fi

            # Parse Jira key
            if [[ "$line" =~ \[([A-Z][A-Z0-9]*-[0-9]+)\] ]]; then
                local key="${BASH_REMATCH[1]}"

                # Filter by target key if specified
                if [ -n "$target_key" ] && [ "$key" != "$target_key" ]; then
                    continue
                fi

                # Parse hours
                local hours=0
                if [[ "$line" =~ \|\ ([0-9]+\.?[0-9]*)h? ]]; then
                    hours="${BASH_REMATCH[1]}"
                fi

                # Ensure prev_cat has value
                [ -z "$prev_cat" ] && prev_cat="(auto)"

                # Add to entries
                if [ -z "${entries[$key]:-}" ]; then
                    entries[$key]="${hours}|${prev_cat}"
                else
                    local old="${entries[$key]}"
                    local old_h="${old%%|*}"
                    local old_c="${old##*|}"
                    entries[$key]="$((${old_h%.*} + ${hours%.*}))|${old_c},${prev_cat}"
                fi

                total_hours=$((${total_hours%.*} + ${hours%.*}))
                ((entry_count++))
                prev_cat=""
            fi
        fi
    done < "$WORK_LOG_FILE"

    # Report
    if [ $entry_count -eq 0 ]; then
        echo "No entries found for $target_week"
        return 0
    fi

    echo "Found: $entry_count entries, ${total_hours}h"
    echo ""

    # Create output
    mkdir -p "$OUTPUT_DIR"
    local report_file="${OUTPUT_DIR}/${target_week}-report.md"

    {
        echo "# [주간보고] $target_week ($week_start ~ $week_end)"
        echo ""
        echo "## 요약"
        echo "- 총 처리: $entry_count entries"
        echo "- 총 시간: ${total_hours}h"
        echo "- Jira 태스크: ${#entries[@]}개"
        echo ""
        echo "## 완료 (Done)"
        for key in $(printf '%s\n' "${!entries[@]}" 2>/dev/null | sort); do
            local data="${entries[$key]}"
            local h="${data%%|*}"
            local c="${data##*|}"
            echo "- **$key**: ${h}h (${c})"
        done
        echo ""
        echo "## Work Log 요약"
        for key in $(printf '%s\n' "${!entries[@]}" 2>/dev/null | sort); do
            local h="${entries[$key]%%|*}"
            echo "- $key: ${h}h"
        done
        echo ""
        echo "**총 투입**: ${total_hours}h"
        echo "**생성**: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "---"
        echo "*Generated by make-jira*"
    } > "$report_file"

    echo "✓ Report saved: $report_file"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# Direct Execution Guard
# ═══════════════════════════════════════════════════════════════════════════

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
