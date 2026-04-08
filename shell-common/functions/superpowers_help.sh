#!/bin/sh
# shell-common/functions/superpowers_help.sh
# Help display for superpowers plugin skills

SUPERPOWERS_SKILLS_DIR="$HOME/.claude/plugins/cache/superpowers-dev/superpowers"

superpowers_help() {
    # Find installed version directory
    local skills_base=""
    local version=""
    if [ -d "$SUPERPOWERS_SKILLS_DIR" ]; then
        for d in "$SUPERPOWERS_SKILLS_DIR"/*/skills; do
            if [ -d "$d" ]; then
                skills_base="$d"
                version=$(basename "$(dirname "$d")")
                break
            fi
        done
    fi

    ux_header "Superpowers Plugin Skills (v${version:-unknown})"

    ux_section "Process Skills (HOW to approach)"
    ux_table_row "brainstorming" "Creative work, feature design, requirements exploration before implementation"
    ux_table_row "writing-plans" "Multi-step task planning from spec/requirements, before touching code"
    ux_table_row "executing-plans" "Execute written implementation plans in separate sessions with review checkpoints"
    ux_table_row "systematic-debugging" "Bug/test failure diagnosis - root cause analysis before proposing fixes"
    ux_table_row "test-driven-development" "Red-green-refactor: write tests before implementation code"
    ux_table_row "verification-before-completion" "Run verification commands and confirm output before claiming done"

    ux_section "Execution Skills (parallel & isolation)"
    ux_table_row "dispatching-parallel-agents" "Run 2+ independent tasks concurrently without shared state"
    ux_table_row "subagent-driven-development" "Execute implementation plans with independent sub-agents"
    ux_table_row "using-git-worktrees" "Isolated feature work via git worktrees with safety checks"

    ux_section "Review & Completion Skills"
    ux_table_row "requesting-code-review" "Request review after feature completion or before merge"
    ux_table_row "receiving-code-review" "Handle review feedback with technical rigor, not blind agreement"
    ux_table_row "finishing-a-development-branch" "Branch integration: merge, PR, or cleanup options"

    ux_section "Meta Skills"
    ux_table_row "using-superpowers" "Skill discovery and invocation at conversation start"
    ux_table_row "writing-skills" "Create, edit, or verify skills before deployment"

    ux_section "Skill Usage Flow"
    ux_info "Feature Development (full lifecycle):"
    echo ""
    ux_numbered 1 "brainstorming          - explore requirements, design spec"
    ux_numbered 2 "writing-plans          - break spec into bite-sized tasks"
    ux_numbered 3 "executing-plans        - execute tasks (TDD per step)"
    ux_numbered 4 "  or subagent-driven-development (parallel, same session)"
    ux_numbered 5 "requesting-code-review - dispatch reviewer subagent"
    ux_numbered 6 "receiving-code-review  - evaluate & apply feedback"
    ux_numbered 7 "finishing-a-dev-branch - merge, PR, or cleanup"
    echo ""
    ux_info "verification-before-completion runs at every completion claim."
    ux_info "test-driven-development runs inside each execution step."
    echo ""
    ux_info "Bug Fix (shorter cycle):"
    echo ""
    ux_numbered 1 "systematic-debugging   - root cause analysis first"
    ux_numbered 2 "test-driven-development - write failing test for the bug"
    ux_numbered 3 "verification-before-completion"
    ux_numbered 4 "finishing-a-dev-branch - merge the fix"
    echo ""
    ux_info "Parallel tasks: use dispatching-parallel-agents or using-git-worktrees"

    ux_section "Skill Files Location"
    if [ -n "$skills_base" ]; then
        ux_info "$skills_base/"
    else
        ux_warning "Superpowers plugin not found. Install via Claude Code marketplace."
        ux_info "Expected: $SUPERPOWERS_SKILLS_DIR/<version>/skills/"
    fi

    ux_section "Usage"
    ux_bullet "Invoke in Claude Code: ${UX_CODE}/brainstorm${UX_RESET}, ${UX_CODE}/write-plan${UX_RESET}, ${UX_CODE}/execute-plan${UX_RESET}"
    ux_bullet "Read a skill: ${UX_CODE}cat <skills_path>/<skill-name>/SKILL.md${UX_RESET}"
    ux_bullet "Priority: Process skills first, then implementation skills"
}

alias superpowers-help='superpowers_help'
