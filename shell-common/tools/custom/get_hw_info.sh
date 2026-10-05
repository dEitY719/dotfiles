#!/bin/bash

# ~/dotfiles/shell-common/tools/custom/get_hw_info.sh
# Display comprehensive hardware information

# Initialize paths using unified path resolution
_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
_SCRIPT_DIR="$(dirname "$_SCRIPT_PATH")"

# Navigate from shell-common/tools/custom to DOTFILES_ROOT
SHELL_COMMON="${_SCRIPT_DIR%/tools/custom}"
export SHELL_COMMON
DOTFILES_ROOT="${SHELL_COMMON%/shell-common}"
export DOTFILES_ROOT
DOTFILES_BASH_DIR="${DOTFILES_ROOT}/bash"
export DOTFILES_BASH_DIR

# Load UX library
# shellcheck source=/dev/null
source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

# =============================================================================
# Hardware Information Functions
# =============================================================================

show_cpu_info() {
    ux_section "🖥️  CPU Information"
    ux_info ""

    local cpu_model cpu_cores cpu_threads cpu_freq
    cpu_model=$(lscpu | grep "Model name:" | sed 's/Model name: *//')
    cpu_cores=$(lscpu | grep "^Core(s) per socket:" | awk '{print $4}')
    cpu_threads=$(lscpu | grep "^CPU(s):" | head -1 | awk '{print $2}')
    cpu_freq=$(lscpu | grep "^BogoMIPS:" | awk '{print $2}')

    ux_table_row "Model" "$cpu_model"
    ux_table_row "Cores" "$cpu_cores"
    ux_table_row "Threads" "$cpu_threads"
    ux_table_row "BogoMIPS" "$cpu_freq"

    # Cache info
    local l1d l1i l2 l3
    l1d=$(lscpu | grep "L1d cache:" | awk '{print $3, $4}')
    l1i=$(lscpu | grep "L1i cache:" | awk '{print $3, $4}')
    l2=$(lscpu | grep "L2 cache:" | awk '{print $3, $4}')
    l3=$(lscpu | grep "L3 cache:" | awk '{print $3, $4}')

    ux_info ""
    ux_table_row "L1d cache" "$l1d"
    ux_table_row "L1i cache" "$l1i"
    ux_table_row "L2 cache" "$l2"
    ux_table_row "L3 cache" "$l3"
    ux_info ""
}

show_memory_info() {
    ux_section "💾 Memory Information"
    ux_info ""

    local total used free available swap_total swap_used
    read -r total used free _ _ available < <(free -h | awk 'NR==2 {print $2, $3, $4, $5, $6, $7}')
    read -r swap_total swap_used _ < <(free -h | awk 'NR==3 {print $2, $3, $4}')

    ux_table_row "Total RAM" "$total"
    ux_table_row "Used" "$used"
    ux_table_row "Free" "$free"
    ux_table_row "Available" "$available"
    ux_info ""
    ux_table_row "Swap Total" "$swap_total"
    ux_table_row "Swap Used" "$swap_used"
    ux_info ""
}

show_disk_info() {
    ux_section "💿 Disk Information"
    ux_info ""

    local filesystem size used avail use_pct
    read -r filesystem size used avail use_pct _ < <(df -h / | awk 'NR==2 {print $1, $2, $3, $4, $5, $6}')

    ux_table_row "Filesystem" "$filesystem"
    ux_table_row "Total Size" "$size"
    ux_table_row "Used" "$used"
    ux_table_row "Available" "$avail"
    ux_table_row "Usage" "$use_pct"
    ux_info ""
}

show_gpu_info() {
    ux_section "🎮 GPU Information"
    ux_info ""

    if command -v nvidia-smi &>/dev/null; then
        local gpu_name driver_version cuda_version
        local vram_total vram_used vram_free compute_cap
        local temp power_usage power_cap gpu_util

        # Get GPU info using pipe delimiter
        IFS='|' read -r gpu_name driver_version vram_total vram_free compute_cap < <(
            nvidia-smi --query-gpu=name,driver_version,memory.total,memory.free,compute_cap \
                --format=csv,noheader | sed 's/, /|/g'
        )

        # Trim whitespace
        gpu_name=$(echo "$gpu_name" | xargs)
        driver_version=$(echo "$driver_version" | xargs)
        vram_total=$(echo "$vram_total" | xargs | sed 's/ MiB//')
        vram_free=$(echo "$vram_free" | xargs | sed 's/ MiB//')
        compute_cap=$(echo "$compute_cap" | xargs)

        # Get CUDA version
        cuda_version=$(nvidia-smi | grep "CUDA Version:" | awk '{print $9}')

        # Get status info using pipe delimiter
        IFS='|' read -r temp power_usage power_cap gpu_util < <(
            nvidia-smi --query-gpu=temperature.gpu,power.draw,power.limit,utilization.gpu \
                --format=csv,noheader,nounits | sed 's/, /|/g'
        )

        # Trim whitespace
        temp=$(echo "$temp" | xargs)
        power_usage=$(echo "$power_usage" | xargs)
        power_cap=$(echo "$power_cap" | xargs)
        gpu_util=$(echo "$gpu_util" | xargs)

        # Calculate VRAM used
        vram_used=$((vram_total - vram_free))

        ux_table_row "Model" "$gpu_name"
        ux_table_row "Driver" "$driver_version"
        ux_table_row "CUDA" "$cuda_version"
        ux_table_row "Compute Cap" "$compute_cap"
        ux_info ""
        ux_table_row "VRAM Total" "${vram_total} MiB"
        ux_table_row "VRAM Used" "${vram_used} MiB"
        ux_table_row "VRAM Free" "${vram_free} MiB"
        ux_info ""
        ux_table_row "Temperature" "${temp}°C"
        ux_table_row "Power Usage" "${power_usage}W / ${power_cap}W"
        ux_table_row "GPU Util" "${gpu_util}%"

        # Check for DirectX device (WSL2)
        if [ -e /dev/dxg ]; then
            ux_info ""
            ux_success "  WSL2 DirectX support enabled"
        fi
    else
        ux_warning "  nvidia-smi not found - No NVIDIA GPU detected"
    fi
    ux_info ""
}

show_system_info() {
    ux_section "⚙️  System Information"
    ux_info ""

    local hostname kernel arch
    hostname=$(uname -n)
    kernel=$(uname -r)
    arch=$(uname -m)

    ux_table_row "Hostname" "$hostname"
    ux_table_row "Kernel" "$kernel"
    ux_table_row "Architecture" "$arch"

    # Check for WSL
    if grep -qi microsoft /proc/version; then
        local wsl_version
        wsl_version=$(grep -oP 'WSL\d+' /proc/version || echo "WSL")
        ux_table_row "Environment" "$wsl_version (Windows Subsystem for Linux)"
    fi

    # Uptime
    local uptime_info
    uptime_info=$(uptime -p | sed 's/up //')
    ux_table_row "Uptime" "$uptime_info"
    ux_info ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    ux_header "Hardware Information Report"
    ux_info ""

    show_system_info
    show_cpu_info
    show_memory_info
    show_disk_info
    show_gpu_info

    ux_section "📅 Report Generated"
    ux_info "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    ux_info ""
}

# ═══════════════════════════════════════════════════════════════
# Direct-Execution Guard
# ═══════════════════════════════════════════════════════════════
# Only run main() if this script is executed directly, not sourced
if [ "${BASH_SOURCE[0]}" = "$0" ] || [ -z "${BASH_SOURCE[0]}" ]; then
    main "$@"
fi
