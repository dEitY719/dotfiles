#!/bin/bash
# analyze_shebang_report.sh
# Comprehensive shebang consistency analyzer for .sh and .bash files

set -euo pipefail

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
. "$DOTFILES_ROOT/shell-common/tools/ux_lib/ux_lib.sh"

# Bash-specific feature patterns
declare -A BASH_FEATURES=(
    ["[[ ]]"]='(\[\[.*\]\])'
    ["BASH_SOURCE"]='BASH_SOURCE'
    ["BASH_VERSION"]='BASH_VERSION'
    ["arrays"]='(\(\(|\)\)|declare -[aA]|local -[aA]|\[[0-9]+\]=)'
    ["process_subst"]='(<\(|>\()'
    ["parameter_exp"]='(\$\{[^}]*//|\$\{[^}]*:|\$\{[^}]*\^|\$\{[^}]*,)'
    ["bashisms"]='(shopt|source\s|readarray|mapfile|declare -[gnifrlux]|local -[gnifrlux]|export -f)'
    ["regex_match"]='(=~)'
    ["{1..n}"]='(\{[0-9]+\.\.[0-9]+\})'
)

# Track statistics
declare -A stats
stats[total]=0
stats[bash_required]=0
stats[posix_ok]=0
stats[source_only]=0
stats[wrong_shebang]=0
stats[missing_shebang]=0
stats[correct]=0

# Arrays for different categories
declare -a bash_required_files=()
declare -a posix_ok_files=()
declare -a source_only_files=()
declare -a wrong_shebang_files=()
declare -a missing_shebang_files=()
declare -a correct_files=()

# Function to detect bash-specific features
detect_bash_features() {
    local file="$1"
    local features_found=()

    for feature_name in "${!BASH_FEATURES[@]}"; do
        pattern="${BASH_FEATURES[$feature_name]}"
        if grep -qE "$pattern" "$file" 2>/dev/null; then
            features_found+=("$feature_name")
        fi
    done

    printf '%s' "${features_found[*]}"
}

