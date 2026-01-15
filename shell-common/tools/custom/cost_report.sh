#!/bin/bash

# shell-common/tools/custom/cost_report.sh
# Anthropic Organization Cost Report API
# Displays USD-based cost analysis by model

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Configuration & Validation
# ═══════════════════════════════════════════════════════════════

ADMIN_API_KEY="${ANTHROPIC_ADMIN_API_KEY:-}"

# ANSI Color codes
HEADER='\033[1;36m'      # Cyan Bold
SUCCESS='\033[32m'       # Green
ERROR='\033[31m'         # Red
INFO='\033[36m'          # Cyan
DOLLAR='\033[1;32m'      # Bold Green (for currency)
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

print_cost() {
    echo -ne "${DOLLAR}\$$1${RESET}"
}

# ═══════════════════════════════════════════════════════════════
# Validation
# ═══════════════════════════════════════════════════════════════

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

fetch_cost_report() {
    local start_date="${1:-$(date -d 'yesterday' +%Y-%m-%d)}"
    local end_date="${2:-$(date -d 'today' +%Y-%m-%d)}"

    print_header "Organization Cost Report"
    print_info "Period: $start_date to $end_date"
    print_info "Endpoint: https://api.anthropic.com/v1/organizations/cost_report"
    echo ""

    # Construct request payload
    local payload=$(cat <<EOF
{
  "start_date": "$start_date",
  "end_date": "$end_date"
}
EOF
)

    print_info "Fetching cost data from API..."
    echo ""

    # Make API request
    local response
    response=$(curl -s -X POST \
        "https://api.anthropic.com/v1/organizations/cost_report" \
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
    display_cost_data "$response"
}

display_cost_data() {
    local response="$1"

    # Extract data array
    local data=$(echo "$response" | jq '.data // []')

    if [[ $(echo "$data" | jq 'length') -eq 0 ]]; then
        print_info "No cost data available for the specified period"
        return 0
    fi

    print_success "Cost data retrieved successfully"
    echo ""

    # Display breakdown by model
    echo -e "${INFO}💰 Cost Breakdown by Model${RESET}"
    echo "─────────────────────────────────────────────────────────────────────────────────────"
    printf "%-45s %12s %12s %12s\n" "Model" "Input $" "Output $" "Total $"
    echo "─────────────────────────────────────────────────────────────────────────────────────"

    # Process each data point
    echo "$data" | jq -r '.[] | [
        .model,
        (.input_cost // "0"),
        (.output_cost // "0"),
        ((.input_cost // "0" | tonumber) + (.output_cost // "0" | tonumber))
    ] | @tsv' | while IFS=$'\t' read -r model input_cost output_cost total_cost; do
        # Parse model name (extract version)
        local model_name=$(echo "$model" | sed 's/.*claude-//' | sed 's/-20[0-9]*//')

        printf "%-45s %12.4f %12.4f %12.4f\n" \
            "$model_name" \
            "$(printf '%.4f' "$input_cost")" \
            "$(printf '%.4f' "$output_cost")" \
            "$(printf '%.4f' "$total_cost")"
    done

    echo "─────────────────────────────────────────────────────────────────────────────────────"
    echo ""

    # Display aggregated totals
    display_totals "$data"
}

display_totals() {
    local data="$1"

    local total_input_cost=$(echo "$data" | jq '[.[].input_cost // 0 | tonumber] | add' 2>/dev/null || echo 0)
    local total_output_cost=$(echo "$data" | jq '[.[].output_cost // 0 | tonumber] | add' 2>/dev/null || echo 0)
    local total_cost=$(echo "$total_input_cost + $total_output_cost" | bc -l 2>/dev/null || echo 0)

    local total_input_tokens=$(echo "$data" | jq '[.[].input_tokens // 0] | add' 2>/dev/null || echo 0)
    local total_output_tokens=$(echo "$data" | jq '[.[].output_tokens // 0] | add' 2>/dev/null || echo 0)

    echo -e "${INFO}📈 Cost Summary${RESET}"
    echo "─────────────────────────────────────────────────────────────────────────────────────"
    echo -ne "  Input Cost:                      "
    print_cost "$(printf '%.4f' "$total_input_cost")"
    echo ""
    echo -ne "  Output Cost:                     "
    print_cost "$(printf '%.4f' "$total_output_cost")"
    echo ""
    echo "─────────────────────────────────────────────────────────────────────────────────────"
    echo -ne "  Total Cost:                      "
    print_cost "$(printf '%.4f' "$total_cost")"
    echo ""
    echo "─────────────────────────────────────────────────────────────────────────────────────"
    echo ""

    echo -e "${INFO}📊 Token Metrics${RESET}"
    echo "─────────────────────────────────────────────────────────────────────────────────────"
    printf "  Total Input Tokens:              %20d\n" "$total_input_tokens"
    printf "  Total Output Tokens:             %20d\n" "$total_output_tokens"
    printf "  Combined Tokens:                 %20d\n" "$((total_input_tokens + total_output_tokens))"
    echo "─────────────────────────────────────────────────────────────────────────────────────"
}

# ═══════════════════════════════════════════════════════════════
# Main Entry Point
# ═══════════════════════════════════════════════════════════════

main() {
    validate_env || return 1

    # Parse arguments
    local start_date="${1:-$(date -d 'yesterday' +%Y-%m-%d)}"
    local end_date="${2:-$(date -d 'today' +%Y-%m-%d)}"

    fetch_cost_report "$start_date" "$end_date"
}

main "$@"
