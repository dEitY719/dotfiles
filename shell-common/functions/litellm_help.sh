#!/bin/sh
# shell-common/functions/litellm_help.sh
# litellm Help - shared between bash and zsh

litellm_help() {
    ux_header "LiteLLM Commands"

    ux_section "Basic Commands"
    ux_table_row "litellm_start" "Start Stack" "docker compose up"
    ux_table_row "litellm_stop" "Stop Stack" "docker compose down"
    ux_table_row "litellm_restart" "Restart" "Stop & Start"
    ux_table_row "litellm_status" "Status" "Check health & models"
    ux_table_row "litellm_models" "List Models" "Show loaded models"
    ux_table_row "litellm_test" "Test Model" "Run basic prompt"
    echo ""

    ux_section "Examples"
    ux_bullet "Start: ${UX_SUCCESS}litellm_start${UX_RESET}"
    ux_bullet "Test:  ${UX_SUCCESS}litellm_test gemini-2.0-flash${UX_RESET}"
    ux_bullet "Check: ${UX_SUCCESS}litellm_status${UX_RESET}"
    echo ""

    ux_section "Project Info"
    ux_table_row "Path" "$LITELLM_PROJECT_PATH" ""
    ux_table_row "URL" "$LITELLM_URL" ""
    ux_table_row "Key" "$LITELLM_API_KEY" ""
    echo ""
}
