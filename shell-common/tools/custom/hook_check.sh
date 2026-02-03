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

    local has_error=0

    # Check pre-commit hook
    local pre_commit_hook="$expanded_hooks_path/pre-commit"
    if [ -f "$pre_commit_hook" ]; then
        _format_check "~/.config/git/hooks/pre-commit" "✓" "Exists"
    else
        _format_check "~/.config/git/hooks/pre-commit" "✗" "Missing"
        has_error=1
    fi

    # Check if it's a symlink
    if [ -L "$pre_commit_hook" ]; then
        local target
        target=$(readlink -f "$pre_commit_hook" 2>/dev/null || readlink "$pre_commit_hook")
        ux_bullet "Symlink target: $target"
    fi

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

    local hooks_path
    hooks_path=$(git config --global core.hooksPath 2>/dev/null)
    local expanded_hooks_path="${hooks_path/#\~/$HOME}"

    local pre_commit_hook="$expanded_hooks_path/pre-commit"

    if [ ! -f "$pre_commit_hook" ]; then
        ux_warning "Hook file not found, skipping permission check"
        echo ""
        return 0
    fi

    # Check if executable
    if [ -x "$pre_commit_hook" ]; then
        _format_check "Executable Permission" "✓" "Yes ($(stat -c '%A' "$pre_commit_hook" 2>/dev/null || stat -f '%A' "$pre_commit_hook" 2>/dev/null))"
        echo ""
        return 0
    else
        _format_check "Executable Permission" "✗" "No ($(stat -c '%A' "$pre_commit_hook" 2>/dev/null || stat -f '%A' "$pre_commit_hook" 2>/dev/null))"
        echo ""
        ux_error "Hook file is not executable"
        ux_section "Solution:"
        ux_bullet "Run: chmod +x $pre_commit_hook"
        echo ""
        return 1
    fi
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

    local hooks_path
    hooks_path=$(git config --global core.hooksPath 2>/dev/null)
    local expanded_hooks_path="${hooks_path/#\~/$HOME}"
    local pre_commit_hook="$expanded_hooks_path/pre-commit"

    if [ ! -f "$pre_commit_hook" ]; then
        ux_warning "Hook file not found, skipping execution test"
        echo ""
        return 0
    fi

    ux_info "Running hook in dry-run mode (no changes to git index)..."
    echo ""

    # Try to source the hook to check for syntax errors
    if bash -n "$pre_commit_hook" 2>/dev/null; then
        ux_success "Hook syntax is valid"
        echo ""
    else
        ux_error "Hook has syntax errors"
        echo ""
        ux_section "Debug Info:"
        bash -n "$pre_commit_hook" 2>&1 | head -20 | sed 's/^/    /'
        echo ""
        return 1
    fi

    echo ""
    return 0
}

# ============================================================
# Main Diagnostic Flow
# ============================================================

run_all_checks() {
    ux_header "🔍 Git Hook Configuration Diagnostic"

    local all_passed=0
    local should_run_setup=0

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
        ux_bullet "Global hook: ~/.config/git/hooks/pre-commit"

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
