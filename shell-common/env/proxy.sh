#!/bin/bash
# proxy.sh
# 프록시 관련 환경 변수 설정
#
# 환경별 설정 방법:
#   1. shell-common/env/proxy.local.example을 proxy.local.sh로 복사
#   2. proxy.local.sh에서 환경에 맞게 프록시 설정 수정
#   3. proxy.local.sh는 자동으로 로드됨 (.gitignore에 의해 제외됨)

# No Proxy 설정 (기본값 - 일반 가정 환경)
export no_proxy="localhost,127.0.0.1,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,.local"
export NO_PROXY="$no_proxy"

# HTTP/HTTPS 프록시 설정 (필요한 경우)
# export http_proxy="http://proxy.example.com:8080"
# export https_proxy="http://proxy.example.com:8080"
# export HTTP_PROXY="$http_proxy"
# export HTTPS_PROXY="$https_proxy"

# 환경별 로컬 프록시 설정 로드 (있는 경우)
if [ -f "${BASH_SOURCE[0]%/*}/proxy.local.sh" ]; then
    . "${BASH_SOURCE[0]%/*}/proxy.local.sh"
elif [ -f "${0:a:h}/proxy.local.sh" ]; then
    # zsh support
    . "${0:a:h}/proxy.local.sh"
fi
