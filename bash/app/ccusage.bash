#!/usr/bin/env bash
# bash/app/ccusage.bash  (정리판)
# Claude Code Usage (ccusage) 보조 스크립트
# - 설치 방법/환경 설정
# - 자주 쓰는 명령어 alias
# - 도움말 함수

# ── 설치 방법 ─────────────────────────────────────────────────
# 전역 prefix를 사용자 홈으로 지정하여 설치 (권장)
# 1) 설치
#    npm install -g ccusage --prefix=$HOME/.npm-global
# 2) PATH 반영 (필요 시)
#    export PATH="$HOME/.npm-global/bin:$PATH"
#
# 설치 확인:
#    which ccusage && ccusage --version

# ── 환경 보조: PATH 보정용 옵션 함수 ──────────────────────────
ccusage_path_hint() {
  case ":$PATH:" in
    *":$HOME/.npm-global/bin:"*) ;;
    *) echo '참고: PATH에 $HOME/.npm-global/bin 이 없다면 아래를 실행하세요:'
       echo '  export PATH="$HOME/.npm-global/bin:$PATH"'
       ;;
  esac
}

# ── 필수 명령어 alias (3개) ───────────────────────────────────
# 모델별 소비 내역
alias ccd='ccusage daily --breakdown'

# 세션 단위 분석 (어떤 대화에서 토큰 많이 썼는지)
alias ccs='ccusage session --sort tokens'

# 캐시 비율 확인 (live)
alias ccb='ccusage blocks --live'

# ── 도움말 ────────────────────────────────────────────────────
cchelp() {
  cat <<-'EOF'
[ccusage install]
  전역 prefix를 사용자 홈으로 지정하여 설치:
    npm install -g ccusage --prefix=$HOME/.npm-global


[ccusage자주 쓰는 명령어 / alias]
  
  ccd: ccusage daily --breakdown      // 모델별 소비 내역
  ccs: ccusage session --sort tokens  // 세션 단위 분석 (어떤 대화에서 토큰 많이 썼는지)
  ccb: ccusage blocks --live          // 캐시 비율 확인 (실시간)
EOF
}
