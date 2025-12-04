#!/bin/bash
# Check UX consistency across all bash files

DOTFILES_BASH_DIR="$(dirname "$(dirname "$(realpath "$0")")")"

# shellcheck source=/dev/null
source "${DOTFILES_BASH_DIR}/core/ux_lib.bash"

ux_header "UX Consistency Checker"

# Check 1: Functions using old color definitions
ux_section "Checking for deprecated color definitions"
deprecated_patterns=(
    'bold=\$\(tput bold'
    'blue=\$\(tput setaf 4'
    'green=\$\(tput setaf 2'
    'yellow=\$\(tput setaf 3'
    'red=\$\(tput setaf 1'
    'reset=\$\(tput sgr0'
)

found_issues=0
for pattern in "${deprecated_patterns[@]}"; do
    ux_info "Searching for pattern: $pattern"
    # Search in app/ and alias/ directories, excluding current script and ux_lib itself
    if grep -r -E "$pattern" "${DOTFILES_BASH_DIR}/app" "${DOTFILES_BASH_DIR}/alias" "${DOTFILES_BASH_DIR}/coreutils" 2>/dev/null | grep -v "ux_lib.bash"; then
        ux_warning "Found deprecated pattern: $pattern"
        ((found_issues++))
    fi
done
if [ "$found_issues" -eq 0 ]; then
    ux_success "No deprecated color definitions found."
else
    ux_error "Found $found_issues issues with deprecated color definitions."
fi

# Check 2: Functions without help text (heuristic: not always accurate)
# This check is complex and can lead to false positives/negatives.
# For now, let's focus on detecting *help functions that don't call ux_header or ux_section.
ux_section "Checking for help functions missing UX formatting"
help_funcs=()
while IFS= read -r func; do
    func_name="${func%%(*}"
    if [[ "$func_name" =~ help$ ]] && [[ "$func_name" != "myhelp" ]] && [[ "$func_name" != _* ]]; then
        help_funcs+=("$func_name")
    fi
done < <(declare -F | awk '{print $3}' | { grep 'help$' || true; } | LC_ALL=C sort) # Need to load functions first to declare -F

help_format_issues=0
for hf in "${help_funcs[@]}"; do
    func_definition=$(type "$hf" 2>/dev/null)
    if ! (echo "$func_definition" | grep -q "ux_header" && echo "$func_definition" | grep -q "ux_section"); then
        ux_warning "Help function '$hf' might not be using ux_header/ux_section for formatting."
        ((help_format_issues++))
    fi
done

if [ "$help_format_issues" -eq 0 ]; then
    ux_success "All help functions appear to use UX formatting."
else
    ux_error "Found $help_format_issues help functions with potential formatting issues."
fi


# Check 3: Python scripts have execute permission
ux_section "Checking Python scripts execute permissions"
python_script_issues=0
for py_script in "${DOTFILES_BASH_DIR}/scripts/"*.py; do
    if [ -f "$py_script" ]; then
        if [ ! -x "$py_script" ]; then
            ux_warning "Python script '$py_script' is not executable. Run 'chmod +x $py_script'"
            ((python_script_issues++))
        fi
    fi
done
if [ "$python_script_issues" -eq 0 ]; then
    ux_success "All Python scripts have execute permissions."
else
    ux_error "Found $python_script_issues Python scripts without execute permissions."
fi


# Summary
echo ""
ux_divider_thick
if [ "$found_issues" -eq 0 ] && [ "$help_format_issues" -eq 0 ] && [ "$python_script_issues" -eq 0 ]; then
    ux_success "All UX consistency checks passed!"
else
    ux_error "Found $((found_issues + help_format_issues + python_script_issues)) total UX consistency issues."
fi
