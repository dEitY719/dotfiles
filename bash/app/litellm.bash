#!/bin/bash

: <<'LITELLM_DOC'
==========================================================
LiteLLM Proxy Server - Getting Started Guide
==========================================================

🎯 개요
LiteLLM은 여러 LLM 공급자(Gemini, OpenAI 등)를 통합하는 프록시 서버입니다.
프로젝트 경로: /home/bwyoon/para/project/litellm

⚙️  설정 파일
  - litellm_settings.yml : 모델 라우팅 설정
  - .env               : API 키 (GEMINI_API_KEY)
  - docker-compose.yml : 서비스 오케스트레이션

📋 주요 설정
  - Master Key: sk-4444
  - API URL: http://localhost:4444
  - Database: PostgreSQL (5431 포트)
  - Local Models: Ollama (tinyllama1 - 11431 포트)

🚀 빠른 시작
  1) litellm_start      : LiteLLM 스택 시작
  2) litellm_status     : 서비스 상태 확인
  3) litellm_models     : 등록된 모델 목록 확인
  4) litellm_test geminimm-2.0-flash : 모델 정상성 테스트

==========================================================
LITELLM_DOC

# ===== 색상 정의 =====
if command -v tput &> /dev/null; then
    bold=$(tput bold)
    blue=$(tput setaf 4)
    green=$(tput setaf 2)
    yellow=$(tput setaf 3)
    red=$(tput setaf 1)
    reset=$(tput sgr0)
else
    bold=""
    blue=""
    green=""
    yellow=""
    red=""
    reset=""
fi

# ===== 상수 정의 =====
LITELLM_PROJECT_PATH="/home/bwyoon/para/project/litellm"
LITELLM_API_KEY="sk-4444"
LITELLM_URL="http://localhost:4444"
LITELLM_MASTER_KEY="sk-4444"

# ===== 헬퍼 함수 =====

# 프로젝트 디렉토리 체크
_check_litellm_project() {
    if [[ ! -d "$LITELLM_PROJECT_PATH" ]]; then
        echo "${red}❌ LiteLLM 프로젝트를 찾을 수 없습니다: $LITELLM_PROJECT_PATH${reset}"
        return 1
    fi
    return 0
}

