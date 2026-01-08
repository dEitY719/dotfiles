#!/bin/sh
# shell-common/functions/litellm_help.sh
# litellm Help - shared between bash and zsh

litellm_help() {
    ux_header "LiteLLM Commands"

    ux_section "Basic Commands"
    ux_table_row "llm-start" "Start Stack" "docker compose up"
    ux_table_row "llm-stop" "Stop Stack" "docker compose down"
    ux_table_row "llm-restart" "Restart" "Stop & Start"
    ux_table_row "llm-status" "Status" "Check health & models"
    ux_table_row "llm-models" "List Models" "Show loaded models"
    ux_table_row "llm-test" "Test Model" "Run basic prompt"
    echo ""

    ux_section "Examples"
    ux_bullet "Start: ${UX_SUCCESS}litellm_start${UX_RESET}"
    # ux_bullet "Test:  ${UX_SUCCESS}litellm_test gemini-2.0-flash${UX_RESET}"
    ux_bullet "Test:  ${UX_SUCCESS}litellm_test gpt-oss-20b${UX_RESET}"
    ux_bullet "Check: ${UX_SUCCESS}litellm_status${UX_RESET}"
    echo ""

    ux_section "Project Info"
    ux_table_row "Path" "$LITELLM_PROJECT_PATH" ""
    ux_table_row "URL" "$LITELLM_URL" ""
    ux_table_row "Key" "$LITELLM_API_KEY" ""
    echo ""
}

# Alias for litellm-help format (using dash instead of underscore)
alias litellm-help='litellm_help'
