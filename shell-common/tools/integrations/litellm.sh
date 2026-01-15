#!/bin/bash
# shell-common/tools/external/litellm.sh
# Auto-generated from bash/app/litellm.bash


: <<'LITELLM_DOC'
==========================================================
LiteLLM Proxy Server - Getting Started Guide
==========================================================

🎯 개요
LiteLLM은 여러 LLM 공급자(Gemini, OpenAI 등)를 통합하는 프록시 서버입니다.
프로젝트 경로: $HOME/para/project/litellm

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

# ===== 환경 변수 초기화 =====

# 프로젝트 경로 자동 감지 (Makefile에서 export되지 않았을 경우)
_init_litellm_env() {
    if [[ "${_LITELLM_ENV_INITIALIZED:-}" == "1" ]]; then
        return 0
    fi

    if [[ -z "${LITELLM_PROJECT_PATH:-}" ]]; then
        # 현재 디렉토리부터 상위로 올라가면서 docker-compose.yml 검색
        local search_dir="."
        while [[ "$search_dir" != "/" ]]; do
            if [[ -f "$search_dir/docker-compose.yml" ]] && [[ -f "$search_dir/litellm_settings.yml" ]]; then
                LITELLM_PROJECT_PATH="$(cd "$search_dir" && pwd)"
                break
            fi
            search_dir="$(cd "$search_dir/.." && pwd)"
        done

        # 여전히 못 찾으면 기본값 사용
        if [[ -z "${LITELLM_PROJECT_PATH:-}" ]]; then
            LITELLM_PROJECT_PATH="$HOME/para/project/litellm"
        fi
    fi

    # 다른 환경 변수도 기본값 설정
    LITELLM_URL="${LITELLM_URL:-http://localhost:4444}"
    LITELLM_API_KEY="${LITELLM_API_KEY:-sk-4444}"

    # 전역 변수로 export
    export LITELLM_PROJECT_PATH LITELLM_URL LITELLM_API_KEY

    _LITELLM_ENV_INITIALIZED="1"
}

# ===== 헬퍼 함수 =====

# Lazy initialization wrapper (idempotent)
_litellm_ensure_init() {
    _init_litellm_env
}

# 프로젝트 디렉토리 체크
_check_litellm_project() {
    _litellm_ensure_init
    local project_path="${LITELLM_PROJECT_PATH:-}"
    if [[ -z "$project_path" ]] || [[ ! -d "$project_path" ]]; then
        ux_error "LiteLLM 프로젝트를 찾을 수 없습니다: ${project_path:-<unset>}"
        return 1
    fi
    return 0
}