# Function to get current shebang
get_shebang() {
    local file="$1"
    local first_line
    first_line=$(head -n1 "$file" 2>/dev/null || echo "")

    if [[ "$first_line" =~ ^#! ]]; then
        echo "$first_line"
    else
        echo "NONE"
    fi
}

# Function to check if file is executable
is_executable() {
    local file="$1"
    [[ -x "$file" ]]
}

# Analyze a single file
analyze_file() {
    local file="$1"
    local rel_path="${file#"$DOTFILES_ROOT"/}"

    ((++stats[total]))

    local shebang=$(get_shebang "$file")
    local bash_features=$(detect_bash_features "$file")
    local is_exec=$(is_executable "$file" && echo "yes" || echo "no")

    # Determine category
    local category=""
    local recommended_shebang=""
    local reason=""

    if [[ -n "$bash_features" ]]; then
        # Bash-specific features detected
        category="BASH_REQUIRED"
        recommended_shebang="#!/bin/bash"
        reason="Uses: $bash_features"
        ((++stats[bash_required]))

        if [[ "$shebang" == "#!/bin/bash"* || "$shebang" == "#!/usr/bin/env bash"* ]]; then
            ((++stats[correct]))
            correct_files+=("$rel_path|$shebang|$reason")
        elif [[ "$shebang" == "NONE" ]]; then
            ((++stats[missing_shebang]))
            missing_shebang_files+=("$rel_path|$recommended_shebang|$reason")
        else
            ((++stats[wrong_shebang]))
            wrong_shebang_files+=("$rel_path|$shebang|$recommended_shebang|$reason")
        fi

        bash_required_files+=("$rel_path|$shebang|$bash_features|$is_exec")
    else
        # No bash-specific features
        category="POSIX_OK"
        recommended_shebang="#!/bin/sh"
        reason="POSIX-compatible, no bash features"
        ((++stats[posix_ok]))

        if [[ "$shebang" == "#!/bin/sh"* || "$shebang" == "#!/usr/bin/env sh"* ]]; then
            ((++stats[correct]))
            correct_files+=("$rel_path|$shebang|$reason")
        elif [[ "$shebang" == "NONE" ]]; then
            if [[ "$is_exec" == "no" ]]; then
                ((++stats[source_only]))
                source_only_files+=("$rel_path|optional|$reason")
            else
                ((++stats[missing_shebang]))
                missing_shebang_files+=("$rel_path|$recommended_shebang|$reason")
            fi
        elif [[ "$shebang" == "#!/bin/bash"* || "$shebang" == "#!/usr/bin/env bash"* ]]; then
            ((++stats[wrong_shebang]))
            wrong_shebang_files+=("$rel_path|$shebang|$recommended_shebang|$reason")
        else
            ((++stats[correct]))
            correct_files+=("$rel_path|$shebang|$reason")
        fi

        posix_ok_files+=("$rel_path|$shebang|$is_exec")
    fi
}

# Print one file entry: file, current shebang, recommended shebang, reason
print_entry() {
    ux_bullet "$1"
    ux_table_row "Current" "$2"
    ux_table_row "Recommended" "$3"
    ux_table_row "Reason" "$4"
}

# Print statistics
print_stats() {
    ux_header "STATISTICS"

    ux_table_row "Total files" "${stats[total]}"
    ux_section "By features"
    ux_table_row "Bash-required" "${stats[bash_required]} (need #!/bin/bash)"
    ux_table_row "POSIX-compatible" "${stats[posix_ok]} (can use #!/bin/sh)"
    ux_section "By shebang status"
    ux_table_row "Correct shebang" "${stats[correct]}"
    ux_table_row "Wrong shebang" "${stats[wrong_shebang]}"
    ux_table_row "Missing shebang" "${stats[missing_shebang]}"
    ux_table_row "Source-only" "${stats[source_only]} (shebang optional)"
}

# Print priority files (shell-common/env/ and shell-common/functions/)
print_priority_files() {
    ux_header "PRIORITY FILES (shell-common/env/ and shell-common/functions/)"

    local priority_count=0

    ux_section "Files needing shebang changes"
    for entry in "${wrong_shebang_files[@]}"; do
        IFS='|' read -r file current recommended reason <<< "$entry"
        if [[ "$file" =~ ^shell-common/(env|functions)/ ]]; then
            ((++priority_count))
            print_entry "$file" "$current" "$recommended" "$reason"
        fi
    done

    for entry in "${missing_shebang_files[@]}"; do
        IFS='|' read -r file recommended reason <<< "$entry"
        if [[ "$file" =~ ^shell-common/(env|functions)/ ]]; then
            ((++priority_count))
            print_entry "$file" "NONE" "$recommended" "$reason"
        fi
    done

    if [[ $priority_count -eq 0 ]]; then
        ux_success "All priority files have correct shebangs!"
    fi
}

# Print detailed findings
print_findings() {
    ux_header "FILES NEEDING SHEBANG CHANGES"

    if [[ ${#wrong_shebang_files[@]} -eq 0 ]] && [[ ${#missing_shebang_files[@]} -eq 0 ]]; then
        ux_success "No files need shebang changes!"
        return
    fi

    if [[ ${#wrong_shebang_files[@]} -gt 0 ]]; then
        ux_section "Wrong Shebang (${#wrong_shebang_files[@]} files)"
        for entry in "${wrong_shebang_files[@]}"; do
            IFS='|' read -r file current recommended reason <<< "$entry"
            print_entry "$file" "$current" "$recommended" "$reason"
        done
    fi

    if [[ ${#missing_shebang_files[@]} -gt 0 ]]; then
        ux_section "Missing Shebang (${#missing_shebang_files[@]} files)"
        for entry in "${missing_shebang_files[@]}"; do
            IFS='|' read -r file recommended reason <<< "$entry"
            print_entry "$file" "NONE" "$recommended" "$reason"
        done
    fi
}

# Print source-only files
print_source_only() {
    ux_header "SOURCE-ONLY FILES (Shebang Optional)"

    if [[ ${#source_only_files[@]} -eq 0 ]]; then
        ux_info "None"
        return
    fi

    for entry in "${source_only_files[@]}"; do
        IFS='|' read -r file shebang reason <<< "$entry"
        ux_bullet "$file - $reason"
    done
}

# Print bash-required files
print_bash_required() {
    ux_header "BASH-REQUIRED FILES (${#bash_required_files[@]} files)"

    for entry in "${bash_required_files[@]}"; do
        IFS='|' read -r file shebang features is_exec <<< "$entry"
        ux_bullet "$file"
        ux_table_row "Shebang" "$shebang"
        ux_table_row "Features" "$features"
        ux_table_row "Exec" "$is_exec"
    done
}

# Print POSIX-OK files
print_posix_ok() {
    ux_header "POSIX-COMPATIBLE FILES (${#posix_ok_files[@]} files)"

    for entry in "${posix_ok_files[@]}"; do
        IFS='|' read -r file shebang is_exec <<< "$entry"
        ux_bullet "$file - Shebang: $shebang, Exec: $is_exec"
    done
}

# Main execution
main() {
    ux_header "SHEBANG CONSISTENCY ANALYSIS"

    ux_info "Analyzing all .sh and .bash files in $DOTFILES_ROOT..."

    # Find and analyze all files
    while IFS= read -r file; do
        analyze_file "$file"
    done < <(find "$DOTFILES_ROOT" -type f \( -name "*.sh" -o -name "*.bash" \) | sort)

    # Print results
    print_stats
    print_priority_files
    print_findings
    print_source_only

    # Optional: uncomment to see full details
    # print_bash_required
    # print_posix_ok

    ux_header "SUMMARY"
    ux_info "Analysis complete. Check the sections above for detailed findings."
    ux_section "Next steps"
    ux_numbered 1 "Review priority files (shell-common/env/ and shell-common/functions/)"
    ux_numbered 2 "Fix wrong shebangs in bash-required files"
    ux_numbered 3 "Add shebangs to executable files missing them"
    ux_numbered 4 "Consider whether source-only files need shebangs"
}

main "$@"
