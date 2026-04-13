#!/bin/sh
# shell-common/functions/manage_doc.sh
# Document management utilities for dotfiles
# Provides functions to manage documentation files (clear, archive, etc.)
#
# ═══════════════════════════════════════════════════════════════════════════════
# DEVELOPER NOTES - NAMING CONVENTION (See AGENTS.md:174-178)
# ═══════════════════════════════════════════════════════════════════════════════
# This file demonstrates the project's naming convention:
#
#   INTERNAL NAMES:   snake_case (clear_doc, show_doc_help)
#   USER-FACING:      dash-form  (clear-doc, doc-help via aliases)
#
# CRITICAL RULE:
#   All documentation, help text, examples, and error messages shown to users
#   MUST use dash-form (clear-doc), NEVER snake_case (clear_doc).
#
# Pattern Used in This File:
#   - Function definition:  clear_doc() {}           (snake_case - internal)
#   - Alias definition:     alias clear-doc='clear_doc'  (dash-form - user)
#   - Help text:            "Usage: clear-doc ..."   (dash-form - users see this)
#   - All examples:         "clear-doc file.md"     (dash-form - users copy/paste)
#   - Error messages:       "Usage: clear-doc ..."  (dash-form - users read this)
#
# To preserve this consistency:
#   1. Verify no snake_case appears in user-visible text
#   2. All user-visible text should use dash-form (grep clear-doc show_doc_help)
# ═══════════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════
# UX Library Setup
# ═══════════════════════════════════════════════════════════════

_UX_LIB_PATH="${SHELL_COMMON:-${HOME}/.local/dotfiles/shell-common}/tools/ux_lib/ux_lib.sh"

if [ -f "$_UX_LIB_PATH" ]; then
    source "$_UX_LIB_PATH"
else
    # Fallback for minimal shells without UX library
    ux_header() { echo "=== $1 ==="; }
    ux_section() { echo ""; echo "$1"; }
    ux_success() { echo "✓ $1"; }
    ux_error() { echo "✗ $1" >&2; }
    ux_warning() { echo "⚠ $1"; }
    ux_info() { echo "ℹ $1"; }
    ux_bullet() { echo "  • $1"; }
    ux_confirm() {
        printf "%s❓ %s [y/N]: " "⚠" "$1"
        read -r response
        [ "$response" = "y" ] || [ "$response" = "Y" ]
    }
fi

unset _UX_LIB_PATH

# ═══════════════════════════════════════════════════════════════
# clear_doc() - Clear content of documentation files
# ═══════════════════════════════════════════════════════════════

