#!/bin/bash

# shell-common/tools/custom/usage_report.sh
# Anthropic Organization Usage Report API
# Displays token usage data for organization by model

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Configuration & Validation
# ═══════════════════════════════════════════════════════════════

ADMIN_API_KEY="${ANTHROPIC_ADMIN_API_KEY:-}"

# ANSI Color codes
HEADER='\033[1;36m'      # Cyan Bold
SUCCESS='\033[32m'       # Green
WARNING='\033[33m'       # Orange
ERROR='\033[31m'         # Red
INFO='\033[36m'          # Cyan
RESET='\033[0m'          # Reset

# ═══════════════════════════════════════════════════════════════
# Helper Functions
# ═══════════════════════════════════════════════════════════════

print_header() {
    echo -e "${HEADER}▶ $1${RESET}"
}

print_error() {
    echo -e "${ERROR}✗ Error: $1${RESET}" >&2
}

print_success() {
    echo -e "${SUCCESS}✓ $1${RESET}"
}

print_info() {
    echo -e "${INFO}ℹ $1${RESET}"
}

validate_env() {
    if [[ -z "$ADMIN_API_KEY" ]]; then
        print_error "ANTHROPIC_ADMIN_API_KEY environment variable not set"
        echo "Export your Admin API key:"
        echo "  export ANTHROPIC_ADMIN_API_KEY=\"sk-ant-admin-...\""
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Main API Call & Processing
# ═══════════════════════════════════════════════════════════════

fetch_usage_report() {
    local start_date="${1:-$(date -d 'today' +%Y-%m-%d)}"
    local end_date="${2:-$(date -d 'today' +%Y-%m-%d)}"
    local group_by="${3:-model}"

    print_header "Organization Usage Report"
    print_info "Period: $start_date to $end_date"
    print_info "Endpoint: https://api.anthropic.com/v1/organizations/usage_report/messages"
    echo ""

    # Construct request payload
    local payload=$(cat <<EOF
{
  "start_date": "$start_date",
  "end_date": "$end_date",
  "group_by": ["$group_by"]
}
EOF
)

    print_info "Fetching data from API..."
    echo ""

    # Make API request
    local response
    response=$(curl -s -X POST \
        "https://api.anthropic.com/v1/organizations/usage_report/messages" \
        -H "x-api-key: ${ADMIN_API_KEY}" \
        -H "anthropic-version: 2023-06-01" \
        -H "Content-Type: application/json" \
        -d "$payload")

    # Check for errors
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        local error_msg=$(echo "$response" | jq -r '.error.message // .error // "Unknown error"')
        print_error "API Error: $error_msg"
        echo "Response: $response" >&2
        return 1
    fi

    # Check if we got data
    if ! echo "$response" | jq -e '.data' >/dev/null 2>&1; then
        print_error "No data field in response"
        echo "Response: $response" >&2
        return 1
    fi

    # Process and display response
    display_usage_data "$response"
}

display_usage_data() {
    local response="$1"

    # Extract data array
    local data=$(echo "$response" | jq '.data // []')

    if [[ $(echo "$data" | jq 'length') -eq 0 ]]; then
        print_info "No usage data available for the specified period"
        return 0
    fi

    print_success "Data retrieved successfully"
    echo ""

    # Display in table format
    echo -e "${INFO}📊 Token Usage Summary${RESET}"
    echo "─────────────────────────────────────────────────────────────────────────────────────"
    printf "%-45s %12s %12s %12s %12s\n" "Model" "Input" "Output" "Cached" "Cache-In"
    echo "─────────────────────────────────────────────────────────────────────────────────────"

    # Process each data point
    echo "$data" | jq -r '.[] | [
        .model,
        (.input_tokens // 0),
        (.output_tokens // 0),
        (.cached_input_tokens // 0),
        (.cache_creation_input_tokens // 0)
    ] | @tsv' | while IFS=$'\t' read -r model input output cached cache_in; do
        # Parse model name (extract version)
        local model_name=$(echo "$model" | sed 's/.*claude-//' | sed 's/-20[0-9]*//')

        printf "%-45s %12d %12d %12d %12d\n" \
            "$model_name" \
            "$(printf '%d' "$input")" \
            "$(printf '%d' "$output")" \
            "$(printf '%d' "$cached")" \
            "$(printf '%d' "$cache_in")"
    done

    echo "─────────────────────────────────────────────────────────────────────────────────────"
    echo ""

    # Display aggregated totals
    display_totals "$data"
}

display_totals() {
    local data="$1"

    local total_input=$(echo "$data" | jq '[.[].input_tokens // 0] | add' 2>/dev/null || echo 0)
    local total_output=$(echo "$data" | jq '[.[].output_tokens // 0] | add' 2>/dev/null || echo 0)
    local total_cached=$(echo "$data" | jq '[.[].cached_input_tokens // 0] | add' 2>/dev/null || echo 0)
    local total_cache_in=$(echo "$data" | jq '[.[].cache_creation_input_tokens // 0] | add' 2>/dev/null || echo 0)

    echo -e "${INFO}📈 Aggregated Totals${RESET}"
    echo "─────────────────────────────────────────────────────────────────────────────────────"
    printf "  Input Tokens:                    %20d\n" "$total_input"
    printf "  Output Tokens:                   %20d\n" "$total_output"
    printf "  Cached Input Tokens:             %20d\n" "$total_cached"
    printf "  Cache Creation Tokens:           %20d\n" "$total_cache_in"
    echo "─────────────────────────────────────────────────────────────────────────────────────"
    echo ""

    local total_billable=$(( total_input + total_output + total_cache_in ))
    echo -e "${INFO}💰 Billing Summary${RESET}"
    echo "─────────────────────────────────────────────────────────────────────────────────────"
    printf "  Total Billable Tokens:           %20d\n" "$total_billable"

    # Cache efficiency
    if [[ $total_input -gt 0 ]]; then
        local cache_ratio=$(( total_cached * 100 / total_input ))
        printf "  Cache Hit Ratio:                 %19d%%\n" "$cache_ratio"
    fi
    echo "─────────────────────────────────────────────────────────────────────────────────────"
}

# ═══════════════════════════════════════════════════════════════
# Main Entry Point
# ═══════════════════════════════════════════════════════════════

main() {
    validate_env || return 1

    # Parse arguments
    local start_date="${1:-$(date -d 'today' +%Y-%m-%d)}"
    local end_date="${2:-$(date -d 'today' +%Y-%m-%d)}"
    local group_by="${3:-model}"

    fetch_usage_report "$start_date" "$end_date" "$group_by"
}

main "$@"
