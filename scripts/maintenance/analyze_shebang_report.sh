#!/bin/bash
# analyze_shebang_report.sh
# Comprehensive shebang consistency analyzer for .sh and .bash files

set -euo pipefail

# Color definitions
RED=$(tput setaf 1 2>/dev/null || echo "")
GREEN=$(tput setaf 2 2>/dev/null || echo "")
YELLOW=$(tput setaf 3 2>/dev/null || echo "")
BLUE=$(tput setaf 4 2>/dev/null || echo "")
BOLD=$(tput bold 2>/dev/null || echo "")
RESET=$(tput sgr0 2>/dev/null || echo "")

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
    local rel_path="${file#./}"

    ((stats[total]++))

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
        ((stats[bash_required]++))

        if [[ "$shebang" == "#!/bin/bash"* || "$shebang" == "#!/usr/bin/env bash"* ]]; then
            ((stats[correct]++))
            correct_files+=("$rel_path|$shebang|$reason")
        elif [[ "$shebang" == "NONE" ]]; then
            ((stats[missing_shebang]++))
            missing_shebang_files+=("$rel_path|$recommended_shebang|$reason")
        else
            ((stats[wrong_shebang]++))
            wrong_shebang_files+=("$rel_path|$shebang|$recommended_shebang|$reason")
        fi

        bash_required_files+=("$rel_path|$shebang|$bash_features|$is_exec")
    else
        # No bash-specific features
        category="POSIX_OK"
        recommended_shebang="#!/bin/sh"
        reason="POSIX-compatible, no bash features"
        ((stats[posix_ok]++))

        if [[ "$shebang" == "#!/bin/sh"* || "$shebang" == "#!/usr/bin/env sh"* ]]; then
            ((stats[correct]++))
            correct_files+=("$rel_path|$shebang|$reason")
        elif [[ "$shebang" == "NONE" ]]; then
            if [[ "$is_exec" == "no" ]]; then
                ((stats[source_only]++))
                source_only_files+=("$rel_path|optional|$reason")
            else
                ((stats[missing_shebang]++))
                missing_shebang_files+=("$rel_path|$recommended_shebang|$reason")
            fi
        elif [[ "$shebang" == "#!/bin/bash"* || "$shebang" == "#!/usr/bin/env bash"* ]]; then
            ((stats[wrong_shebang]++))
            wrong_shebang_files+=("$rel_path|$shebang|$recommended_shebang|$reason")
        else
            ((stats[correct]++))
            correct_files+=("$rel_path|$shebang|$reason")
        fi

        posix_ok_files+=("$rel_path|$shebang|$is_exec")
    fi
}

# Print section header
print_section() {
    local title="$1"
    echo ""
    echo "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${RESET}"
    echo "${BOLD}${BLUE}  $title${RESET}"
    echo "${BOLD}${BLUE}═══════════════════════════════════════════════════════════════${RESET}"
    echo ""
}

# Print statistics
print_stats() {
    print_section "STATISTICS"

    echo "${BOLD}Total files analyzed:${RESET} ${stats[total]}"
    echo ""
    echo "${BOLD}By features:${RESET}"
    echo "  ${YELLOW}Bash-required:${RESET}    ${stats[bash_required]} (need #!/bin/bash)"
    echo "  ${GREEN}POSIX-compatible:${RESET} ${stats[posix_ok]} (can use #!/bin/sh)"
    echo ""
    echo "${BOLD}By shebang status:${RESET}"
    echo "  ${GREEN}Correct shebang:${RESET}  ${stats[correct]}"
    echo "  ${RED}Wrong shebang:${RESET}    ${stats[wrong_shebang]}"
    echo "  ${YELLOW}Missing shebang:${RESET}  ${stats[missing_shebang]}"
    echo "  ${BLUE}Source-only:${RESET}      ${stats[source_only]} (shebang optional)"
}

# Print priority files (shell-common/env/ and shell-common/functions/)
print_priority_files() {
    print_section "PRIORITY FILES (shell-common/env/ and shell-common/functions/)"

    local priority_count=0

    # Check wrong shebang in priority directories
    echo "${BOLD}${RED}Files needing shebang changes:${RESET}"
    for entry in "${wrong_shebang_files[@]}"; do
        IFS='|' read -r file current recommended reason <<< "$entry"
        if [[ "$file" =~ ^shell-common/(env|functions)/ ]]; then
            ((priority_count++))
            echo ""
            echo "  ${YELLOW}File:${RESET}        $file"
            echo "  ${RED}Current:${RESET}     $current"
            echo "  ${GREEN}Recommended:${RESET} $recommended"
            echo "  ${BLUE}Reason:${RESET}      $reason"
        fi
    done

    # Check missing shebang in priority directories
    for entry in "${missing_shebang_files[@]}"; do
        IFS='|' read -r file recommended reason <<< "$entry"
        if [[ "$file" =~ ^shell-common/(env|functions)/ ]]; then
            ((priority_count++))
            echo ""
            echo "  ${YELLOW}File:${RESET}        $file"
            echo "  ${RED}Current:${RESET}     NONE"
            echo "  ${GREEN}Recommended:${RESET} $recommended"
            echo "  ${BLUE}Reason:${RESET}      $reason"
        fi
    done

    if [[ $priority_count -eq 0 ]]; then
        echo "  ${GREEN}✓ All priority files have correct shebangs!${RESET}"
    fi
}