# API 연결 테스트
_check_litellm_health() {
    _litellm_ensure_init
    if curl -s "${LITELLM_URL:-}/health/liveliness" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# litellm_settings.yml에 정의된 모델 목록 파싱
_get_configured_models() {
    _litellm_ensure_init

    local project_path="${LITELLM_PROJECT_PATH:-}"
    if [[ -z "$project_path" ]] || [[ ! -f "$project_path/litellm_settings.yml" ]]; then
        return 0
    fi

    grep "model_name:" "$project_path/litellm_settings.yml" |
        sed 's/.*model_name: //' |
        tr -d ' '
}

# 실제 로드된 모델 목록 조회
_get_loaded_models() {
    _litellm_ensure_init

    local url="${LITELLM_URL:-}"
    local api_key="${LITELLM_API_KEY:-}"
    if [[ -z "$url" ]]; then
        return 0
    fi

    curl -s "${url}/models" \
        -H "Authorization: Bearer ${api_key}" 2>/dev/null |
        grep -o '"id":"[^"]*"' | cut -d'"' -f4 | sort
}

# 모델 등록 상태 검증
_verify_models_loaded() {
    if ! _check_litellm_health; then
        ux_warning "LiteLLM이 응답하지 않습니다"
        return 1
    fi

    local configured_models=()
    local loaded_models=()

    # POSIX 호환 방식으로 배열에 데이터 할당 (mapfile 대신 while read 사용)
    while IFS= read -r model; do
        [[ -n "$model" ]] && configured_models+=("$model")
    done < <(_get_configured_models)

    while IFS= read -r model; do
        [[ -n "$model" ]] && loaded_models+=("$model")
    done < <(_get_loaded_models)

    if [[ ${#loaded_models[@]} -eq 0 ]]; then
        ux_error "로드된 모델이 없습니다"
        return 1
    fi

    echo ""
    ux_section "모델 로드 상태"

    local all_loaded=true
    for model in "${configured_models[@]}"; do
        local found=false
        for loaded in "${loaded_models[@]}"; do
            if [[ "$loaded" == "$model" ]]; then
                found=true
                break
            fi
        done

        if [[ "$found" == "true" ]]; then
            ux_success "$model"
        else
            ux_error "$model (로드 실패)"
            all_loaded=false
        fi
    done

    echo ""
    if [[ "$all_loaded" == true ]]; then
        ux_success "모든 모델이 정상적으로 로드되었습니다!"
        return 0
    else
        ux_warning "일부 모델이 로드되지 않았습니다"
        return 1
    fi
}

# ===== 메인 함수 =====

# 1. LiteLLM 시작
litellm_start() {
    ux_header "LiteLLM 스택 시작"
    _check_litellm_project || return 1

    cd "$LITELLM_PROJECT_PATH" || return 1

    ux_info "Docker Compose로 서비스 시작 중..."
    if docker compose up -d >/dev/null 2>&1; then
        ux_success "컨테이너 시작 완료"
    else
        ux_error "컨테이너 시작 실패"
        return 1
    fi

    echo ""
    ux_info "LiteLLM 초기화 대기 중... (최대 30초)"
    local max_attempts=15
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        sleep 2
        if _check_litellm_health; then
            ux_success "LiteLLM 응답 확인"
            echo ""
            _verify_models_loaded
            return $?
        fi
        attempt=$((attempt + 1))
        echo -ne "  시도: $((attempt))/$max_attempts\r"
    done

    echo ""
    ux_error "LiteLLM이 응답하지 않습니다"
    echo ""
    ux_section "디버깅 정보"
    docker compose ps
    echo ""
    docker compose logs litellm | tail -20
    return 1
}

# 2. LiteLLM 중지
litellm_stop() {
    ux_header "LiteLLM 스택 중지"
    _check_litellm_project || return 1

    cd "$LITELLM_PROJECT_PATH" || return 1
    make down
}

# 3. LiteLLM 재시작
litellm_restart() {
    ux_header "LiteLLM 스택 재시작"
    litellm_stop
    sleep 2
    litellm_start
}

# 4. 서비스 상태 확인
litellm_status() {
    ux_header "LiteLLM 서비스 상태"

    _check_litellm_project || return 1

    cd "$LITELLM_PROJECT_PATH" || return 1

    # Docker 서비스 상태
    ux_section "Docker 서비스 상태"
    docker compose ps

    echo ""

    # API 연결 상태
    if _check_litellm_health; then
        ux_success "LiteLLM API: 정상"
    else
        ux_error "LiteLLM API: 응답 없음"
        return 1
    fi

    echo ""
    _verify_models_loaded
}

# 5. 등록된 모델 목록 조회
litellm_models() {
    ux_header "LiteLLM 모델 목록"

    if ! _check_litellm_health; then
        ux_error "LiteLLM이 응답하지 않습니다"
        ux_info "실행: litellm_start"
        return 1
    fi

    local models
    models=$(curl -s "${LITELLM_URL}/models" \
        -H "Authorization: Bearer ${LITELLM_API_KEY}" 2>/dev/null)

    if [[ -z "$models" ]]; then
        ux_error "모델 목록을 조회할 수 없습니다"
        return 1
    fi

    # JSON 파싱해서 모델명 추출
    echo "$models" | grep -o '"id":"[^"]*"' | cut -d'"' -f4 | while read -r model; do
        ux_bullet "$model"
    done

    echo ""
    ux_info "총 모델 수: $(echo "$models" | grep -o '"id":"[^"]*"' | wc -l)"
}

# 6. 모델 테스트
litellm_test() {
    # 매개변수 검증
    if [[ $# -eq 0 ]]; then
        ux_header "LiteLLM 모델 테스트"
        ux_section "사용법"
        echo ""
        ux_bullet "기본 사용법:"
        echo "  llm-test <model> [prompt] [max-tokens]"
        echo ""
        ux_bullet "매개변수:"
        echo "  model       : 사용할 모델명 (필수)"
        echo "  prompt      : 질문 (선택, 기본값: What is 2+2?)"
        echo "  max-tokens  : 최대 토큰 (선택, 기본값: 100)"
        echo ""
        ux_bullet "예시:"
        echo "  llm-test gpt-oss-20b                                  # 기본 프롬프트"
        echo "  llm-test gpt-oss-20b \"What is 3+4?\"                 # 프롬프트 지정"
        echo "  llm-test gpt-oss-20b \"Explain AI\" 200               # 토큰 지정"
        echo ""
        ux_section "사용 가능한 모델"
        litellm_models
        return 0
    fi

    local model_name="${1:-gpt-oss-20b}"
    local prompt="${2:-What is 2+2?}"
    local max_tokens="${3:-100}"

    ux_header "LiteLLM 모델 테스트: $model_name"

    if ! _check_litellm_health; then
        ux_error "LiteLLM이 응답하지 않습니다"
        return 1
    fi

    # 모델 존재 여부 확인
    local available_models
    available_models=$(_get_loaded_models)
    if ! echo "$available_models" | grep -q "^${model_name}$"; then
        ux_error "모델을 찾을 수 없습니다: $model_name"
        echo ""
        ux_section "💡 사용법"
        echo ""
        ux_bullet "올바른 사용법:"
        echo "  llm-test <model> <prompt> [max-tokens]"
        echo ""
        ux_bullet "예시:"
        echo "  llm-test gpt-oss-20b \"What is 3+4?\""
        echo "  llm-test gpt-oss-20b \"Your question\" 200"
        echo ""
        ux_section "사용 가능한 모델:"
        litellm_models
        return 1
    fi

    ux_info "요청 중..."
    ux_bullet "Model: ${UX_SUCCESS}$model_name${UX_RESET}"
    ux_bullet "Prompt: $prompt"
    ux_bullet "Max tokens: $max_tokens"
    echo ""

    # JSON 요청 생성 (proper escaping)
    local request_json
    request_json=$(cat <<EOF
{
  "model": "$model_name",
  "messages": [
    {
      "role": "user",
      "content": $(echo "$prompt" | jq -R .)
    }
  ],
  "max_tokens": $max_tokens
}
EOF
)

    local response
    response=$(curl -s -X POST "${LITELLM_URL}/v1/chat/completions" \
        -H "Authorization: Bearer ${LITELLM_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$request_json" \
        2>/dev/null)

    # jq로 에러 확인
    if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error.message // .error' 2>/dev/null)
        ux_error "요청 실패"
        echo "  에러: $error_msg"
        echo ""
        echo "DEBUG: Full response:"
        echo "$response" | jq . 2>/dev/null || echo "$response"
        return 1
    fi

    # jq로 응답 파싱 (안전함)
    local content
    content=$(echo "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

    if [[ -z "$content" ]]; then
        ux_warning "응답을 수신했지만 내용이 비어있습니다"
        echo ""
        echo "원본 응답:"
        echo "$response" | jq . 2>/dev/null || echo "$response"
        return 0
    fi

    ux_success "성공"
    echo ""
    ux_section "응답"
    echo "$content"
    return 0
}

# 7. 도커 네트워크 정보
litellm_network() {
    ux_header "LiteLLM 도커 네트워크"
    docker network inspect litellm-network
}

# 8. 도움말

# ===== Alias 정의 =====
alias llm-start='litellm_start'
alias llm-stop='litellm_stop'
alias llm-restart='litellm_restart'
alias llm-status='litellm_status'
alias llm-models='litellm_models'
alias llm-test='litellm_test'
alias llm-network='litellm_network'

# ===== 초기화 =====
# Do not auto-run at shell init time. Functions call _init_litellm_env lazily.
