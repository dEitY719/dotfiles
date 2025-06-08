#!/bin/bash

# ~/dotfiles/bash/util/log_util.bash
# --- ANSI Color Codes ---
RESET='\033[0m'
CBold='\033[1m'
CDim='\033[2m'
CItalic='\033[3m'
CUnderline='\033[4m'
CBlink='\033[5m'
CInvert='\033[7m'
CHidden='\033[8m'
CBlack='\033[0;30m'
CRed='\033[0;31m'
CGreen='\033[0;32m'
CYellow='\033[0;33m'
CBlue='\033[0;34m'
CMagenta='\033[0;35m'
CCyan='\033[0;36m'
CWhite='\033[0;37m'
CLightGray='\033[0;37m' # Alias for white
CLBlack='\033[1;30m' # Bold Black
CLRed='\033[1;31m'
CLGreen='\033[1;32m'
CLYellow='\033[1;33m'
CLBlue='\033[1;34m'
CLMagenta='\033[1;35m'
CLCyan='\033[1;36m'
CLWhite='\033[1;37m' # Bold White
# Background Colors
CBGBlack='\033[40m'
CBGRed='\033[41m'
CBGGreen='\033[42m'
CBGYellow='\033[43m'
CBGBlue='\033[44m'
CBGMagenta='\033[45m'
CBGCyan='\033[46m'
CBGWhite='\033[47m'
# --- General purpose colored echo ---

# Usage: cecho <color_code> "Your message"
cecho() {
    local color="$1"
    shift
    echo -e "${color}$*${RESET}"
}


# --- Log level functions ---
log_critical() {
    cecho "${CLMagenta}" "$*"
}
log_error() {
    cecho "${CLRed}" "$*"
}
log_warning() {
    cecho "${CLYellow}" "$*"
}
log_info() {
    cecho "${CGreen}" "$*"
}
log_debug() {
    cecho "${CWhite}" "$*"
}


# --- Alias for some colors ---
log_reset()       { cecho "${RESET}" "$*"; }
log_bold()        { cecho "${CBold}" "$*"; }
log_dim()         { cecho "${CDim}" "$*"; }
log_italic()      { cecho "${CItalic}" "$*"; }
log_underline()   { cecho "${CUnderline}" "$*"; }
log_blink()       { cecho "${CBlink}" "$*"; }
log_invert()      { cecho "${CInvert}" "$*"; }
log_hidden()      { cecho "${CHidden}" "$*"; }

log_black()       { cecho "${CBlack}" "$*"; }
log_red()         { cecho "${CRed}" "$*"; }
log_green()       { cecho "${CGreen}" "$*"; }
log_yellow()      { cecho "${CYellow}" "$*"; }
log_blue()        { cecho "${CBlue}" "$*"; }
log_magenta()     { cecho "${CMagenta}" "$*"; }
log_cyan()        { cecho "${CCyan}" "$*"; }
log_white()       { cecho "${CWhite}" "$*"; }
log_light_gray()  { cecho "${CLightGray}" "$*"; }

log_lblack()      { cecho "${CLBlack}" "$*"; }
log_lred()        { cecho "${CLRed}" "$*"; }
log_lgreen()      { cecho "${CLGreen}" "$*"; }
log_lyellow()     { cecho "${CLYellow}" "$*"; }
log_lblue()       { cecho "${CLBlue}" "$*"; }
log_lmagenta()    { cecho "${CLMagenta}" "$*"; }
log_lcyan()       { cecho "${CLCyan}" "$*"; }
log_lwhite()      { cecho "${CLWhite}" "$*"; }

# 배경 색상
log_bg_black()    { cecho "${CBGBlack}" "$*"; }
log_bg_red()      { cecho "${CBGRed}" "$*"; }
log_bg_green()    { cecho "${CBGGreen}" "$*"; }
log_bg_yellow()   { cecho "${CBGYellow}" "$*"; }
log_bg_blue()     { cecho "${CBGBlue}" "$*"; }
log_bg_magenta()  { cecho "${CBGMagenta}" "$*"; }
log_bg_cyan()     { cecho "${CBGCyan}" "$*"; }
log_bg_white()    { cecho "${CBGWhite}" "$*"; }


# --- log() function with color parsing ---
log() {
    local input="$*"
    local output=""
    local color=""
    local text=""
    local match=""
    local before=""
    local color_code=""
    local pattern='([A-Za-z]+)\(([^)]*)\)'

    while [[ "$input" =~ $pattern ]]; do
        match="${BASH_REMATCH[0]}"
        color="${BASH_REMATCH[1]}"
        text="${BASH_REMATCH[2]}"
        before="${input%%"$match"*}"
        color_code="${!color}"

        if [[ -n "$color_code" ]]; then
            output+="${before}${color_code}${text}${RESET}"
        else
            output+="${before}${match}"
        fi
        input="${input#*"$match"}"
    done

    output+="$input"
    echo -e "$output"
}

# --- Custom print example ---

print_bash_config_loaded() {
    log_dim "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "CGreen(✔️  Bash config loaded:) CInvert(~/.bash_main) CRed(👈 technologya~ 😁)"
    log "CMagenta(¯＼_〔ツ〕_／¯ Everything looks good!)"
    log_dim "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
}


