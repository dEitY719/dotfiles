#!/bin/sh
# shell-common/functions/claude_plugins_help.sh
# Help display for Claude plugins (split from claude_plugins.sh)

_claude_plugins_help_summary() {
    ux_info "Usage: claude-plugins-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "commands: open_claude_plugins | list-plugins | init-plugins-docs | sync-plugins-structure"
    ux_bullet_sub "view: view-plugin-info | generate-plugin-doc-ko | create-plugin-structure-ko"
    ux_bullet_sub "examples: quick examples for create-plugin-ko"
    ux_bullet_sub "ai-tools: claude | gemini | codex"
    ux_bullet_sub "workflow: recommended workflow"
    ux_bullet_sub "structure: plugin and docs directory layout"
    ux_bullet_sub "git: git integration & mount details"
    ux_bullet_sub "details: claude-plugins-help <section>"
}

_claude_plugins_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "commands"
    ux_bullet_sub "view"
    ux_bullet_sub "examples"
    ux_bullet_sub "ai-tools"
    ux_bullet_sub "workflow"
    ux_bullet_sub "structure"
    ux_bullet_sub "git"
}

_claude_plugins_help_rows_commands() {
    ux_bullet "open_claude_plugins  - Open marketplace plugins directory in VSCode"
    ux_bullet "list-plugins         - List all available marketplaces and their skills"
    ux_bullet "init-plugins-docs    - Initialize Korean documentation directory structure"
    ux_bullet "sync-plugins-structure - Create directory structure mirroring plugins organization"
}

_claude_plugins_help_rows_view() {
    ux_bullet "view-plugin-info <plugin-name>"
    ux_bullet "  Usage: ${UX_CODE}view-plugin-info algorithmic-art${UX_RESET}"
    ux_bullet "generate-plugin-doc-ko <source-file> <output-file> [ai-tool]"
    ux_bullet "  Default Claude: ${UX_CODE}generate-plugin-doc-ko file.md output_KO.md${UX_RESET}"
    ux_bullet "  Gemini: ${UX_CODE}generate-plugin-doc-ko file.md output_KO.md gemini${UX_RESET}"
    ux_bullet "create-plugin-structure-ko <marketplace> <plugin-path> [ai-tool]"
    ux_bullet "  Default: ${UX_CODE}create-plugin-structure-ko <marketplace> <path/to/file.md>${UX_RESET}"
    ux_bullet "  Gemini: ${UX_CODE}create-plugin-structure-ko <marketplace> <path/to/file.md> gemini${UX_RESET}"
}

_claude_plugins_help_rows_examples() {
    ux_bullet "1. Generate with default AI (Claude):"
    ux_bullet "   ${UX_CODE}create-plugin-ko claude-code-workflows plugins/code-refactoring/agents/code-reviewer.md${UX_RESET}"
    ux_bullet "2. Generate with Gemini:"
    ux_bullet "   ${UX_CODE}create-plugin-ko claude-code-workflows plugins/code-refactoring/agents/code-reviewer.md gemini${UX_RESET}"
    ux_bullet "3. Change default AI tool for session:"
    ux_bullet "   ${UX_CODE}export CLAUDE_DOC_GENERATOR=codex${UX_RESET}"
    ux_bullet "   ${UX_CODE}create-plugin-ko claude-code-workflows plugins/code-refactoring/agents/code-reviewer.md${UX_RESET}"
    ux_bullet "4. Review the generated file:"
    ux_bullet "   ${UX_CODE}code ~/.claude/docs/marketplaces/claude-code-workflows/plugins/code-refactoring/agents/code-reviewer_KO.md${UX_RESET}"
    ux_bullet "5. Commit to git:"
    ux_bullet "   ${UX_CODE}cd ~/dotfiles && git add claude/docs/ && git commit -m 'docs: Add Korean summary'${UX_RESET}"
}

