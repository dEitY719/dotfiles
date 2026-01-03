#!/bin/bash
# security.sh
# 보안 관련 환경 변수 설정 (bash 사용)
#
# 환경별 CA 인증서 설정 방법:
#   1. shell-common/env/security.local.example을 security.local.sh로 복사
#   2. 환경에 맞는 CA 설정 선택 (회사 외부PC/내부PC)
#   3. security.local.sh는 자동으로 로드됨 (.gitignore에 의해 제외됨)

# SSH 에이전트 소켓
if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
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

# ========================================
# 환경별 로컬 보안 설정 로드 (CA 인증서 등)
# ========================================
_security_dir="$(dirname "${BASH_SOURCE[0]:-$0}")"
if [ -f "${_security_dir}/security.local.sh" ]; then
    . "${_security_dir}/security.local.sh"
fi
unset _security_dir
