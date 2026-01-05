#!/bin/bash
# shell-common/tools/external/cp_wdown.sh
# Copy files from Windows "Downloads" to WSL ~/downloads with robust path resolution
# Bash-specific due to use of: local -a, (()), mapfile, compgen

# Guard: only load in bash (tools/external is sourced in both bash and zsh)
[ -n "$BASH_VERSION" ] || return 0

cp_wdown() {
    # ✅ getopts initialization: prevent OPTIND state from previous calls
    local OPTIND=1

    local dest="$HOME/downloads"
    local src="" recursive=0 force=0 verbose=0 dryrun=0

    # Handle --help directly (optional)
    if [ "${1-}" = "--help" ]; then
        set -- -h
    fi

    while getopts ":d:s:nrvfh" opt; do
        case "$opt" in
        d) dest="$OPTARG" ;;
        s) src="$OPTARG" ;;
        n) dryrun=1 ;;
        r) recursive=1 ;;
        f) force=1 ;;
        v) verbose=1 ;;
        h)
            cat <<'EOF'
Usage: cp_wdown [options] <file1> [file2] ...

Copies files from Windows Downloads folder to WSL destination.
Default destination: ~/downloads

Options:
  -d <dest>   Destination folder (default: ~/downloads)
  -s <src>    Source folder (default: Windows "Downloads")
  -r          Recursive copy (for directories)
  -f          Force overwrite (no prompt)
  -v          Verbose output
  -n          Dry-run (show commands, do not copy)
  -h          Show this help

Examples:
  # Copy specific file from Windows Downloads
  cp_wdown report.pdf         # Works without quotes
  cp_wdown "report.pdf"       # Safe with quotes

  # File names with spaces
  cp_wdown "invoice March.pdf"

  # Pattern matching (must be quoted!)
  cp_wdown "*.deb"
  cp_wdown "*.zip"

  # Multiple files
  cp_wdown report.pdf plan.xlsx

  # Copy directory recursively
  cp_wdown -r "project_folder"

  # Force overwrite existing files
  cp_wdown -f "*.iso"

  # Change destination folder
  cp_wdown -d ~/backup "*.mp4"

  # Specify source folder directly (e.g., Windows Desktop)
  cp_wdown -s "/mnt/c/Users/<name>/Desktop" "*.pptx"

  # Simulation mode (preview what will be copied)
  cp_wdown -n -v "*.tar.gz"

Notes:
- Patterns (*.zip, *.deb, etc.) MUST be quoted
  (Otherwise they expand in current WSL directory and fail to match)
- Regular filenames work without quotes
  (But MUST be quoted if they contain spaces or special characters)
EOF
            return 0
            ;;
        \?)
            ux_error "Unknown option: -$OPTARG"
            return 1
            ;;
        :)
            ux_error "Option -$OPTARG requires an argument"
            return 1
            ;;
        esac
    done
    shift $((OPTIND - 1))

    if [ "$#" -lt 1 ]; then
        ux_usage "cp_wdown" "<file1> [file2] ..." "Copy files from Windows Downloads to WSL"
        ux_info "Use -h for help"
        return 1
    fi

    # --- Get Windows Downloads path (robust) ---
    if [ -z "$src" ]; then
        local ps_cmd="(New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path"
        local win_downloads=""

        # 1) pwsh.exe
        if command -v pwsh.exe >/dev/null 2>&1; then
            win_downloads=$(pwsh.exe -NoProfile -Command "$ps_cmd" 2>/dev/null | tr -d '\r')
        fi

        # 2) powershell.exe
        if [ -z "$win_downloads" ] && command -v powershell.exe >/dev/null 2>&1; then
            win_downloads=$(powershell.exe -NoProfile -Command "$ps_cmd" 2>/dev/null | tr -d '\r')
        fi

        # 3) cmd.exe USERPROFILE\Downloads
        if [ -z "$win_downloads" ] && command -v cmd.exe >/dev/null 2>&1; then
            local userprofile
            userprofile=$(cmd.exe /C "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')
            if [ -n "$userprofile" ]; then
                win_downloads="${userprofile}\\Downloads"
            fi
        fi

        if [ -z "$win_downloads" ]; then
            ux_error "Failed to locate Windows Downloads path"
            ux_info "Make sure pwsh.exe/powershell.exe or cmd.exe is available"
            return 1
        fi

        # Convert Windows path to WSL
        src=$(wslpath -u "$win_downloads") || {
            ux_error "wslpath conversion failed for: $win_downloads"
            return 1
        }
    fi

    mkdir -p "$dest" || {
        ux_error "Cannot create destination: $dest"
        return 1
    }

    local -a cp_opts=()
    ((recursive)) && cp_opts+=(-r)
    if ((force)); then cp_opts+=(-f); else cp_opts+=(-i); fi
    ((verbose)) && cp_opts+=(-v)

    ((verbose)) && {
        ux_info "Source (Windows): $src"
        ux_info "Destination     : $dest"
    }

    local any_copied=0
    for arg in "$@"; do
        local pattern="$src/$arg"
        mapfile -t matches < <(compgen -G "$pattern")
        if [ "${#matches[@]}" -eq 0 ]; then
            ux_warning "No match: $pattern"
            continue
        fi
        for m in "${matches[@]}"; do
            if ((dryrun)); then
                echo cp "${cp_opts[@]}" -- "$m" "$dest/"
            else
                cp "${cp_opts[@]}" -- "$m" "$dest/" && any_copied=1
            fi
        done
    done

    if ((dryrun)); then
        ux_info "[dry-run] No files were actually copied"
    elif ((any_copied)); then
        ((verbose)) && ux_success "Done"
    else
        ux_warning "Nothing copied"
        return 1
    fi
}

# Only execute if run directly (not sourced)
if [ "${0##*/}" = "cp_wdown.sh" ]; then
    cp_wdown "$@"
fi
