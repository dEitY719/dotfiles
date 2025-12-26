# security.bash
# 보안 관련 환경 변수 설정 (비대화 환경에서도 안전)

# 대화형이 아닌 경우엔 조용히 빠르게 리턴 (선택)
# [[ $- != *i* ]] && return 0

# SSH 에이전트 소켓
if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    # 이중 슬래시 방지: ${var%/}는 끝 슬래시 제거
    export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR%/}/ssh-agent.socket"
else
    # fallback (systemd 런타임 디렉터리 관례)
    uid="$(id -u)"
    export SSH_AUTH_SOCK="/run/user/${uid}/ssh-agent.socket"
fi

# GPG TTY 설정: TTY가 있을 때만
if tty >/dev/null 2>&1; then
    GPG_TTY="$(tty)"
    export GPG_TTY
fi

# Node.js/NPM CA 인증서 설정 (회사 내부 프록시용)
# 파일이 존재할 때만 설정하여 집 WSL 환경과 호환성 유지
COMPANY_CA_CERT="/usr/local/share/ca-certificates/samsungsemi-prx.com.crt"
if [ -f "$COMPANY_CA_CERT" ]; then
    export NODE_EXTRA_CA_CERTS="$COMPANY_CA_CERT"
fi
