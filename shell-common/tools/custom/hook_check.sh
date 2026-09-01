#!/bin/bash
# shell-common/tools/custom/hook_check.sh
#
# Git Hook Configuration Diagnostic Tool
# Checks if git hooks are properly configured and offers solutions
#
# Usage: hook_check
# Alias: hook-check

# Initialize common tools environment
source "$(dirname "$0")/init.sh" || exit 1

# ============================================================
# Helper Functions
# ============================================================

_format_check() {
    local label="$1"
    local status="$2"  # "✓", "✗", "⚠"
    local value="$3"

    if [ "$status" = "✓" ]; then
        printf "  ${UX_GREEN}%s${UX_RESET} %-30s : %s\n" "$status" "$label" "$value"
    elif [ "$status" = "✗" ]; then
        printf "  ${UX_RED}%s${UX_RESET} %-30s : %s\n" "$status" "$label" "$value"
    else  # "⚠"
        printf "  ${UX_YELLOW}%s${UX_RESET} %-30s : %s\n" "$status" "$label" "$value"
    fi
}

_run_setup_hooks() {
    if [ ! -f "$DOTFILES_ROOT/git/setup.sh" ]; then
        ux_error "setup.sh not found at: $DOTFILES_ROOT/git/setup.sh"
        return 1
    fi

    ux_info "Running git/setup.sh to configure hooks..."
    echo ""
    bash "$DOTFILES_ROOT/git/setup.sh"
    return $?
}

