#!/bin/bash

# ~/dotfiles/shell-common/tools/custom/get_hw_info.sh
# Display comprehensive hardware information

# Initialize DOTFILES_BASH_DIR using common initialization function
_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
source "$(dirname "$_SCRIPT_PATH")/../../bash/util/init.bash"
DOTFILES_BASH_DIR="$(init_dotfiles_bash_dir "$_SCRIPT_PATH")"
export DOTFILES_BASH_DIR

# Load UX library
# shellcheck source=/dev/null
source "${SHELL_COMMON}/tools/ux_lib/ux_lib.sh"

# =============================================================================
# Hardware Information Functions
# =============================================================================

show_cpu_info() {
    ux_section "🖥️  CPU Information"
    echo ""

    local cpu_model cpu_cores cpu_threads cpu_freq
    cpu_model=$(lscpu | grep "Model name:" | sed 's/Model name: *//')
    cpu_cores=$(lscpu | grep "^Core(s) per socket:" | awk '{print $4}')
    cpu_threads=$(lscpu | grep "^CPU(s):" | head -1 | awk '{print $2}')
    cpu_freq=$(lscpu | grep "^BogoMIPS:" | awk '{print $2}')

    echo "  ${UX_BOLD}Model:${UX_RESET}    $cpu_model"
    echo "  ${UX_BOLD}Cores:${UX_RESET}    $cpu_cores"
    echo "  ${UX_BOLD}Threads:${UX_RESET}  $cpu_threads"
    echo "  ${UX_BOLD}BogoMIPS:${UX_RESET} $cpu_freq"

    # Cache info
    local l1d l1i l2 l3
    l1d=$(lscpu | grep "L1d cache:" | awk '{print $3, $4}')
    l1i=$(lscpu | grep "L1i cache:" | awk '{print $3, $4}')
    l2=$(lscpu | grep "L2 cache:" | awk '{print $3, $4}')
    l3=$(lscpu | grep "L3 cache:" | awk '{print $3, $4}')

    echo ""
    echo "  ${UX_DIM}Cache:${UX_RESET}"
    echo "    L1d: $l1d"
    echo "    L1i: $l1i"
    echo "    L2:  $l2"
    echo "    L3:  $l3"
    echo ""
}

show_memory_info() {
    ux_section "💾 Memory Information"
    echo ""

    local total used free available swap_total swap_used
    read -r total used free _ _ available < <(free -h | awk 'NR==2 {print $2, $3, $4, $5, $6, $7}')
    read -r swap_total swap_used _ < <(free -h | awk 'NR==3 {print $2, $3, $4}')

    echo "  ${UX_BOLD}Total RAM:${UX_RESET}     $total"
    echo "  ${UX_BOLD}Used:${UX_RESET}          $used"
    echo "  ${UX_BOLD}Free:${UX_RESET}          $free"
    echo "  ${UX_BOLD}Available:${UX_RESET}     $available"
    echo ""
    echo "  ${UX_BOLD}Swap Total:${UX_RESET}    $swap_total"
    echo "  ${UX_BOLD}Swap Used:${UX_RESET}     $swap_used"
    echo ""
}

show_disk_info() {
    ux_section "💿 Disk Information"
    echo ""

    local filesystem size used avail use_pct
    read -r filesystem size used avail use_pct _ < <(df -h / | awk 'NR==2 {print $1, $2, $3, $4, $5, $6}')

    echo "  ${UX_BOLD}Filesystem:${UX_RESET}    $filesystem"
    echo "  ${UX_BOLD}Total Size:${UX_RESET}    $size"
    echo "  ${UX_BOLD}Used:${UX_RESET}          $used"
    echo "  ${UX_BOLD}Available:${UX_RESET}     $avail"
    echo "  ${UX_BOLD}Usage:${UX_RESET}         $use_pct"
    echo ""
}

show_gpu_info() {
    ux_section "🎮 GPU Information"
    echo ""

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

        echo "  ${UX_BOLD}Model:${UX_RESET}         $gpu_name"
        echo "  ${UX_BOLD}Driver:${UX_RESET}        $driver_version"
        echo "  ${UX_BOLD}CUDA:${UX_RESET}          $cuda_version"
        echo "  ${UX_BOLD}Compute Cap:${UX_RESET}   $compute_cap"
        echo ""
        echo "  ${UX_BOLD}VRAM Total:${UX_RESET}    ${vram_total} MiB"
        echo "  ${UX_BOLD}VRAM Used:${UX_RESET}     ${vram_used} MiB"
        echo "  ${UX_BOLD}VRAM Free:${UX_RESET}     ${vram_free} MiB"
        echo ""
        echo "  ${UX_BOLD}Temperature:${UX_RESET}   ${temp}°C"
        echo "  ${UX_BOLD}Power Usage:${UX_RESET}   ${power_usage}W / ${power_cap}W"
        echo "  ${UX_BOLD}GPU Util:${UX_RESET}      ${gpu_util}%"

        # Check for DirectX device (WSL2)
        if [ -e /dev/dxg ]; then
            echo ""
            ux_success "  WSL2 DirectX support enabled"
        fi
    else
        ux_warning "  nvidia-smi not found - No NVIDIA GPU detected"
    fi
    echo ""
}

show_system_info() {
    ux_section "⚙️  System Information"
    echo ""

    local hostname kernel arch
    hostname=$(uname -n)
    kernel=$(uname -r)
    arch=$(uname -m)

    echo "  ${UX_BOLD}Hostname:${UX_RESET}      $hostname"
    echo "  ${UX_BOLD}Kernel:${UX_RESET}        $kernel"
    echo "  ${UX_BOLD}Architecture:${UX_RESET}  $arch"

    # Check for WSL
    if grep -qi microsoft /proc/version; then
        local wsl_version
        wsl_version=$(grep -oP 'WSL\d+' /proc/version || echo "WSL")
        echo "  ${UX_BOLD}Environment:${UX_RESET}   $wsl_version (Windows Subsystem for Linux)"
    fi

    # Uptime
    local uptime_info
    uptime_info=$(uptime -p | sed 's/up //')
    echo "  ${UX_BOLD}Uptime:${UX_RESET}        $uptime_info"
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    ux_header "Hardware Information Report"
    echo ""

    show_system_info
    show_cpu_info
    show_memory_info
    show_disk_info
    show_gpu_info

    ux_section "📅 Report Generated"
    echo "  $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo ""
}

main "$@"
