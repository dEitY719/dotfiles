#!/bin/bash

# ~/dotfiles/bash/scripts/demo_ux.sh
# Interactive demo of UX library features
# This script showcases all the styling and interactive capabilities

# Get the dotfiles bash directory
SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
DOTFILES_BASH_DIR="$(dirname "$SCRIPT_DIR")"

# Load UX library
# shellcheck source=/dev/null
source "${DOTFILES_BASH_DIR}/core/ux_lib.bash"

# =============================================================================
# Demo Functions
# =============================================================================

demo_colors() {
    ux_header "Color System Demo"

    ux_section "Semantic Colors"
    echo ""
    ux_success "This is a success message (operations completed)"
    ux_error "This is an error message (operations failed)"
    ux_warning "This is a warning message (requires attention)"
    ux_info "This is an info message (helpful information)"
    echo ""

    ux_section "Text Styles"
    echo ""
    echo "  ${UX_BOLD}Bold text${UX_RESET} - for emphasis"
    echo "  ${UX_DIM}Dimmed text${UX_RESET} - for secondary info"
    echo "  ${UX_MUTED}Muted text${UX_RESET} - for hints and metadata"
    echo ""

    ux_section "Semantic Usage"
    echo ""
    echo "  ${UX_PRIMARY}Primary${UX_RESET}   - Headers, titles, command names"
    echo "  ${UX_SUCCESS}Success${UX_RESET}   - Valid states, completed tasks"
    echo "  ${UX_WARNING}Warning${UX_RESET}   - Cautions, confirmations"
    echo "  ${UX_ERROR}Error${UX_RESET}     - Failed operations, invalid input"
    echo "  ${UX_INFO}Info${UX_RESET}      - Informational messages, tips"
    echo "  ${UX_MUTED}Muted${UX_RESET}     - Secondary information, dividers"
    echo ""

    read -rp "Press Enter to continue..."
}

demo_headers() {
    ux_header "Headers and Sections Demo"

    ux_section "Main Section"
    echo "  This is content under the main section."
    echo "  Sections are used to organize information."
    echo ""

    ux_section "Another Section"
    echo "  Each section has an underline for clarity."
    echo ""

    ux_divider
    echo "  This is a regular divider (60 chars)"
    echo ""

    ux_divider_thick
    echo "  This is a thick divider (for emphasis)"
    echo ""

    read -rp "Press Enter to continue..."
}

demo_lists() {
    ux_header "Lists and Tables Demo"

    ux_section "Bullet Lists"
    ux_bullet "First item in the list"
    ux_bullet "Second item with more details"
    ux_bullet "Third item demonstrating consistency"
    echo ""

    ux_section "Numbered Lists"
    ux_numbered 1 "First step: Initialize the project"
    ux_numbered 2 "Second step: Configure settings"
    ux_numbered 3 "Third step: Run the application"
    echo ""

    ux_section "Tables (2 columns)"
    ux_table_header "Command" "Description"
    ux_table_row "git status" "Show working tree status"
    ux_table_row "git commit" "Record changes to repository"
    ux_table_row "git push" "Update remote refs"
    echo ""

    ux_section "Tables (3 columns)"
    ux_table_header "Name" "Type" "Status"
    ux_table_row "web-app" "nginx:latest" "Running"
    ux_table_row "database" "postgres:15" "Running"
    ux_table_row "cache" "redis:7" "Stopped"
    echo ""

    read -rp "Press Enter to continue..."
}

demo_progress() {
    ux_header "Progress Indicators Demo"

    ux_section "Spinner Animation"
    ux_info "Starting background task..."
    sleep 3 &
    ux_spinner $! "Loading data"
    echo ""

    ux_section "Long Operation with Spinner"
    ux_info "This will take a few seconds..."
    ux_with_spinner "Downloading files" sleep 2
    echo ""

    ux_section "Failed Operation Example"
    ux_info "Simulating a failed operation..."
    ux_with_spinner "Processing invalid data" bash -c "exit 1" || true
    echo ""

    read -rp "Press Enter to continue..."
}

