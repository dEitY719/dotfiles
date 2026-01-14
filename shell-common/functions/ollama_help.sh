#!/bin/sh
# shell-common/functions/ollama_help.sh
# Ollama / LLM Model Management Help

ollama_help() {
    ux_header "Ollama / LLM Model Management"

    ux_section "Model Management"
    ux_table_row "docker exec ollama ollama list" "List all models" "Show model info (ID, size, modified)"
    ux_table_row "docker exec ollama ollama pull <name>" "Download model" "e.g., tinyllama, gpt-oss:20b"
    ux_table_row "docker exec ollama ollama rm <name>" "Remove model" "Delete model from local storage"
    ux_table_row "docker exec ollama ollama show <name>" "Show model details" "Display model configuration"
    echo ""

    ux_section "Model Usage (Command Line)"
    ux_table_row "docker exec ollama ollama run <model>" "Interactive chat" "Start conversation with model"
    ux_table_row "docker exec ollama ollama run <model> <prompt>" "Single request" "Get response to one query"
    echo ""

    ux_section "Container Logs & Monitoring"
    ux_table_row "docker logs -f ollama" "Follow logs" "Real-time container output"
    ux_table_row "docker stats ollama" "Resource usage" "Monitor CPU, memory, network"
    ux_table_row "docker exec ollama ps aux" "Container processes" "List running processes"
    echo ""

    ux_section "Common Models"
    ux_table_row "tinyllama:latest" "637 MB" "Fast, lightweight model"
    ux_table_row "bge-m3:latest" "1.2 GB" "Embedding/semantic search model"
    ux_table_row "gpt-oss:20b" "13 GB" "Larger capability model"
    ux_table_row "mistral" "4.1 GB" "Fast, general-purpose model"
    ux_table_row "neural-chat" "3.8 GB" "Chat-optimized model"
    echo ""

    ux_section "Practical Examples"
    ux_bullet "List all installed models:"
    ux_info "  docker exec ollama ollama list"
    echo ""
    ux_bullet "Pull and use a specific model:"
    ux_info "  docker exec ollama ollama pull mistral"
    ux_info "  docker exec ollama ollama run mistral 'Explain quantum computing'"
    echo ""
    ux_bullet "Interactive chat with a model:"
    ux_info "  docker exec -it ollama ollama run tinyllama"
    echo ""
    ux_bullet "View model details:"
    ux_info "  docker exec ollama ollama show tinyllama:latest"
    echo ""

    ux_section "Tips"
    ux_bullet "Use '-it' flags for interactive mode: ${UX_CODE}docker exec -it ollama ...${UX_RESET}"
    ux_bullet "Models are stored in container volume: ${UX_CODE}/root/.ollama${UX_RESET}"
    ux_bullet "Model downloads can be large; check disk space before pulling"
    ux_bullet "Combine with ${UX_HIGHLIGHT}docker-help${UX_RESET} for container management"
    echo ""
}

# Aliases for easy access
alias ollama-help='ollama_help'
alias llm-help='ollama_help'
