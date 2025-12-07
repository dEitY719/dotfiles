#!/bin/bash

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
    if [[ -z "$LITELLM_PROJECT_PATH" ]]; then
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
        if [[ -z "$LITELLM_PROJECT_PATH" ]]; then
            LITELLM_PROJECT_PATH="$HOME/para/project/litellm"
        fi
    fi

    # 다른 환경 변수도 기본값 설정
    LITELLM_URL="${LITELLM_URL:-http://localhost:4444}"
    LITELLM_API_KEY="${LITELLM_API_KEY:-sk-4444}"

    # 전역 변수로 export
    export LITELLM_PROJECT_PATH LITELLM_URL LITELLM_API_KEY
}

# ===== 헬퍼 함수 =====

# 프로젝트 디렉토리 체크
_check_litellm_project() {
    if [[ ! -d "$LITELLM_PROJECT_PATH" ]]; then
        ux_error "LiteLLM 프로젝트를 찾을 수 없습니다: $LITELLM_PROJECT_PATH"
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

    grep "model_name:" "$LITELLM_PROJECT_PATH/litellm_settings.yml" |
        sed 's/.*model_name: //' |
        tr -d ' '
}

# 실제 로드된 모델 목록 조회
_get_loaded_models() {
    curl -s "${LITELLM_URL}/models" \
        -H "Authorization: Bearer ${LITELLM_API_KEY}" 2>/dev/null |
        grep -o '"id":"[^"]*"' | cut -d'"' -f4 | sort
}

# 모델 등록 상태 검증
_verify_models_loaded() {
    if ! _check_litellm_health; then
        ux_warning "LiteLLM이 응답하지 않습니다"
        return 1
    fi

    local configured_models
    local loaded_models
    mapfile -t configured_models < <(_get_configured_models)
    mapfile -t loaded_models < <(_get_loaded_models)

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
    local model_name="${1:-gemini-2.0-flash}"

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
        ux_info "사용 가능한 모델:"
        litellm_models
        return 1
    fi

    ux_info "요청 중..."
    ux_bullet "Model: ${UX_SUCCESS}$model_name${UX_RESET}"
    ux_bullet "Prompt: What is 2+2?"
    echo ""

    local response
    response=$(curl -s -X POST "${LITELLM_URL}/v1/chat/completions" \
        -H "Authorization: Bearer ${LITELLM_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$model_name\",\"messages\":[{\"role\":\"user\",\"content\":\"What is 2+2?\"}],\"max_tokens\":50}" \
        2>/dev/null)

    # 에러 확인
    if echo "$response" | grep -q '"error"'; then
        local error_msg
        error_msg=$(echo "$response" | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
        ux_error "요청 실패"
        echo "  에러: $error_msg"
        return 1
    fi

    # 응답 파싱
    local content
    content=$(echo "$response" | grep -o '"content":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [[ -z "$content" ]]; then
        # content가 없으면 다른 형식 확인
        ux_warning "응답을 수신했지만 내용이 비어있습니다"
        echo ""
        echo "원본 응답 (일부):"
        echo "$response" | head -c 200
        echo "..."
        return 0
    fi

    ux_success "성공"
    echo ""
    ux_section "응답"
    echo "  $content"
    return 0
}

# 7. 도움말
litellm_help() {
    ux_header "LiteLLM Commands"

    ux_section "Basic Commands"
    ux_table_row "litellm_start" "Start Stack" "docker compose up"
    ux_table_row "litellm_stop" "Stop Stack" "docker compose down"
    ux_table_row "litellm_restart" "Restart" "Stop & Start"
    ux_table_row "litellm_status" "Status" "Check health & models"
    ux_table_row "litellm_models" "List Models" "Show loaded models"
    ux_table_row "litellm_test" "Test Model" "Run basic prompt"
    echo ""

    ux_section "Examples"
    ux_bullet "Start: ${UX_SUCCESS}litellm_start${UX_RESET}"
    ux_bullet "Test:  ${UX_SUCCESS}litellm_test gemini-2.0-flash${UX_RESET}"
    ux_bullet "Check: ${UX_SUCCESS}litellm_status${UX_RESET}"
    echo ""

    ux_section "Project Info"
    ux_table_row "Path" "$LITELLM_PROJECT_PATH" ""
    ux_table_row "URL" "$LITELLM_URL" ""
    ux_table_row "Key" "$LITELLM_API_KEY" ""
    echo ""
}

# ===== Alias 정의 =====
alias llm_start='litellm_start'
alias llm_stop='litellm_stop'
alias llm_restart='litellm_restart'
alias llm_status='litellm_status'
alias llm_models='litellm_models'
alias llm_test='litellm_test'
alias llm_help='litellm_help'

# ===== 초기화 (sourced될 때 자동 실행) =====
_init_litellm_env