# Expected global hook set (issue #1664).
#
# core.hooksPath REPLACES .git/hooks, so EVERY hook the dotfiles rely on must
# be present here — checking pre-commit alone hid four dead hooks.
# SSOT: GIT_GLOBAL_HOOKS in git/config/hook-config.sh; the directory listing
# is only a fallback for a checkout without that config.
_load_global_hook_names() {
    local config="${DOTFILES_ROOT}/git/config/hook-config.sh"
    local hook_file

    if [ -f "$config" ]; then
        # shellcheck source=/dev/null
        source "$config"
    fi

    if declare -p GIT_GLOBAL_HOOKS >/dev/null 2>&1 && [ ${#GIT_GLOBAL_HOOKS[@]} -gt 0 ]; then
        GLOBAL_HOOK_NAMES=("${GIT_GLOBAL_HOOKS[@]}")
        return 0
    fi

    GLOBAL_HOOK_NAMES=()
    for hook_file in "${DOTFILES_ROOT}/git/global-hooks"/*; do
        [ -f "$hook_file" ] || continue
        GLOBAL_HOOK_NAMES+=("$(basename "$hook_file")")
    done
}

# Configured global hooks directory with a leading ~ expanded.
_global_hooks_dir() {
    local hooks_path
    hooks_path=$(git config --global core.hooksPath 2>/dev/null)
    printf '%s' "${hooks_path/#\~/$HOME}"
}

# ============================================================
# Check 1: core.hooksPath Configuration
# ============================================================

check_hooks_path() {
    ux_header "CHECK 1: Git core.hooksPath Configuration"

    local hooks_path
    hooks_path=$(git config --global core.hooksPath 2>/dev/null)

    if [ -z "$hooks_path" ]; then
        _format_check "core.hooksPath" "✗" "[NOT SET]"
        echo ""
        ux_error "Global hooks path is not configured"
        ux_section "Solution:"
        ux_bullet "Run: git config --global core.hooksPath ~/.config/git/hooks"
        ux_bullet "Or run: cd $DOTFILES_ROOT && ./git/setup.sh"
        echo ""
        return 1
    fi

    # Expand ~ to actual home directory for comparison
    local expanded_hooks_path="${hooks_path/#\~/$HOME}"

    _format_check "core.hooksPath" "✓" "$hooks_path"

    if [ -d "$expanded_hooks_path" ]; then
        ux_success "Directory exists"
    else
        _format_check "Directory Status" "✗" "Does not exist"
        ux_section "Solution:"
        ux_bullet "Create directory: mkdir -p $expanded_hooks_path"
        echo ""
        return 1
    fi

    echo ""
    return 0
}

# ============================================================
# Check 2: Hook Files Existence
# ============================================================

check_hook_files() {
    ux_header "CHECK 2: Hook Files Existence"

    local hooks_path
    hooks_path=$(git config --global core.hooksPath 2>/dev/null)
    local expanded_hooks_path="${hooks_path/#\~/$HOME}"

    if [ -z "$expanded_hooks_path" ]; then
        ux_warning "core.hooksPath is not set, skipping hook file check"
        echo ""
        return 1
    fi

    local has_error=0
    local hook_name hook_file hook_label target

    for hook_name in "${GLOBAL_HOOK_NAMES[@]}"; do
        hook_file="${expanded_hooks_path}/${hook_name}"
        hook_label="${hooks_path}/${hook_name}"

        if [ -L "$hook_file" ] && [ ! -e "$hook_file" ]; then
            # Dangling symlink: the dotfiles checkout moved or was removed.
            _format_check "$hook_label" "✗" "Broken symlink"
            has_error=1
            continue
        fi

        if [ -f "$hook_file" ]; then
            _format_check "$hook_label" "✓" "Exists"

            # Check if it's a symlink
            if [ -L "$hook_file" ]; then
                target=$(readlink -f "$hook_file" 2>/dev/null || readlink "$hook_file")
                ux_bullet "Symlink target: $target"
            fi
        else
            _format_check "$hook_label" "✗" "Missing"
            has_error=1
        fi
    done

    echo ""

    if [ $has_error -eq 1 ]; then
        ux_error "Some hook files are missing"
        ux_section "Solution:"
        ux_bullet "Run: cd $DOTFILES_ROOT && ./git/setup.sh"
        echo ""
        return 1
    fi

    echo ""
    return 0
}

# ============================================================
# Check 3: Hook File Permissions
# ============================================================

check_permissions() {
    ux_header "CHECK 3: Hook File Permissions"

    local expanded_hooks_path
    expanded_hooks_path=$(_global_hooks_dir)

    if [ -z "$expanded_hooks_path" ]; then
        ux_warning "core.hooksPath is not set, skipping permission check"
        echo ""
        return 0
    fi

    local has_error=0
    local hook_name hook_file mode

    for hook_name in "${GLOBAL_HOOK_NAMES[@]}"; do
        hook_file="${expanded_hooks_path}/${hook_name}"

        if [ ! -f "$hook_file" ]; then
            _format_check "$hook_name" "⚠" "Not found, skipping"
            continue
        fi

        mode=$(stat -c '%A' "$hook_file" 2>/dev/null || stat -f '%A' "$hook_file" 2>/dev/null)

        if [ -x "$hook_file" ]; then
            _format_check "$hook_name" "✓" "Executable ($mode)"
        else
            _format_check "$hook_name" "✗" "Not executable ($mode)"
            has_error=1
        fi
    done

    echo ""

    if [ $has_error -eq 1 ]; then
        ux_error "Some hook files are not executable"
        ux_section "Solution:"
        ux_bullet "Run: chmod +x ${expanded_hooks_path}/*"
        echo ""
        return 1
    fi

    return 0
}

# ============================================================
# Check 4: Project-level Hooks Setup
# ============================================================

check_project_hooks() {
    ux_header "CHECK 4: Project-level Hooks Setup"

    # Find git directory of current repository (not DOTFILES_ROOT)
    local git_dir
    git_dir=$(git rev-parse --git-dir 2>/dev/null)

    if [ -z "$git_dir" ] || [ ! -d "$git_dir" ]; then
        ux_warning "Not in a git repository"
        echo ""
        return 0
    fi

    # Resolve to absolute path (git rev-parse can return relative paths like .git)
    if [ "${git_dir#/}" = "$git_dir" ]; then
        # Relative path, convert to absolute
        git_dir="$(cd "$(pwd)" && pwd)/$git_dir"
    fi

    local project_hook="$git_dir/hooks/pre-commit"

    if [ -f "$project_hook" ]; then
        _format_check ".git/hooks/pre-commit" "✓" "Exists"

        if [ -L "$project_hook" ]; then
            local target
            target=$(readlink -f "$project_hook" 2>/dev/null || readlink "$project_hook")
            ux_bullet "Symlink target: $target"
        fi

        if [ -x "$project_hook" ]; then
            _format_check "Executable Permission" "✓" "Yes"
        else
            _format_check "Executable Permission" "✗" "No"
            echo ""
            ux_error "Project hook is not executable"
            ux_section "Solution:"
            ux_bullet "Run: chmod +x $project_hook"
            echo ""
            return 1
        fi
    else
        _format_check ".git/hooks/pre-commit" "⚠" "Missing (Optional)"
    fi

    echo ""
    return 0
}

# ============================================================
# Check 5: Test Hook Execution (Optional)
# ============================================================

test_hook_execution() {
    ux_header "CHECK 5: Hook Execution Test (Optional)"

    local expanded_hooks_path
    expanded_hooks_path=$(_global_hooks_dir)

    if [ -z "$expanded_hooks_path" ]; then
        ux_warning "core.hooksPath is not set, skipping execution test"
        echo ""
        return 0
    fi

    ux_info "Running hooks in dry-run mode (no changes to git index)..."
    echo ""

    local has_error=0
    local hook_name hook_file

    for hook_name in "${GLOBAL_HOOK_NAMES[@]}"; do
        hook_file="${expanded_hooks_path}/${hook_name}"

        if [ ! -f "$hook_file" ]; then
            _format_check "$hook_name" "⚠" "Not found, skipping"
            continue
        fi

        # Parse-only check for syntax errors
        if bash -n "$hook_file" 2>/dev/null; then
            _format_check "$hook_name" "✓" "Syntax valid"
        else
            _format_check "$hook_name" "✗" "Syntax error"
            ux_section "Debug Info:"
            bash -n "$hook_file" 2>&1 | head -20 | sed 's/^/    /'
            has_error=1
        fi
    done

    echo ""

    if [ $has_error -eq 1 ]; then
        ux_error "Some hooks have syntax errors"
        echo ""
        return 1
    fi

    return 0
}

# ============================================================
# Main Diagnostic Flow
# ============================================================

run_all_checks() {
    ux_header "🔍 Git Hook Configuration Diagnostic"

    local all_passed=0
    local should_run_setup=0

    # Load the expected global hook set before any check consumes it.
    _load_global_hook_names

    echo ""

    # Run all checks
    check_hooks_path || { all_passed=1; should_run_setup=1; }
    check_hook_files || { all_passed=1; should_run_setup=1; }
    check_permissions || { all_passed=1; should_run_setup=1; }
    check_project_hooks || { all_passed=1; should_run_setup=1; }
    test_hook_execution

    # Summary and recommendations
    ux_header "📋 Summary"

    if [ $all_passed -eq 0 ]; then
        ux_success "✅ All hook configurations are valid!"
        echo ""
        ux_section "Your git hooks are ready to use:"

        local summary_hooks_path
        summary_hooks_path=$(git config --global core.hooksPath 2>/dev/null)
        local hook_name
        for hook_name in "${GLOBAL_HOOK_NAMES[@]}"; do
            ux_bullet "Global hook: ${summary_hooks_path}/${hook_name}"
        done

        # Show current project hook if in git repo
        local current_git_dir
        current_git_dir=$(git rev-parse --git-dir 2>/dev/null)
        if [ -n "$current_git_dir" ]; then
            # Resolve to absolute path (git rev-parse can return relative paths like .git)
            if [ "${current_git_dir#/}" = "$current_git_dir" ]; then
                # Relative path, convert to absolute
                current_git_dir="$(cd "$(pwd)" && pwd)/$current_git_dir"
            fi
            ux_bullet "Project hook: $current_git_dir/hooks/pre-commit"
        else
            ux_bullet "Project hook: (not in a git repository)"
        fi

        echo ""
        ux_info "Next: Try making a commit to test the hooks"
        ux_bullet "Example: echo 'test' >> README.md && git add README.md && git commit -m 'test'"
        echo ""
        return 0
    else
        ux_warning "⚠️  Some hook configurations need attention"
        echo ""

        if [ $should_run_setup -eq 1 ]; then
            ux_section "Recommended Action:"
            ux_bullet "Run: cd $DOTFILES_ROOT && ./git/setup.sh"
            echo ""

            # Ask user if they want to run setup.sh
            ux_info "Would you like to run setup.sh now to fix these issues?"
            read -p "  (y/n) [default: n]: " -r response
            echo ""

            if [[ "$response" =~ ^[Yy]$ ]]; then
                _run_setup_hooks
                return $?
            else
                ux_info "Setup skipped. Run './git/setup.sh' manually when ready."
                echo ""
                return 1
            fi
        fi

        return 1
    fi
}

# ============================================================
# Main Entry Point
# ============================================================

main() {
    if [ "${DOTFILES_ROOT:-}" = "" ]; then
        ux_error "DOTFILES_ROOT not set. Failed to initialize tools environment."
        exit 1
    fi

    run_all_checks
}

# Direct-exec guard: Only run main() if executed directly, not sourced
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
    main "$@"
fi
