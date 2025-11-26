# system_aliases.bash
# 시스템 관련 명령어에 대한 alias 정의

# 프로세스 관리
alias psg='ps aux | grep' # 프로세스 검색
alias kill9='kill -9'     # 강제 종료
alias psa='ps aux'        # 모든 프로세스 표시

# 네트워크
alias ports='ss -tulanp'                        # 열린 포트 확인: netstat은 ss로 대체되는 추세입니다. ss가 더 빠르고 상세한 정보를 제공합니다.
alias myip='curl http://ipecho.net/plain; echo' # 공인 IP 확인
alias localip='hostname -I'                     # 로컬 IP 확인
alias ping='ping -c 5'                          # ping 5회만 실행

# 시스템 모니터링
alias top='htop'              # 향상된 top 명령어 (htop 설치 필요)
alias meminfo='free -m -l -t' # 메모리 정보
alias cpuinfo='lscpu'         # CPU 정보
alias diskusage='df -h'       # 디스크 사용량

# 시스템 관리
alias update='sudo apt update'   # 패키지 목록 업데이트
alias upgrade='sudo apt upgrade' # 패키지 업그레이드
alias upgrade_all='sudo apt update && sudo apt upgrade'
alias install='sudo apt install' # 패키지 설치
alias remove='sudo apt remove'   # 패키지 제거
alias auto_remove='sudo apt autoremove'

# 로그 확인
alias logs='tail -f /var/log/syslog'     # 시스템 로그 실시간 확인
alias error='tail -f /var/log/error.log' # 에러 로그 실시간 확인
alias auth='tail -f /var/log/auth.log'   # 인증 로그 실시간 확인

# -------------------------------
# System aliases 도움말
# -------------------------------
syshelp() {
    # Color definitions
    local bold=$(tput bold 2>/dev/null || echo "")
    local blue=$(tput setaf 4 2>/dev/null || echo "")
    local green=$(tput setaf 2 2>/dev/null || echo "")
    local reset=$(tput sgr0 2>/dev/null || echo "")

    cat <<EOF

${bold}${blue}[System Management Commands]${reset}

  ${bold}${blue}Process Management:${reset}
    ${green}psg${reset}          : ps aux | grep (프로세스 검색)
    ${green}kill9${reset}        : kill -9 (강제 종료)
    ${green}psa${reset}          : ps aux (모든 프로세스 표시)

  ${bold}${blue}Network:${reset}
    ${green}ports${reset}        : ss -tulanp (열린 포트 확인)
    ${green}myip${reset}         : curl http://ipecho.net/plain (공인 IP)
    ${green}localip${reset}      : hostname -I (로컬 IP)
    ${green}ping${reset}         : ping -c 5 (5회만 실행)

  ${bold}${blue}System Monitoring:${reset}
    ${green}top${reset}          : htop (향상된 top, htop 설치 필요)
    ${green}meminfo${reset}      : free -m -l -t (메모리 정보)
    ${green}cpuinfo${reset}      : lscpu (CPU 정보)
    ${green}diskusage${reset}    : df -h (디스크 사용량)

  ${bold}${blue}Package Management:${reset}
    ${green}update${reset}       : sudo apt update
    ${green}upgrade${reset}      : sudo apt upgrade
    ${green}upgrade_all${reset}  : sudo apt update && sudo apt upgrade
    ${green}install${reset}      : sudo apt install
    ${green}remove${reset}       : sudo apt remove
    ${green}auto_remove${reset}  : sudo apt autoremove

  ${bold}${blue}Logs:${reset}
    ${green}logs${reset}         : tail -f /var/log/syslog (시스템 로그)
    ${green}error${reset}        : tail -f /var/log/error.log (에러 로그)
    ${green}auth${reset}         : tail -f /var/log/auth.log (인증 로그)

EOF
}