# Print detailed findings
print_findings() {
    print_section "FILES NEEDING SHEBANG CHANGES"

    if [[ ${#wrong_shebang_files[@]} -eq 0 ]] && [[ ${#missing_shebang_files[@]} -eq 0 ]]; then
        echo "${GREEN}✓ No files need shebang changes!${RESET}"
        return
    fi

    if [[ ${#wrong_shebang_files[@]} -gt 0 ]]; then
        echo "${BOLD}${RED}Wrong Shebang (${#wrong_shebang_files[@]} files):${RESET}"
        for entry in "${wrong_shebang_files[@]}"; do
            IFS='|' read -r file current recommended reason <<< "$entry"
            echo ""
            echo "  ${YELLOW}File:${RESET}        $file"
            echo "  ${RED}Current:${RESET}     $current"
            echo "  ${GREEN}Recommended:${RESET} $recommended"
            echo "  ${BLUE}Reason:${RESET}      $reason"
        done
        echo ""
    fi

    if [[ ${#missing_shebang_files[@]} -gt 0 ]]; then
        echo "${BOLD}${YELLOW}Missing Shebang (${#missing_shebang_files[@]} files):${RESET}"
        for entry in "${missing_shebang_files[@]}"; do
            IFS='|' read -r file recommended reason <<< "$entry"
            echo ""
            echo "  ${YELLOW}File:${RESET}        $file"
            echo "  ${RED}Current:${RESET}     NONE"
            echo "  ${GREEN}Recommended:${RESET} $recommended"
            echo "  ${BLUE}Reason:${RESET}      $reason"
        done
    fi
}

# Print source-only files
print_source_only() {
    print_section "SOURCE-ONLY FILES (Shebang Optional)"

    if [[ ${#source_only_files[@]} -eq 0 ]]; then
        echo "None"
        return
    fi

    for entry in "${source_only_files[@]}"; do
        IFS='|' read -r file shebang reason <<< "$entry"
        echo "  ${BLUE}$file${RESET} - $reason"
    done
}

# Print bash-required files
print_bash_required() {
    print_section "BASH-REQUIRED FILES (${#bash_required_files[@]} files)"

    for entry in "${bash_required_files[@]}"; do
        IFS='|' read -r file shebang features is_exec <<< "$entry"
        echo ""
        echo "  ${YELLOW}File:${RESET}     $file"
        echo "  ${BLUE}Shebang:${RESET}  $shebang"
        echo "  ${GREEN}Features:${RESET} $features"
        echo "  ${BLUE}Exec:${RESET}     $is_exec"
    done
}

# Print POSIX-OK files
print_posix_ok() {
    print_section "POSIX-COMPATIBLE FILES (${#posix_ok_files[@]} files)"

    for entry in "${posix_ok_files[@]}"; do
        IFS='|' read -r file shebang is_exec <<< "$entry"
        echo "  ${GREEN}$file${RESET} - Shebang: $shebang, Exec: $is_exec"
    done
}

# Main execution
main() {
    print_section "SHEBANG CONSISTENCY ANALYSIS"

    echo "Analyzing all .sh and .bash files in /home/bwyoon/dotfiles..."
    echo ""

    # Find and analyze all files
    while IFS= read -r file; do
        analyze_file "$file"
    done < <(find /home/bwyoon/dotfiles -type f \( -name "*.sh" -o -name "*.bash" \) | sort)

    # Print results
    print_stats
    print_priority_files
    print_findings
    print_source_only

    # Optional: uncomment to see full details
    # print_bash_required
    # print_posix_ok

    print_section "SUMMARY"
    echo "Analysis complete. Check the sections above for detailed findings."
    echo ""
    echo "${BOLD}Next steps:${RESET}"
    echo "  1. Review priority files (shell-common/env/ and shell-common/functions/)"
    echo "  2. Fix wrong shebangs in bash-required files"
    echo "  3. Add shebangs to executable files missing them"
    echo "  4. Consider whether source-only files need shebangs"
    echo ""
}

main "$@"