# API 연결 테스트
_check_litellm_health() {
    if curl -s "${LITELLM_URL}/health/liveliness" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# litellm_settings.yml에 정의된 모델 목록 파싱
_get_configured_models() {
    if [[ ! -f "$LITELLM_PROJECT_PATH/litellm_settings.yml" ]]; then
        echo ""
        return
    fi

    grep "model_name:" "$LITELLM_PROJECT_PATH/litellm_settings.yml" | \
        sed 's/.*model_name: //' | \
        tr -d ' '
}

# 실제 로드된 모델 목록 조회
_get_loaded_models() {
    curl -s "${LITELLM_URL}/models" \
        -H "Authorization: Bearer ${LITELLM_API_KEY}" 2>/dev/null | \
        grep -o '"id":"[^"]*"' | cut -d'"' -f4 | sort
}

# 모델 등록 상태 검증
_verify_models_loaded() {
    if ! _check_litellm_health; then
        echo "${red}⚠️  LiteLLM이 응답하지 않습니다${reset}"
        return 1
    fi

    local configured_models=($(_get_configured_models))
    local loaded_models=($(_get_loaded_models))

    if [[ ${#loaded_models[@]} -eq 0 ]]; then
        echo "${red}❌ 로드된 모델이 없습니다${reset}"
        return 1
    fi

    echo ""
    echo "${bold}${blue}[모델 로드 상태]${reset}"
    echo ""

    local all_loaded=true
    for model in "${configured_models[@]}"; do
        if [[ " ${loaded_models[@]} " =~ " ${model} " ]]; then
            echo "${green}✅ $model${reset}"
        else
            echo "${red}❌ $model (로드 실패)${reset}"
            all_loaded=false
        fi
    done

    echo ""
    if [[ "$all_loaded" == true ]]; then
        echo "${bold}${green}✓ 모든 모델이 정상적으로 로드되었습니다!${reset}"
        return 0
    else
        echo "${bold}${yellow}⚠️  일부 모델이 로드되지 않았습니다${reset}"
        return 1
    fi
}

# ===== 메인 함수 =====

# 1. LiteLLM 시작
litellm_start() {
    echo "${bold}${blue}[LiteLLM 스택 시작]${reset}"
    _check_litellm_project || return 1

    cd "$LITELLM_PROJECT_PATH" || return 1

    echo "Docker Compose로 서비스 시작 중..."
    docker compose up -d > /dev/null 2>&1

    if [[ $? -eq 0 ]]; then
        echo "${green}✓ 컨테이너 시작 완료${reset}"
    else
        echo "${red}❌ 컨테이너 시작 실패${reset}"
        return 1
    fi

    echo ""
    echo "LiteLLM 초기화 대기 중... (최대 30초)"
    local max_attempts=15
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        sleep 2
        if _check_litellm_health; then
            echo "${green}✓ LiteLLM 응답 확인${reset}"
            echo ""
            _verify_models_loaded
            return $?
        fi
        attempt=$((attempt + 1))
        echo -ne "  시도: $((attempt))/$max_attempts\r"
    done

    echo ""
    echo "${red}❌ LiteLLM이 응답하지 않습니다${reset}"
    echo ""
    echo "디버깅 정보:"
    docker compose ps
    echo ""
    docker compose logs litellm | tail -20
    return 1
}

# 2. LiteLLM 중지
litellm_stop() {
    echo "${bold}${blue}[LiteLLM 스택 중지]${reset}"
    _check_litellm_project || return 1

    cd "$LITELLM_PROJECT_PATH" || return 1
    make down
}

# 3. LiteLLM 재시작
litellm_restart() {
    echo "${bold}${blue}[LiteLLM 스택 재시작]${reset}"
    litellm_stop
    sleep 2
    litellm_start
}

# 4. 서비스 상태 확인
litellm_status() {
    echo "${bold}${blue}[LiteLLM 서비스 상태]${reset}"
    echo ""

    _check_litellm_project || return 1

    cd "$LITELLM_PROJECT_PATH" || return 1

    # Docker 서비스 상태
    echo "Docker 서비스 상태:"
    docker compose ps

    echo ""

    # API 연결 상태
    if _check_litellm_health; then
        echo "${green}✅ LiteLLM API: 정상${reset}"
    else
        echo "${red}❌ LiteLLM API: 응답 없음${reset}"
        return 1
    fi

    echo ""
    _verify_models_loaded
}

# 5. 등록된 모델 목록 조회
litellm_models() {
    echo "${bold}${blue}[LiteLLM 모델 목록]${reset}"
    echo ""

    if ! _check_litellm_health; then
        echo "${red}❌ LiteLLM이 응답하지 않습니다${reset}"
        echo "실행: ${green}litellm_start${reset}"
        return 1
    fi

    local models=$(curl -s "${LITELLM_URL}/models" \
        -H "Authorization: Bearer ${LITELLM_API_KEY}" 2>/dev/null)

    if [[ -z "$models" ]]; then
        echo "${red}❌ 모델 목록을 조회할 수 없습니다${reset}"
        return 1
    fi

    # JSON 파싱해서 모델명 추출
    echo "$models" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | while read -r model; do
        echo "  ${green}•${reset} $model"
    done

    echo ""
    echo "총 모델 수: $(echo "$models" | grep -o '"id":"[^"]*"' | wc -l)"
}

# 6. 모델 테스트
litellm_test() {
    local model_name="${1:-gemini-2.0-flash}"

    echo "${bold}${blue}[LiteLLM 모델 테스트: $model_name]${reset}"
    echo ""

    if ! _check_litellm_health; then
        echo "${red}❌ LiteLLM이 응답하지 않습니다${reset}"
        return 1
    fi

    # 모델 존재 여부 확인
    local available_models=$(_get_loaded_models)
    if ! echo "$available_models" | grep -q "^${model_name}$"; then
        echo "${red}❌ 모델을 찾을 수 없습니다: $model_name${reset}"
        echo ""
        echo "사용 가능한 모델:"
        litellm_models
        return 1
    fi

    echo "요청 중..."
    echo "  Model: ${green}$model_name${reset}"
    echo "  Prompt: What is 2+2?"
    echo ""

    local response=$(curl -s -X POST "${LITELLM_URL}/v1/chat/completions" \
        -H "Authorization: Bearer ${LITELLM_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$model_name\",\"messages\":[{\"role\":\"user\",\"content\":\"What is 2+2?\"}],\"max_tokens\":50}" \
        2>/dev/null)

    # 에러 확인
    if echo "$response" | grep -q '"error"'; then
        local error_msg=$(echo "$response" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
        echo "${red}❌ 요청 실패${reset}"
        echo "  에러: $error_msg"
        return 1
    fi

    # 응답 파싱
    local content=$(echo "$response" | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [[ -z "$content" ]]; then
        # content가 없으면 다른 형식 확인
        echo "${yellow}⚠️  응답을 수신했지만 내용이 비어있습니다${reset}"
        echo ""
        echo "원본 응답 (일부):"
        echo "$response" | head -c 200
        echo "..."
        return 0
    fi

    echo "${green}✅ 성공${reset}"
    echo ""
    echo "응답:"
    echo "  $content"
    return 0
}

# 7. 도움말
litellm_help() {
    cat <<EOF

${bold}${blue}[LiteLLM 명령어 가이드]${reset}

${bold}${blue}기본 명령어:${reset}
  ${green}litellm_start${reset}           : LiteLLM 스택 시작 (make up)
  ${green}litellm_stop${reset}            : LiteLLM 스택 중지 (make down)
  ${green}litellm_restart${reset}         : LiteLLM 재시작
  ${green}litellm_status${reset}          : 서비스 상태 확인
  ${green}litellm_models${reset}          : 등록된 모델 목록 조회
  ${green}litellm_test${reset} <model>    : 모델 정상성 테스트
  ${green}litellm_help${reset}            : 이 도움말 표시

${bold}${blue}사용 예시:${reset}
  # LiteLLM 시작
  ${green}litellm_start${reset}

  # 모델 목록 확인
  ${green}litellm_models${reset}

  # 특정 모델 테스트
  ${green}litellm_test gemini-2.0-flash${reset}
  ${green}litellm_test gemini-2.5-pro${reset}
  ${green}litellm_test tinyllama1${reset}

  # 서비스 상태 확인
  ${green}litellm_status${reset}

${bold}${blue}프로젝트 정보:${reset}
  경로: $LITELLM_PROJECT_PATH
  API URL: $LITELLM_URL
  Master Key: $LITELLM_API_KEY

${bold}${blue}설정 파일:${reset}
  litellm_settings.yml : 모델 라우팅
  .env                 : API 키
  docker-compose.yml   : 서비스 구성

EOF
}

# ===== Alias 정의 =====
alias llm_start='litellm_start'
alias llm_stop='litellm_stop'
alias llm_restart='litellm_restart'
alias llm_status='litellm_status'
alias llm_models='litellm_models'
alias llm_test='litellm_test'
alias llm_help='litellm_help'

# 기본 명령어 (dotfiles에서 sourced될 때 도움말 표시)
# 주석 처리: 매번 도움말이 출력되는 것을 방지
# litellm_help
