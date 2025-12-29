#!/bin/sh
# shell-common/aliases/directory.sh
# Shared directory navigation aliases for bash and zsh

# BASIC
alias cd_dot='cd ~/dotfiles'
alias cd_down='cd ~/downloads'
alias cd_work='cd ~/workspace'

# Windows directory paths (WSL)
alias cd_wdocu='cd /mnt/c/Users/bwyoon/Documents'
alias cd_wobsidian='cd /mnt/c/Users/bwyoon/Documents/.obsidian'
alias cd_wdown='cd /mnt/c/Users/bwyoon/Downloads'
alias cd_wpicture='cd /mnt/c/Users/bwyoon/Pictures'
alias cd_tilnote='cd /mnt/c/Users/bwyoon/Documents/ObsidianVault-TilNote'
alias cd_obsidian='cd /mnt/c/Users/bwyoon/Documents/ObsidianVault-TilNote'

# PARA structure
alias mkpara='mkdir -p para/{archive,area,project,resource}'
alias cd_para='cd ~/para'

# PROJECT directories
alias cd_proj='cd ~/para/project'
alias cd_area='cd ~/para/area'
alias cd_resource='cd ~/para/resource'
alias cd_archive='cd ~/para/archive'

# Copy from Windows "Downloads" to WSL ~/downloads (robust path resolution)
cp_wdown() {
    # ✅ getopts 초기화: 이전 호출의 OPTIND 상태가 남지 않도록
    local OPTIND=1

    local dest="$HOME/downloads"
    local src="" recursive=0 force=0 verbose=0 dryrun=0

    # --help 직접 처리(선택)
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
  # 윈도우 Downloads의 특정 파일 복사
  cp_wdown report.pdf         # 따옴표 없어도 OK
  cp_wdown "report.pdf"       # 안전하게 감싸도 OK

  # 공백이 있는 파일명
  cp_wdown "invoice March.pdf"

  # 패턴 매칭 (반드시 따옴표로 감싸야 함!)
  cp_wdown "*.deb"
  cp_wdown "*.zip"

  # 여러 개 파일 복사
  cp_wdown report.pdf plan.xlsx

  # 디렉토리 통째로 복사 (재귀 옵션)
  cp_wdown -r "project_folder"

  # 강제 덮어쓰기 (기존 파일 덮어씀)
  cp_wdown -f "*.iso"

  # 목적지 폴더를 바꾸기
  cp_wdown -d ~/backup "*.mp4"

  # 소스 폴더를 직접 지정 (예: 윈도우 Desktop)
  cp_wdown -s "/mnt/c/Users/<name>/Desktop" "*.pptx"

  # 시뮬레이션 모드 (무엇이 복사될지 미리 확인)
  cp_wdown -n -v "*.tar.gz"

Notes:
- 패턴 (*.zip, *.deb 등) 은 반드시 따옴표로 감싸야 합니다.
  (안 그러면 현재 WSL 디렉터리에서 확장되어 매칭 실패합니다.)
- 일반 파일 이름은 따옴표 없이도 동작합니다.
  (단, 공백이나 특수문자가 있으면 반드시 따옴표로 감싸야 합니다.)
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

    # --- Windows Downloads 경로 얻기 (robust) ---
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

        # Windows → WSL 경로로 변환
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
