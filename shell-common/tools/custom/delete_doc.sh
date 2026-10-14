#!/bin/bash
# shell-common/tools/custom/delete_doc.sh
# del-doc — permanently delete documentation files (confirmation required).
#
# PATH executable since #2195 (~/.local/bin/del-doc via config/symlinks.conf):
# it never changes the parent shell's state (docs/.ssot/command-delivery-model.md
# §3), so AI agents' non-interactive `bash -c 'del-doc'` resolve it too.
# functions/manage_doc.sh keeps the `delete_doc` / `del-doc` names as a thin wrapper.

# readlink -f: resolve the ~/.local/bin symlink to find init.sh next to the source.
# shellcheck source=/dev/null
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/init.sh" || exit 1

main() {
    case "${1-}" in
    -h | --help)
        # shellcheck source=/dev/null
        DOTFILES_FORCE_INIT=1 . "${SHELL_COMMON}/functions/manage_doc.sh"
        show_doc_help delete
        return 0
        ;;
    esac
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

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