clear_doc() {
    # Validate arguments
    if [ $# -eq 0 ]; then
        ux_error "Usage: clear-doc <file|pattern>"
        ux_section "Examples"
        ux_bullet "clear-doc docs/review/abc-review-G.md           # Clear single file"
        ux_bullet "clear-doc 'docs/abc-review*'             # Clear matching files"
        return 1
    fi

    local files=()

    # Process each argument - supports both quoted patterns and direct globs
    # Examples:
    #   clear-doc 'docs/review/abc-review*'      (quoted pattern)
    #   clear-doc docs/review/abc-review*        (unquoted glob - shell expands first)
    #   clear-doc docs/file1.md docs/file2.md  (multiple explicit files)
    for arg in "$@"; do
        # Try glob expansion on each argument
        # If arg contains wildcards (quoted), this expands them
        # If arg is a literal filename, this just returns the filename as-is
        for f in $arg; do
            if [ -f "$f" ]; then
                files+=("$f")
            fi
        done
    done

    # Handle case where no files match
    if [ ${#files[@]} -eq 0 ]; then
        ux_error "No matching files found"
        ux_info "Searched for: $*"
        return 1
    fi

    # Show header
    echo ""
    ux_header "Document Content Clearing"
    echo ""

    # Display files to be cleared
    ux_section "Files to be cleared (${#files[@]})"
    for file in "${files[@]}"; do
        # Show file size before clearing
        local size
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "?")
        ux_bullet "$file ($size bytes)"
    done
    echo ""

    # Request user confirmation (destructive operation)
    ux_warning "This will permanently delete the content of these files"
    if ! ux_confirm "Clear content of ${#files[@]} file(s)?"; then
        ux_info "Operation cancelled"
        echo ""
        return 0
    fi

    # Clear each file
    echo ""
    ux_section "Clearing files"
    local success_count=0
    local error_count=0

    for file in "${files[@]}"; do
        # NOTE: Avoid a "bare" redirection (`> file`) in zsh.
        # In interactive zsh, it can redirect the current shell's stdout,
        # causing subsequent output (including the prompt) to disappear.
        if : > "$file" 2>/dev/null; then
            ux_success "Cleared: $file"
            ((success_count++))
        else
            ux_error "Failed to clear: $file (permission denied?)"
            ((error_count++))
        fi
    done

    # Summary
    echo ""
    ux_section "Summary"
    if [ $error_count -eq 0 ]; then
        ux_success "$success_count file(s) cleared successfully"
        echo ""
        return 0
    else
        ux_warning "$success_count succeeded, $error_count failed"
        echo ""
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# delete_doc() - Delete documentation files permanently
# ═══════════════════════════════════════════════════════════════

delete_doc() {
    # Validate arguments
    if [ $# -eq 0 ]; then
        ux_error "Usage: del-doc <file|pattern>"
        ux_section "Examples"
        ux_bullet "del-doc docs/abc-review-G.md           # Delete single file"
        ux_bullet "del-doc 'docs/abc-plan*'                # Delete matching files"
        ux_bullet "del-doc 'docs/abc-review*2.md'          # Delete abc-review-CX2.md, etc"
        echo ""
        return 1
    fi

    local files=()

    # Process each argument - supports both quoted patterns and direct globs
    # Examples:
    #   del-doc 'docs/abc-plan*'       (quoted pattern)
    #   del-doc docs/abc-plan*         (unquoted glob - shell expands first)
    #   del-doc docs/file1.md docs/file2.md  (multiple explicit files)
    for arg in "$@"; do
        # Try glob expansion on each argument
        # If arg contains wildcards (quoted), this expands them
        # If arg is a literal filename, this just returns the filename as-is
        for f in $arg; do
            if [ -f "$f" ]; then
                files+=("$f")
            fi
        done
    done

    # Handle case where no files match
    if [ ${#files[@]} -eq 0 ]; then
        ux_error "No matching files found"
        ux_info "Searched for: $*"
        return 1
    fi

    # Show header
    echo ""
    ux_header "Document Deletion"
    echo ""

    # Display files to be deleted
    ux_section "Files to be deleted (${#files[@]})"
    for file in "${files[@]}"; do
        # Show file size before deletion
        local size
        size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "?")
        ux_bullet "$file ($size bytes)"
    done
    echo ""

    # Request user confirmation (destructive operation)
    ux_warning "This will permanently DELETE these files and cannot be undone"
    if ! ux_confirm "Delete ${#files[@]} file(s)?"; then
        ux_info "Operation cancelled"
        echo ""
        return 0
    fi

    # Delete each file
    echo ""
    ux_section "Deleting files"
    local success_count=0
    local error_count=0

    for file in "${files[@]}"; do
        if rm -f "$file" 2>/dev/null; then
            ux_success "Deleted: $file"
            ((success_count++))
        else
            ux_error "Failed to delete: $file (permission denied?)"
            ((error_count++))
        fi
    done

    # Summary
    echo ""
    ux_section "Summary"
    if [ $error_count -eq 0 ]; then
        ux_success "$success_count file(s) deleted successfully"
        echo ""
        return 0
    else
        ux_warning "$success_count succeeded, $error_count failed"
        echo ""
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# archive_doc() - Archive documentation files (placeholder for future)
# ═══════════════════════════════════════════════════════════════

archive_doc() {
    ux_error "archive-doc not yet implemented"
    return 1
}

# ═══════════════════════════════════════════════════════════════
# show_doc_help() - Show help for document management
# ═══════════════════════════════════════════════════════════════

_show_doc_help_summary() {
    ux_info "Usage: show-doc-help [section|--list|--all]"
    ux_bullet "sections"
    ux_bullet_sub "clear: clear-doc <file|pattern> usage and examples"
    ux_bullet_sub "delete: del-doc <file|pattern> usage and examples"
    ux_bullet_sub "description: behavior and safety notes"
    ux_bullet_sub "patterns: glob pattern reference"
    ux_bullet_sub "details: show-doc-help <section>  (example: show-doc-help clear)"
}

_show_doc_help_list_sections() {
    ux_bullet "sections"
    ux_bullet_sub "clear"
    ux_bullet_sub "delete"
    ux_bullet_sub "description"
    ux_bullet_sub "patterns"
}

_show_doc_help_rows_clear() {
    ux_bullet "Clear content of documentation files"
    ux_info "Usage: clear-doc <file|pattern>"
    ux_info "Examples:"
    ux_bullet "clear-doc docs/review/abc-review-G.md       // Clear single file"
    ux_bullet "clear-doc docs/review/abc-review*           // Unquoted glob (both work!)"
    ux_bullet "clear-doc 'docs/review/abc-review*'         // Quoted pattern"
    ux_bullet "clear-doc docs/file1.md docs/file2.md       // Multiple files"
    ux_bullet "clear-doc 'docs/*.md' notes.txt             // Mixed patterns + files"
}

_show_doc_help_rows_delete() {
    ux_bullet "Permanently delete documentation files"
    ux_info "Usage: del-doc <file|pattern>"
    ux_info "Examples:"
    ux_bullet "del-doc docs/review/abc-review-G.md         // Delete single file"
    ux_bullet "del-doc docs/review/abc-plan*               // Unquoted glob"
    ux_bullet "del-doc 'docs/review/abc-review*2.md'       // Quoted pattern (deletes *2.md files)"
    ux_bullet "del-doc docs/file1.md docs/file2.md         // Multiple files"
    ux_bullet "del-doc 'docs/abc-*' notes.txt              // Mixed patterns + files"
}

_show_doc_help_rows_description() {
    ux_info "Safely clears the content of documentation files (clear-doc)"
    ux_info "Permanently deletes documentation files (del-doc)"
    ux_info "Both operations require user confirmation (destructive)"
    ux_info "Support both individual files and glob patterns"
}

_show_doc_help_rows_patterns() {
    ux_bullet "* matches any characters"
    ux_bullet "? matches single character"
}

_show_doc_help_render_section() {
    ux_section "$1"
    "$2"
}

_show_doc_help_section_rows() {
    case "$1" in
        clear|clear-doc)
            _show_doc_help_rows_clear
            ;;
        delete|del|del-doc)
            _show_doc_help_rows_delete
            ;;
        description|desc|about)
            _show_doc_help_rows_description
            ;;
        patterns|pattern|glob)
            _show_doc_help_rows_patterns
            ;;
        *)
            ux_error "Unknown show-doc-help section: $1"
            ux_info "Try: show-doc-help --list"
            return 1
            ;;
    esac
}

_show_doc_help_full() {
    ux_header "Document Management Commands"
    _show_doc_help_render_section "clear-doc" _show_doc_help_rows_clear
    _show_doc_help_render_section "del-doc" _show_doc_help_rows_delete
    _show_doc_help_render_section "Description" _show_doc_help_rows_description
    _show_doc_help_render_section "Patterns" _show_doc_help_rows_patterns
}

show_doc_help() {
    case "${1:-}" in
        ""|-h|--help|help)
            _show_doc_help_summary
            ;;
        --list|list)
            _show_doc_help_list_sections
            ;;
        --all|all)
            _show_doc_help_full
            ;;
        *)
            _show_doc_help_section_rows "$1"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# Main execution
