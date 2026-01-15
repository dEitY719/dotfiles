#!/bin/bash
# shell-common/functions/org_reports.sh
# Anthropic Organization Usage & Cost Report Functions

# ═══════════════════════════════════════════════════════════════
# Organization Usage Report Function
# ═══════════════════════════════════════════════════════════════

usage_report() {
    local start_date="${1:---help}"

    if [[ "$start_date" == "--help" ]] || [[ "$start_date" == "-h" ]]; then
        echo ""
        echo "📊 Organization Usage Report"
        echo ""
        echo "Usage:"
        echo "  usage_report [START_DATE] [END_DATE] [GROUP_BY]"
        echo ""
        echo "Arguments:"
        echo "  START_DATE : Start date (YYYY-MM-DD), default: today"
        echo "  END_DATE   : End date (YYYY-MM-DD), default: today"
        echo "  GROUP_BY   : Group by field (model, api_key, etc), default: model"
        echo ""
        echo "Requirements:"
        echo "  • Export ANTHROPIC_ADMIN_API_KEY environment variable"
        echo ""
        echo "Setup:"
        echo "  export ANTHROPIC_ADMIN_API_KEY=\"sk-ant-admin-...\""
        echo ""
        echo "Examples:"
        echo "  usage_report                          # Today's data, grouped by model"
        echo "  usage_report 2025-01-10 2025-01-15    # Custom date range"
        echo "  usage_report 2025-01-10 2025-01-15 model # Group by model"
        echo ""
        return 0
    fi

    # Check environment variables
    if [[ -z "${ANTHROPIC_ADMIN_API_KEY:-}" ]]; then
        echo "❌ Error: ANTHROPIC_ADMIN_API_KEY not set"
        echo "Export your Admin API key: export ANTHROPIC_ADMIN_API_KEY=\"sk-ant-admin-...\""
        return 1
    fi

    # Run the script
    "${SHELL_COMMON}/tools/custom/usage_report.sh" "$@"
}

# ═══════════════════════════════════════════════════════════════
# Organization Cost Report Function
# ═══════════════════════════════════════════════════════════════

cost_report() {
    local start_date="${1:---help}"

    if [[ "$start_date" == "--help" ]] || [[ "$start_date" == "-h" ]]; then
        echo ""
        echo "💰 Organization Cost Report"
        echo ""
        echo "Usage:"
        echo "  cost_report [START_DATE] [END_DATE]"
        echo ""
        echo "Arguments:"
        echo "  START_DATE : Start date (YYYY-MM-DD), default: yesterday"
        echo "  END_DATE   : End date (YYYY-MM-DD), default: today"
        echo ""
        echo "Requirements:"
        echo "  • Export ANTHROPIC_ADMIN_API_KEY environment variable"
        echo ""
        echo "Setup:"
        echo "  export ANTHROPIC_ADMIN_API_KEY=\"sk-ant-admin-...\""
        echo ""
        echo "Examples:"
        echo "  cost_report                    # Yesterday and today"
        echo "  cost_report 2025-01-10 2025-01-15  # Custom date range"
        echo ""
        return 0
    fi

    # Check environment variables
    if [[ -z "${ANTHROPIC_ADMIN_API_KEY:-}" ]]; then
        echo "❌ Error: ANTHROPIC_ADMIN_API_KEY not set"
        echo "Export your Admin API key: export ANTHROPIC_ADMIN_API_KEY=\"sk-ant-admin-...\""
        return 1
    fi

    # Run the script
    "${SHELL_COMMON}/tools/custom/cost_report.sh" "$@"
}

# ═══════════════════════════════════════════════════════════════
# Shorthand functions
# ═══════════════════════════════════════════════════════════════

# Shorthand: usage
usage() {
    usage_report "$@"
}

# Shorthand: cost
cost() {
    cost_report "$@"
}
