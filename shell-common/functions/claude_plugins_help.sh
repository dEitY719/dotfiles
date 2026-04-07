#!/bin/sh
# shell-common/functions/claude_plugins_help.sh
# Help display for Claude plugins (split from claude_plugins.sh)

claude_plugins_help() {
    ux_header "Claude Marketplace Plugins Management"


    ux_section "Available Commands"


    ux_section "open_claude_plugins"
    ux_info "Open marketplace plugins directory in VSCode"
    ux_bullet "Usage: ${UX_CODE}open_claude_plugins${UX_RESET}"


    ux_section "list-plugins"
    ux_info "List all available marketplaces and their skills"
    ux_bullet "Usage: ${UX_CODE}list-plugins${UX_RESET}"


    ux_section "init-plugins-docs"
    ux_info "Initialize Korean documentation directory structure"
    ux_bullet "Usage: ${UX_CODE}init-plugins-docs${UX_RESET}"


    ux_section "sync-plugins-structure"
    ux_info "Create directory structure mirroring plugins organization"
    ux_bullet "Usage: ${UX_CODE}sync-plugins-structure${UX_RESET}"


    ux_section "view-plugin-info <plugin-name>"
    ux_info "View specific plugin information"
    ux_bullet "Usage: ${UX_CODE}view-plugin-info algorithmic-art${UX_RESET}"


    ux_section "generate-plugin-doc-ko <source-file> <output-file> [ai-tool]"
    ux_info "Generate Korean documentation from plugin file using any AI tool"
    ux_bullet "Usage (default Claude): ${UX_CODE}generate-plugin-doc-ko file.md output_KO.md${UX_RESET}"
    ux_bullet "Usage (Gemini): ${UX_CODE}generate-plugin-doc-ko file.md output_KO.md gemini${UX_RESET}"


    ux_section "create-plugin-structure-ko <marketplace> <plugin-path> [ai-tool]"
    ux_info "Create structure and generate Korean docs in one command (RECOMMENDED)"
    ux_bullet "Usage (default): ${UX_CODE}create-plugin-structure-ko <marketplace> <path/to/file.md>${UX_RESET}"
    ux_bullet "Usage (Gemini): ${UX_CODE}create-plugin-structure-ko <marketplace> <path/to/file.md> gemini${UX_RESET}"


    ux_section "Quick Examples"
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


    ux_section "Supported AI Tools"
    ux_bullet "claude - Anthropic Claude (default)"
    ux_bullet "gemini - Google Gemini"
    ux_bullet "codex - OpenAI Codex"
    ux_bullet "Any CLI tool accepting -p or --prompt flag"


    ux_section "Recommended Workflow"
    ux_bullet "1. ${UX_CODE}init-plugins-docs${UX_RESET} - Initialize docs directory (first time only)"
    ux_bullet "2. ${UX_CODE}open_claude_plugins${UX_RESET} - Review plugin files in VSCode"
    ux_bullet "3. ${UX_CODE}create-plugin-ko <marketplace> <path>${UX_RESET} - Generate Korean summary"
    ux_bullet "4. Edit & customize generated ${UX_CODE}*_KO.md${UX_RESET} file"
    ux_bullet "5. Add personal notes to ${UX_CODE}README.md${UX_RESET}"
    ux_bullet "6. ${UX_CODE}git add && git commit${UX_RESET} - Save to dotfiles repository"


    ux_section "Directory Structure"
    ux_info "Plugins (read-only marketplace):"
    ux_bullet "\$HOME/.claude/plugins/marketplaces/[marketplace]/plugins/[plugin-name]/agents/[agent].md"

    ux_info "Documentation (git-tracked, mounted):"
    ux_bullet "\$HOME/.claude/docs/marketplaces/[marketplace]/plugins/[plugin-name]/agents/"
    ux_bullet "  ├── [agent]_KO.md    (Korean summary, auto-generated)"
    ux_bullet "  └── README.md         (Learning notes, manual)"


    ux_section "Git Integration"
    ux_info "All documentation is mounted and automatically git-tracked:"
    ux_bullet "User location: ${UX_INFO}~/.claude/docs${UX_RESET} (via bind mount)"
    ux_bullet "Git source: ${UX_INFO}~/dotfiles/claude/docs${UX_RESET}"
    ux_bullet "Changes are version-controlled and shareable across machines"
}
