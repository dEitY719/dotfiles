#!/bin/sh
# shell-common/functions/superpowers_help.sh
# Help display for superpowers plugin skills

SUPERPOWERS_SKILLS_DIR="$HOME/.claude/plugins/cache/superpowers-dev/superpowers"

# Resolve the installed superpowers skills base directory and version
_superpowers_help_resolve() {
    _SUPERPOWERS_SKILLS_BASE=""
    _SUPERPOWERS_VERSION=""
    if [ -d "$SUPERPOWERS_SKILLS_DIR" ]; then
        for d in "$SUPERPOWERS_SKILLS_DIR"/*/skills; do
            if [ -d "$d" ]; then
                _SUPERPOWERS_SKILLS_BASE="$d"
                _SUPERPOWERS_VERSION=$(basename "$(dirname "$d")")
                break
            fi
        done
    fi
}

_superpowers_help_summary() {
    ux_info "Usage: superpowers-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "process: brainstorming | plans | TDD | debugging | verify"
    ux_bullet_sub "execution: parallel agents | subagents | worktrees"
    ux_bullet_sub "review: request | receive | finishing branch"
    ux_bullet_sub "meta: using-superpowers | writing-skills"
    ux_bullet_sub "flow: feature & bug-fix lifecycles"
    ux_bullet_sub "location: skill files path"
    ux_bullet_sub "usage: invocation tips"
    ux_bullet_sub "details: superpowers-help <section>"
}

_superpowers_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "process"
    ux_bullet_sub "execution"
    ux_bullet_sub "review"
    ux_bullet_sub "meta"
    ux_bullet_sub "flow"
    ux_bullet_sub "location"
    ux_bullet_sub "usage"
}

_superpowers_help_rows_process() {
    ux_table_row "brainstorming" "Creative work, feature design, requirements exploration before implementation"
    ux_table_row "writing-plans" "Multi-step task planning from spec/requirements, before touching code"
    ux_table_row "executing-plans" "Execute written implementation plans in separate sessions with review checkpoints"
    ux_table_row "systematic-debugging" "Bug/test failure diagnosis - root cause analysis before proposing fixes"
    ux_table_row "test-driven-development" "Red-green-refactor: write tests before implementation code"
    ux_table_row "verification-before-completion" "Run verification commands and confirm output before claiming done"
}

_superpowers_help_rows_execution() {
    ux_table_row "dispatching-parallel-agents" "Run 2+ independent tasks concurrently without shared state"
    ux_table_row "subagent-driven-development" "Execute implementation plans with independent sub-agents"
    ux_table_row "using-git-worktrees" "Isolated feature work via git worktrees with safety checks"
}

_superpowers_help_rows_review() {
    ux_table_row "requesting-code-review" "Request review after feature completion or before merge"
    ux_table_row "receiving-code-review" "Handle review feedback with technical rigor, not blind agreement"
    ux_table_row "finishing-a-development-branch" "Branch integration: merge, PR, or cleanup options"
}

_superpowers_help_rows_meta() {
    ux_table_row "using-superpowers" "Skill discovery and invocation at conversation start"
    ux_table_row "writing-skills" "Create, edit, or verify skills before deployment"
}

_superpowers_help_rows_flow() {
    ux_info "Feature Development (full lifecycle):"
    ux_numbered 1 "brainstorming          - explore requirements, design spec"
    ux_numbered 2 "writing-plans          - break spec into bite-sized tasks"
    ux_numbered 3 "executing-plans        - execute tasks (TDD per step)"
    ux_numbered 4 "  or subagent-driven-development (parallel, same session)"
    ux_numbered 5 "requesting-code-review - dispatch reviewer subagent"
    ux_numbered 6 "receiving-code-review  - evaluate & apply feedback"
    ux_numbered 7 "finishing-a-dev-branch - merge, PR, or cleanup"
    ux_info "verification-before-completion runs at every completion claim."
    ux_info "test-driven-development runs inside each execution step."
    ux_info "Bug Fix (shorter cycle):"
    ux_numbered 1 "systematic-debugging   - root cause analysis first"
    ux_numbered 2 "test-driven-development - write failing test for the bug"
    ux_numbered 3 "verification-before-completion"
    ux_numbered 4 "finishing-a-dev-branch - merge the fix"
    ux_info "Parallel tasks: use dispatching-parallel-agents or using-git-worktrees"
}

_superpowers_help_rows_location() {
    _superpowers_help_resolve
    if [ -n "$_SUPERPOWERS_SKILLS_BASE" ]; then
        ux_info "$_SUPERPOWERS_SKILLS_BASE/"
    else
        ux_warning "Superpowers plugin not found. Install via Claude Code marketplace."
        ux_info "Expected: $SUPERPOWERS_SKILLS_DIR/<version>/skills/"
    fi
}

_superpowers_help_rows_usage() {
    ux_bullet "Invoke in Claude Code: ${UX_CODE}/brainstorm${UX_RESET}, ${UX_CODE}/write-plan${UX_RESET}, ${UX_CODE}/execute-plan${UX_RESET}"
    ux_bullet "Read a skill: ${UX_CODE}cat <skills_path>/<skill-name>/SKILL.md${UX_RESET}"
    ux_bullet "Priority: Process skills first, then implementation skills"
}

_superpowers_help_render_section() {
    ux_section "$1"
    "$2"
}

_superpowers_help_section_rows() {
    case "$1" in
        process|how)
            _superpowers_help_rows_process
            ;;
        execution|exec|parallel)
            _superpowers_help_rows_execution
            ;;
        review|completion)
            _superpowers_help_rows_review
            ;;
        meta)
            _superpowers_help_rows_meta
            ;;
        flow|workflow|usage-flow)
            _superpowers_help_rows_flow
            ;;
        location|path|files)
            _superpowers_help_rows_location
            ;;
        usage|use|invoke)
            _superpowers_help_rows_usage
            ;;
        *)
            ux_error "Unknown superpowers-help section: $1"
            ux_info "Try: superpowers-help --list"
            return 1
            ;;
    esac
}

_superpowers_help_full() {
    _superpowers_help_resolve
    ux_header "Superpowers Plugin Skills (v${_SUPERPOWERS_VERSION:-unknown})"
    _superpowers_help_render_section "Process Skills (HOW to approach)" _superpowers_help_rows_process
    _superpowers_help_render_section "Execution Skills (parallel & isolation)" _superpowers_help_rows_execution
    _superpowers_help_render_section "Review & Completion Skills" _superpowers_help_rows_review
    _superpowers_help_render_section "Meta Skills" _superpowers_help_rows_meta
    _superpowers_help_render_section "Skill Usage Flow" _superpowers_help_rows_flow
    _superpowers_help_render_section "Skill Files Location" _superpowers_help_rows_location
    _superpowers_help_render_section "Usage" _superpowers_help_rows_usage
}

superpowers_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _superpowers_help_summary
            ;;
        --list|list)
            _superpowers_help_list_sections
            ;;
        --all|all)
            _superpowers_help_full
            ;;
        *)
            _superpowers_help_section_rows "$1"
            ;;
    esac
}

alias superpowers-help='superpowers_help'