# ═══════════════════════════════════════════════════════════════

# Export functions for use in subshells and aliases (bash-specific)
# Note: export -f is bash-only; zsh doesn't need this as functions are already available
if [ -n "$BASH_VERSION" ]; then
    export -f clear_doc
    export -f delete_doc
    export -f archive_doc
    export -f show_doc_help
fi

# ═══════════════════════════════════════════════════════════════
# Aliases
# ═══════════════════════════════════════════════════════════════

alias clear-doc='clear_doc'
alias del-doc='delete_doc'
alias doc-help='show_doc_help'
alias show-doc-help='show_doc_help'

# ═══════════════════════════════════════════════════════════════
# Main execution - Only run if directly executed, not sourced
# ═══════════════════════════════════════════════════════════════

# If SHELL_COMMON is set, we're being loaded by the dotfiles loader (main.bash/main.zsh)
# Skip direct execution in that case
if [ -z "${SHELL_COMMON:-}" ]; then
    # Check if this script is being executed directly (not sourced)
    # Safe method: Use parameter expansion instead of basename to avoid flag injection
    _script_name="${0##*/}"

    # Validate that _script_name doesn't start with - (indicates sourced with flags)
    if [ "${_script_name#-}" = "$_script_name" ]; then
        case "$_script_name" in
            manage_doc.sh|manage_doc)
                # This is direct execution - run with arguments
                if [ "${DOTFILES_TEST_MODE:-0}" != "1" ] && [ -n "${1:-}" ]; then
                    case "$1" in
                        clear_doc|delete_doc|archive_doc|show_doc_help)
                            "$@"
                            ;;
                        *)
                            # Default to clear_doc for backward compatibility with alias
                            clear_doc "$@"
                            ;;
                    esac
                fi
                ;;
        esac
    fi

    unset _script_name
fi