# Uncomment below to run the example when sourcing or running script
print_test_log_methods() {
    log "RESET(Default color reset)"
    log "CBold(Bold text)"
    log "CDim(Dim text)"
    log "CItalic(Italic text)"
    log "CUnderline(Underline text)"
    log "CBlink(Blinking text)"
    log "CInvert(Inverted text)"
    log "CHidden(Hidden text)"
    log "CBlack(Black text)"
    log "CRed(Red text)"
    log "CGreen(Green text)"
    log "CYellow(Yellow text)"
    log "CBlue(Blue text)"
    log "CMagenta(Magenta text)"
    log "CCyan(Cyan text)"
    log "CWhite(White text)"
    log "CLightGray(Light gray text)"
    log "CLBlack(Bold black text)"
    log "CLRed(Bold red text)"
    log "CLGreen(Bold green text)"
    log "CLYellow(Bold yellow text)"
    log "CLBlue(Bold blue text)"
    log "CLMagenta(Bold magenta text)"
    log "CLCyan(Bold cyan text)"
    log "CLWhite(Bold white text)"
    log "CBGBlack(Background black)"
    log "CBGRed(Background red)"
    log "CBGGreen(Background green)"
    log "CBGYellow(Background yellow)"
    log "CBGBlue(Background blue)"
    log "CBGMagenta(Background magenta)"
    log "CBGCyan(Background cyan)"
    log "CBGWhite(Background white)"
    log_dim "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    log_critical "Critical issue occurred!"
    log_error "Error detected during processing."
    log_warning "Warning: Check your inputs."
    log_info "Information: Process started."
    log_debug "Debugging details here."
    log_dim "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    log "CDim(This is dim text)"
    log "CUnderline(This is underlined text)"
    log "CInvert(This is inverted color text)"
    log "CHidden(This text is hidden (you won't see me))"
    log "CBlink(This text is blinking (if supported))"
    log "${CBlink}This should blink${RESET}"
    log "CReset(This resets the color and style)"
}

# print_test_log_methods

# --- Spinner animation ---
log_spinner() {
    : "
    Usage:
    log_spinner <pid> [style] [message]

    Examples:
    $ sleep 3 & pid=$! && log_spinner '$pid' dots 'Installing...'
    [1] 1131789
    Processing... [⠏][1]+  Done                    sleep 5
    Processing... [DONE]
    "

    local pid=$1
    local style=$2
    local message=$3

    # spinstr 맵 정의 (bash version 4 이상 필요)
    declare -A spinner_styles=(
        ["dots"]='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        ["minimal"]='⠁⠂⠄⠂'
        ["arrow"]="←↑→↓"
        ["star"]="✶✸✹✺✹✷"
        ["circle"]="◐◓◑◒◐◓◑◒"
        ["line"]='⎺⎻⎼⎽'
        ["line2"]="|/-\\"
        ["clock"]='🕛🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚'
    )

    local spinstr="${spinner_styles[$style]}"
    if [[ -z "$spinstr" ]]; then
        spinstr="${spinner_styles["dots"]}" # 기본값
    fi

    local delay=0.1
    local i=0
    local length=${#spinstr}

    tput civis
    while kill -0 "$pid" 2>/dev/null; do
        local char="${spinstr:i%length:1}"
        echo -en "${message} ${CLCyan}[${char}]${RESET}\r"
        sleep "$delay"
        ((i++))
    done

    tput cnorm
    echo -e "${message} ${CLGreen}[DONE]${RESET}"
}


log_spinner_demo() {
    log_info "Demo started: log_spinner"
    sleep 3 &
    pid=$! && log_spinner "$pid" dots "Installing..."
}


# --- Progress bar ---
log_progress_bar() {
    local progress=$1
    local width=40
    local filled=$((progress * width / 100))
    local empty=$((width - filled))
    local bar=""

    for ((i = 0; i < filled; i++)); do
        bar+="█"
    done

    # 100%일 땐 empty도 채움
    if ((progress == 100)); then
        empty=0
    fi

    for ((i = 0; i < empty; i++)); do
        bar+="-"
    done

    echo -ne "[$bar] $progress%\r"
    if ((progress == 100)); then
        echo -ne '\n'
    fi
}


log_progress_bar_demo() {
    log_info "Demo started: log_progress_bar"
    for i in $(seq 0 10 100); do
        log_progress_bar "$i"
        sleep 0.1
    done
}


_SPINNER_PID=""
_SPINNER_MSG=""
_SPINNER_CHARS=("-" "\\" "|" "/") # 스피너 모양 정의


# 스피너를 백그라운드에서 시작하는 함수
log_progress_start() {
    _SPINNER_MSG="${1:-Processing...}" # 메시지 인자를 받음
    (
        trap "exit 0" SIGTERM # 종료 신호 시 깔끔하게 종료
        i=0
        while :; do
            printf "\r[INFO] %s %s" "${_SPINNER_CHARS[$i]}" "${_SPINNER_MSG}"
            i=$(((i + 1) % ${#_SPINNER_CHARS[@]}))
            sleep 0.1
        done
    ) &
    _SPINNER_PID=$! # 백그라운드 프로세스의 PID 저장
}


# 스피너를 중지하고 메시지를 깔끔하게 지우는 함수
log_progress_stop() {
    if [[ -n "${_SPINNER_PID}" ]]; then
        kill -SIGTERM "${_SPINNER_PID}" 2>/dev/null               # 스피너 프로세스 종료
        wait "${_SPINNER_PID}" 2>/dev/null                        # 스피너 프로세스가 완전히 종료될 때까지 대기 (필요시)
        printf "\r%s\r" "$(printf ' %.0s' "$(seq 1 "$(tput cols)")")" # 현재 줄 깔끔하게 지우기
        _SPINNER_PID=""
    fi
    # 최종 메시지는 log_info로 출력
    log_dim "$1"
}
