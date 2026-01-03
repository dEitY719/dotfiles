#!/bin/bash
# shell-common/setup.sh
# Environment-specific configuration setup for shell-common

set -e

# Get the directory where this script is located
SHELL_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

cleanup_local_files() {
    # Find all .local.sh files
    local local_files
    mapfile -t local_files < <(find "$SHELL_COMMON_DIR" -name "*.local.sh" -type f)

    if [ ${#local_files[@]} -eq 0 ]; then
        print_info "No .local.sh files found"
        return 0
    fi

    print_header "Cleaning up environment-specific files"

    # Delete all .local.sh files
    for local_file in "${local_files[@]}"; do
        rm -f "$local_file"
        print_success "Removed: ${local_file#$SHELL_COMMON_DIR/}"
    done
}

setup_local_files() {
    local environment="$1"

    # Find all .local.example files
    local local_examples
    mapfile -t local_examples < <(find "$SHELL_COMMON_DIR" -name "*.local.example" -type f)

    if [ ${#local_examples[@]} -eq 0 ]; then
        print_info "No .local.example files found"
        return 0
    fi

    print_header "Setting up environment-specific files for: $environment"

    # Copy all .local.example files to .local.sh
    for example_file in "${local_examples[@]}"; do
        local dir
        local filename
        local local_file

        dir="$(dirname "$example_file")"
        filename="$(basename "$example_file" .example)"
        local_file="${dir}/${filename%.*}.local.sh"

        # Copy the file
        cp "$example_file" "$local_file"
        print_success "Created: ${local_file#$SHELL_COMMON_DIR/}"
    done

    # Handle security.local.sh based on environment
    local security_local="${SHELL_COMMON_DIR}/env/security.local.sh"

    if [ -f "$security_local" ]; then
        case "$environment" in
            internal)
                # For internal company PC: use Option 2 (system CA bundle)
                print_info "Configuring for internal company PC (Option 2: System CA)"

                # Comment out Option 1
                sed -i 's/^CA_CERT="\/usr\/local\/share/#CA_CERT="\/usr\/local\/share/' "$security_local"

                # Uncomment Option 2
                sed -i 's/^#CA_CERT="\/etc\/ssl\/certs/CA_CERT="\/etc\/ssl\/certs/' "$security_local"

                print_success "Security config: Option 2 (System CA Bundle) activated"
                ;;
            external)
                # For external company PC: use Option 1 (custom certificate)
                print_info "Configuring for external company PC (Option 1: Custom Certificate)"

                # Uncomment Option 1 (already uncommented by default, but ensure it)
                sed -i 's/^#CA_CERT="\/usr\/local\/share/CA_CERT="\/usr\/local\/share/' "$security_local"

                # Comment out Option 2
                sed -i 's/^CA_CERT="\/etc\/ssl\/certs/#CA_CERT="\/etc\/ssl\/certs/' "$security_local"

                print_success "Security config: Option 1 (Custom Certificate) activated"
                ;;
        esac
    fi
}

# ============================================================================
# Main Menu
# ============================================================================

main() {
    echo ""
    print_header "Shell-Common Environment Setup"
    echo ""
    echo "Select your environment:"
    echo ""
    echo "1) Public PC (home environment)"
    echo "2) Internal company PC (direct connection)"
    echo "3) External company PC (VPN)"
    echo ""

    read -p "Enter your choice (1-3): " choice
    echo ""

    case "$choice" in
        1)
            print_info "Selected: Public PC"
            cleanup_local_files
            echo ""
            print_success "Setup complete for public PC (home environment)"
            print_info "All environment-specific configuration removed"
            echo ""
            ;;
        2)
            print_info "Selected: Internal company PC"
            setup_local_files "internal"
            echo ""
            print_success "Setup complete for internal company PC"
            print_info "Changes made:"
            print_info "  - Copied all .local.example files to .local.sh"
            print_info "  - Security: System CA Bundle (Option 2) activated"
            echo ""
            ;;
        3)
            print_info "Selected: External company PC"
            setup_local_files "external"
            echo ""
            print_success "Setup complete for external company PC"
            print_info "Changes made:"
            print_info "  - Copied all .local.example files to .local.sh"
            print_info "  - Security: Custom Certificate (Option 1) activated"
            print_info "  - Next: Run 'setup-crt.sh' to install the certificate"
            echo ""
            ;;
        *)
            echo -e "${YELLOW}Invalid choice. Please run again and select 1, 2, or 3.${NC}"
            exit 1
            ;;
    esac
}

main "$@"
