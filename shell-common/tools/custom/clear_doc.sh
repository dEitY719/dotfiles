#!/bin/bash
# shell-common/tools/custom/clear_doc.sh
# clear-doc — empty the content of documentation files (confirmation required).
#
# PATH executable since #2195 (~/.local/bin/clear-doc via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'clear-doc'` resolve it too.
# functions/manage_doc.sh keeps the `clear_doc` / `clear-doc` names as a thin wrapper.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1

main() {
    case "${1-}" in
    -h | --help)
        # shellcheck source=/dev/null
        DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/manage_doc.sh"
        show_doc_help clear
        return 0
        ;;
    esac
    # Validate arguments
    if [ $# -eq 0 ]; then
        ux_error "Usage: clear-doc <file|pattern>"
        ux_section "Examples"
        ux_bullet "clear-doc docs/archive/review-2026/abc-review-G.md           # Clear single file"
        ux_bullet "clear-doc 'docs/abc-review*'             # Clear matching files"
        return 1
    fi

    local files=()

    # Process each argument - supports both quoted patterns and direct globs
    # Examples:
    #   clear-doc 'docs/archive/review-2026/abc-review*'      (quoted pattern)
    #   clear-doc docs/archive/review-2026/abc-review*        (unquoted glob - shell expands first)
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

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