demo_interactive() {
    ux_header "Interactive Features Demo"

    ux_section "Confirmation Prompts"
    if ux_confirm "Do you want to continue with the demo?" "y"; then
        ux_success "User confirmed - continuing"
    else
        ux_info "User declined - but we'll continue anyway for demo"
    fi
    echo ""

    ux_section "Default 'No' Confirmation"
    if ux_confirm "This is a destructive operation. Are you sure?" "n"; then
        ux_warning "User accepted the risk"
    else
        ux_info "User wisely declined"
    fi
    echo ""

    ux_section "Text Input with Validation"
    ux_info "Enter a name (letters only, or type 'skip' to continue):"
    if read -r response && [[ "$response" != "skip" ]]; then
        if [[ "$response" =~ ^[a-zA-Z]+$ ]]; then
            ux_success "Valid input received: $response"
        else
            ux_error "Invalid input (but we'll continue)"
        fi
    fi
    echo ""

    read -rp "Press Enter to continue..."
}

demo_usage() {
    ux_header "Usage Patterns Demo"

    ux_usage "mycommand" "<arg1> <arg2> [options]" "This is a sample command that demonstrates usage help"

    ux_section "Examples"
    echo "  ${UX_MUTED}#${UX_RESET} Basic usage"
    echo "  ${UX_INFO}mycommand foo bar${UX_RESET}"
    echo ""
    echo "  ${UX_MUTED}#${UX_RESET} With options"
    echo "  ${UX_INFO}mycommand foo bar --verbose${UX_RESET}"
    echo ""

    ux_section "Error Example"
    ux_require "nonexistent-command" "This command doesn't exist" || ux_info "As expected, the command was not found"
    echo ""

    read -rp "Press Enter to continue..."
}

demo_real_world() {
    ux_header "Real-World Example: Git Status"

    ux_section "Repository Information"
    ux_table_row "Branch" "main"
    ux_table_row "Remote" "origin"
    ux_table_row "Status" "Up to date"
    echo ""

    ux_section "Modified Files"
    ux_bullet "bash/core/ux_lib.bash ${UX_MUTED}(new file)${UX_RESET}"
    ux_bullet "bash/app/docker.bash ${UX_MUTED}(modified)${UX_RESET}"
    ux_bullet "bash/main.bash ${UX_MUTED}(modified)${UX_RESET}"
    echo ""

    ux_section "Suggestions"
    ux_step 1 "Review your changes with ${UX_BOLD}git diff${UX_RESET}"
    ux_step 2 "Stage files with ${UX_BOLD}git add${UX_RESET}"
    ux_step 3 "Commit changes with ${UX_BOLD}git commit${UX_RESET}"
    echo ""

    read -rp "Press Enter to continue..."
}

# =============================================================================
# Main Menu
# =============================================================================

show_menu() {
    clear
    ux_header "UX Library Interactive Demo"

    echo "  ${UX_PRIMARY}1.${UX_RESET} Color System"
    echo "  ${UX_PRIMARY}2.${UX_RESET} Headers and Sections"
    echo "  ${UX_PRIMARY}3.${UX_RESET} Lists and Tables"
    echo "  ${UX_PRIMARY}4.${UX_RESET} Progress Indicators"
    echo "  ${UX_PRIMARY}5.${UX_RESET} Interactive Features"
    echo "  ${UX_PRIMARY}6.${UX_RESET} Usage Patterns"
    echo "  ${UX_PRIMARY}7.${UX_RESET} Real-World Example"
    echo "  ${UX_PRIMARY}8.${UX_RESET} Run All Demos"
    echo "  ${UX_PRIMARY}0.${UX_RESET} Exit"
    echo ""
}

main() {
    while true; do
        show_menu

        read -rp "$(echo -e "${UX_WARNING}❯${UX_RESET}") Select demo: " choice

        case "$choice" in
            1) clear; demo_colors ;;
            2) clear; demo_headers ;;
            3) clear; demo_lists ;;
            4) clear; demo_progress ;;
            5) clear; demo_interactive ;;
            6) clear; demo_usage ;;
            7) clear; demo_real_world ;;
            8)
                clear
                demo_colors
                clear
                demo_headers
                clear
                demo_lists
                clear
                demo_progress
                clear
                demo_interactive
                clear
                demo_usage
                clear
                demo_real_world
                ;;
            0)
                echo ""
                ux_success "Thanks for trying the UX library!"
                ux_info "Run ${UX_BOLD}uxhelp${UX_RESET} to see all available functions"
                echo ""
                exit 0
                ;;
            *)
                clear
                ux_error "Invalid choice: $choice"
                sleep 1
                ;;
        esac
    done
}

# Run the demo
main
