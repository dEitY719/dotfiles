# security.bash
# 보안 관련 환경 변수 설정

# SSH 에이전트 설정
export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"

# GPG 설정
GPG_TTY=$(tty)
export GPG_TTY