_claude_plugins_help_rows_ai_tools() {
    ux_bullet "claude - Anthropic Claude (default)"
    ux_bullet "gemini - Google Gemini"
    ux_bullet "codex - OpenAI Codex"
    ux_bullet "Any CLI tool accepting -p or --prompt flag"
}

_claude_plugins_help_rows_workflow() {
    ux_bullet "1. ${UX_CODE}init-plugins-docs${UX_RESET} - Initialize docs directory (first time only)"
    ux_bullet "2. ${UX_CODE}open_claude_plugins${UX_RESET} - Review plugin files in VSCode"
    ux_bullet "3. ${UX_CODE}create-plugin-ko <marketplace> <path>${UX_RESET} - Generate Korean summary"
    ux_bullet "4. Edit & customize generated ${UX_CODE}*_KO.md${UX_RESET} file"
    ux_bullet "5. Add personal notes to ${UX_CODE}README.md${UX_RESET}"
    ux_bullet "6. ${UX_CODE}git add && git commit${UX_RESET} - Save to dotfiles repository"
}

_claude_plugins_help_rows_structure() {
    ux_info "Plugins (read-only marketplace):"
    ux_bullet "\$HOME/.claude/plugins/marketplaces/[marketplace]/plugins/[plugin-name]/agents/[agent].md"
    ux_info "Documentation (git-tracked, mounted):"
    ux_bullet "\$HOME/.claude/docs/marketplaces/[marketplace]/plugins/[plugin-name]/agents/"
    ux_bullet "  ├── [agent]_KO.md    (Korean summary, auto-generated)"
    ux_bullet "  └── README.md         (Learning notes, manual)"
}

_claude_plugins_help_rows_git() {
    ux_info "All documentation is mounted and automatically git-tracked:"
    ux_bullet "User location: ${UX_INFO}~/.claude/docs${UX_RESET} (via bind mount)"
    ux_bullet "Git source: ${UX_INFO}~/dotfiles/claude/docs${UX_RESET}"
    ux_bullet "Changes are version-controlled and shareable across machines"
}

_claude_plugins_help_render_section() {
    ux_section "$1"
    "$2"
}

_claude_plugins_help_section_rows() {
    case "$1" in
        commands|cmd|cmds)
            _claude_plugins_help_rows_commands
            ;;
        view|generate|gen)
            _claude_plugins_help_rows_view
            ;;
        examples|example|ex)
            _claude_plugins_help_rows_examples
            ;;
        ai-tools|ai|tools)
            _claude_plugins_help_rows_ai_tools
            ;;
        workflow|flow)
            _claude_plugins_help_rows_workflow
            ;;
        structure|dir|directory)
            _claude_plugins_help_rows_structure
            ;;
        git|integration)
            _claude_plugins_help_rows_git
            ;;
        *)
            ux_error "Unknown claude-plugins-help section: $1"
            ux_info "Try: claude-plugins-help --list"
            return 1
            ;;
    esac
}

_claude_plugins_help_full() {
    ux_header "Claude Marketplace Plugins Management"
    _claude_plugins_help_render_section "Available Commands" _claude_plugins_help_rows_commands
    _claude_plugins_help_render_section "View & Generate" _claude_plugins_help_rows_view
    _claude_plugins_help_render_section "Quick Examples" _claude_plugins_help_rows_examples
    _claude_plugins_help_render_section "Supported AI Tools" _claude_plugins_help_rows_ai_tools
    _claude_plugins_help_render_section "Recommended Workflow" _claude_plugins_help_rows_workflow
    _claude_plugins_help_render_section "Directory Structure" _claude_plugins_help_rows_structure
    _claude_plugins_help_render_section "Git Integration" _claude_plugins_help_rows_git
}

claude_plugins_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _claude_plugins_help_summary
            ;;
        --list|list|section|sections)
            _claude_plugins_help_list_sections
            ;;
        --all|all)
            _claude_plugins_help_full
            ;;
        *)
            _claude_plugins_help_section_rows "$1"
            ;;
    esac
}

alias claude-plugins-help='claude_plugins_help'
