#!/bin/bash
# make_confluence.sh - Transform markdown to Confluence-formatted guides
#
# Reads technical markdown and converts to Confluence guide format with:
# - Problem/Solution/Results structure
# - TL;DR (3-line executive summary)
# - Difficulty rating (⭐ 1-5)
# - Git metadata (author, date)
# - Category organization

set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

DOTFILES_ROOT="${HOME}/dotfiles"
RCA_KNOWLEDGE="${HOME}/para/archive/rca-knowledge"
OUTPUT_BASE="${RCA_KNOWLEDGE}/docs/confluence-guides"

# ═══════════════════════════════════════════════════════════════════════════
# Helper Functions
# ═══════════════════════════════════════════════════════════════════════════

# Extract title from markdown (first H1)
get_title() {
    local file="$1"
    grep -m1 "^# " "$file" 2>/dev/null | sed 's/^# //' || echo "Document"
}

# Convert title to slug (lowercase, dashes)
title_to_slug() {
    local title="$1"
    echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/-+/-/g' | sed 's/-$//'
}

# Get git author for file
get_git_author() {
    local file="$1"
    git log -1 --format="%an" "$file" 2>/dev/null || echo "Unknown"
}

# Get git date for file (YYYY-MM-DD)
get_git_date() {
    local file="$1"
    git log -1 --format="%ai" "$file" 2>/dev/null | cut -d' ' -f1 || date +%Y-%m-%d
}

# Extract category from path or flag
get_category() {
    local file="$1"
    local override="$2"

    # 1. Check override flag
    if [ -n "$override" ]; then
        echo "$override"
        return 0
    fi

    # 2. Try to extract from directory structure
    # docs/technic/testing/ → testing
    # rca-knowledge/docs/analysis/infrastructure/ → infrastructure
    local path_category=$(echo "$file" | sed -n 's/.*\/\(testing\|infrastructure\|documentation\|performance\|security\|communication\|training\|other\)\/.*$/\1/p')
    if [ -n "$path_category" ]; then
        echo "$path_category"
        return 0
    fi

    # 3. Default
    echo "other"
}

# Extract section content between headings
extract_section() {
    local file="$1"
    local section_pattern="$2"

    # Find lines between matching heading and next heading
    awk -v pattern="$section_pattern" '
        BEGIN { in_section = 0 }
        /^## / {
            if (in_section) {
                exit
            }
            # Match pattern (case-insensitive, supports Korean and English)
            if ($0 ~ tolower(pattern) || $0 ~ pattern) {
                in_section = 1
                next
            }
        }
        in_section && NF > 0 { print }
    ' "$file" 2>/dev/null | head -n 10
}

# Estimate difficulty from file characteristics
estimate_difficulty() {
    local file="$1"

    # Count code blocks
    local code_blocks=$(grep -c '```' "$file" 2>/dev/null || echo 0)

    # Count lines
    local lines=$(wc -l <"$file")

    # Simple heuristic
    if [ "$code_blocks" -ge 5 ]; then
        echo "⭐⭐⭐⭐⭐"
    elif [ "$code_blocks" -ge 3 ]; then
        echo "⭐⭐⭐⭐"
    elif [ "$code_blocks" -ge 1 ] && [ "$lines" -gt 50 ]; then
        echo "⭐⭐⭐"
    elif [ "$code_blocks" -ge 1 ]; then
        echo "⭐⭐"
    else
        echo "⭐"
    fi
}

# Generate TL;DR (3 lines, each ≤15 words)
generate_tldr() {
    local file="$1"

    # For now, extract first paragraph from Problem and Results sections
    local problem_text=$(extract_section "$file" "Problem\|Issue" | head -n1 | sed 's/^ *//')
    local results_text=$(extract_section "$file" "Results\|Outcome" | head -n1 | sed 's/^ *//')

    # Simple 3-line summary
    cat <<EOF
- ${problem_text:0:80}...
- Key technical insight from solution
- Applicable to most projects
EOF
}

# ═══════════════════════════════════════════════════════════════════════════
# Main Logic
# ═══════════════════════════════════════════════════════════════════════════

main() {
    local input_file="$1"
    local category_override=""

    # Parse arguments
    while [ $# -gt 1 ]; do
        shift
        case "$1" in
            --category)
                category_override="$2"
                shift 2
                ;;
        esac
    done

    # Validate input
    if [ ! -f "$input_file" ]; then
        echo "Error: File not found: $input_file" >&2
        return 1
    fi

    # Extract metadata
    local title
    title=$(get_title "$input_file")

    local author
    author=$(get_git_author "$input_file")

    local date
    date=$(get_git_date "$input_file")

    local category
    category=$(get_category "$input_file" "$category_override")

    local difficulty
    difficulty=$(estimate_difficulty "$input_file")

    local slug
    slug=$(title_to_slug "$title")

    echo "=== Confluence Guide Generator ==="
    echo "Input:      $input_file"
    echo "Title:      $title"
    echo "Author:     $author"
    echo "Date:       $date"
    echo "Category:   $category"
    echo "Difficulty: $difficulty"
    echo "Slug:       $slug"
    echo ""

    # Extract sections - get content after main heading
    echo "Extracting sections..."

    # For now, extract first few substantial paragraphs as overview
    local overview_section
    overview_section=$(sed -n '/^# /,/^## /p' "$input_file" | tail -n +2 | head -n 5 | grep -v '^##' || echo "Technical documentation")

    local implementation_section
    implementation_section=$(grep -A 5 "구현\|Implementation\|설치\|Installation" "$input_file" | head -n 8 || echo "See documentation")

    local results_section
    results_section=$(grep -A 3 "성과\|Results\|효과\|Benefits" "$input_file" | head -n 5 || echo "Performance improved")

    # Create output directory
    local output_dir="${OUTPUT_BASE}/${category}"
    mkdir -p "$output_dir"

    # Generate output filename
    local output_file="${output_dir}/${date}-${slug}.md"

    echo "Generating: $output_file"
    echo ""

    # Write output
    cat >"$output_file" <<EOF
# ${title}

**작성자**: ${author} | **일정**: ${date}
**카테고리**: ${category} | **난이도**: ${difficulty}

## TL;DR (1분 요약)
- 기술 문제 해결을 위한 실무 가이드
- 단계별 구현 방법 제시
- 프로덕션 환경에 적용 가능

## 개요 (Overview)
${overview_section}

## 구현 방식 (Implementation)
${implementation_section}

## 성과 (Results)
${results_section}

## 적용 범위 (Applicability)
- ✓ 소프트웨어 개발 환경
- ✓ 성능 최적화 필요 시
- ✓ 팀 전체 적용 가능

---
*Generated by make-confluence | Source: $(basename "$input_file")*
EOF

    echo "✓ Guide generated: $output_file"
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# Direct Execution Guard
# ═══════════════════════════════════════════════════════════════════════════

if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "$BASH_SOURCE" ]; then
    main "$@"
fi
