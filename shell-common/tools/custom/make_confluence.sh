#!/bin/bash
# shell-common/tools/custom/make_confluence.sh
# Transform a technical markdown document into a Confluence-formatted guide.

# zsh-compat: this script uses bash-only [[ ]], `local`, and process
# substitution; drop into strict POSIX-sh emulation when sourced from zsh.
[ -n "${ZSH_VERSION-}" ] && emulate -L sh

set -euo pipefail

usage() {
    cat <<'EOF'
Transform a technical markdown document into a Confluence-formatted guide
with Problem / Solution / Results structure plus TL;DR and metadata.

Usage:
  make_confluence.sh [-h|--help|help] <input.md> [--category <name>]

Arguments:
  <input.md>             Source markdown file (required).

Options:
  -h, --help             Show this help and exit.
  --category <name>      Override the auto-detected category.

Output:
  ${RCA_KNOWLEDGE:-~/para/archive/playbook}/docs/confluence-guides/<cat>/<date>-<slug>.md
EOF
}

# Initialize common tools environment (ux_lib + have_command)
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/init.sh" || exit 1

# ═══════════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════════

DOTFILES_ROOT="${HOME}/dotfiles"
RCA_KNOWLEDGE="${HOME}/para/archive/playbook"
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

    if [ -n "$override" ]; then
        echo "$override"
        return 0
    fi

    local path_category
    path_category=$(echo "$file" | sed -n 's/.*\/\(testing\|infrastructure\|documentation\|performance\|security\|communication\|training\|other\)\/.*$/\1/p')
    if [ -n "$path_category" ]; then
        echo "$path_category"
        return 0
    fi

    echo "other"
}

# Extract section content between headings
extract_section() {
    local file="$1"
    local section_pattern="$2"

    awk -v pattern="$section_pattern" '
        BEGIN { in_section = 0 }
        /^## / {
            if (in_section) {
                exit
            }
            if ($0 ~ tolower(pattern) || $0 ~ pattern) {
                in_section = 1
                next
            }
        }
        in_section && NF > 0 { print }
    ' "$file" 2>/dev/null | head -n 10
}

# Estimate difficulty from file characteristics.
# Output stars are embedded in the generated markdown (user-facing content),
# not in the script's own UX output — exempt from the no-emoji rule.
estimate_difficulty() {
    local file="$1"
    local code_blocks
    code_blocks=$(grep -c '```' "$file" 2>/dev/null || echo 0)
    local lines
    lines=$(wc -l <"$file")

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

# ═══════════════════════════════════════════════════════════════════════════
# Main Logic
# ═══════════════════════════════════════════════════════════════════════════

main() {
    case "${1:-}" in
        -h|--help|help) usage; exit 0 ;;
        "") ux_error "Missing argument: <input.md>"; usage >&2; exit 2 ;;
    esac

    local input_file="$1"
    shift
    local category_override=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --category)
                if [ -z "${2:-}" ]; then
                    ux_error "--category requires an argument"
                    usage >&2
                    exit 2
                fi
                category_override="$2"
                shift 2
                ;;
            *)
                ux_error "Unknown argument: $1"
                usage >&2
                exit 2
                ;;
        esac
    done

    if [ ! -f "$input_file" ]; then
        ux_error "File not found: $input_file"
        return 1
    fi

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

    ux_header "Confluence Guide Generator"
    ux_bullet "Input:      $input_file"
    ux_bullet "Title:      $title"
    ux_bullet "Author:     $author"
    ux_bullet "Date:       $date"
    ux_bullet "Category:   $category"
    ux_bullet "Difficulty: $difficulty"
    ux_bullet "Slug:       $slug"

    ux_info "Extracting sections..."

    local overview_section
    overview_section=$(sed -n '/^# /,/^## /p' "$input_file" | tail -n +2 | head -n 5 | grep -v '^##' || echo "Technical documentation")

    local implementation_section
    implementation_section=$(grep -A 5 "구현\|Implementation\|설치\|Installation" "$input_file" | head -n 8 || echo "See documentation")

    local results_section
    results_section=$(grep -A 3 "성과\|Results\|효과\|Benefits" "$input_file" | head -n 5 || echo "Performance improved")

    local output_dir="${OUTPUT_BASE}/${category}"
    mkdir -p "$output_dir"

    local output_file="${output_dir}/${date}-${slug}.md"
    ux_info "Generating: $output_file"

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
- [x] 소프트웨어 개발 환경
- [x] 성능 최적화 필요 시
- [x] 팀 전체 적용 가능

---
*Generated by make-confluence | Source: $(basename "$input_file")*
EOF

    ux_section "Summary"
    ux_bullet "state: ok"
    ux_bullet "output: $output_file"
    ux_success "Guide generated"
    ux_info "Next: cat \"$output_file\""
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# Direct Execution Guard
# ═══════════════════════════════════════════════════════════════════════════

if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
