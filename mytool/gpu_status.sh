#!/bin/bash
# gpu_status.sh - WSL2 환경 최적화 GPU 상태 모니터링
# 목적: WSL2 특성상 컨테이너 내 nvidia-smi 사용 불가를 해결하고
#      Ollama의 실제 GPU 사용 현황을 정확히 진단

set -e

# ═══════════════════════════════════════════════════
# 색상 정의
# ═══════════════════════════════════════════════════

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# ═══════════════════════════════════════════════════
# 헤더
# ═══════════════════════════════════════════════════

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}GPU 상태 모니터링 (WSL2 환경)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ═══════════════════════════════════════════════════
# [섹션 1/5] WSL2 호스트 GPU 하드웨어
# ═══════════════════════════════════════════════════

echo -e "${YELLOW}[1/5] WSL2 호스트 GPU 하드웨어${NC}"
echo ""

if [ -x /usr/lib/wsl/lib/nvidia-smi ]; then
    GPU_INFO=$(/usr/lib/wsl/lib/nvidia-smi --query-gpu=index,name,driver_version,memory.total,memory.free,memory.used --format=csv,noheader 2>/dev/null)

    if [ -n "$GPU_INFO" ]; then
        echo -e "${GREEN}  ✓ GPU 감지 성공${NC}"
        echo ""
        echo "  GPU Index | GPU Name                       | Driver   | Total VRAM | Free VRAM | Used VRAM"
        echo "  ────────────────────────────────────────────────────────────────────────────────────────"
        echo "$GPU_INFO" | while IFS=, read -r index name driver total free used; do
            printf "  %-9s | %-30s | %-8s | %-10s | %-9s | %-9s\n" \
                "$index" "$(echo $name | cut -c1-30)" "$driver" "$total" "$free" "$used"
        done
        echo ""
    else
        echo -e "${RED}  ✗ GPU 정보 조회 실패${NC}"
        echo ""
    fi
else
    echo -e "${YELLOW}  ⚠ nvidia-smi not found${NC}"
    echo -e "${BLUE}  → WSL2 환경에서 nvidia-smi는 /usr/lib/wsl/lib/에 위치합니다${NC}"
    echo ""
fi

# ═══════════════════════════════════════════════════
# [섹션 2/5] Docker GPU 설정
# ═══════════════════════════════════════════════════

echo -e "${YELLOW}[2/5] Docker GPU 설정${NC}"
echo ""

if docker inspect ollama > /dev/null 2>&1; then
    # Docker 컨테이너의 GPU 디바이스 요청 확인
    GPU_CONFIG=$(docker inspect ollama --format '{{json .HostConfig.DeviceRequests}}' 2>/dev/null || echo "[]")

    if echo "$GPU_CONFIG" | grep -q '"Driver":"nvidia"' 2>/dev/null; then
        echo -e "${GREEN}  ✓ GPU 설정 활성화${NC}"

        # GPU Count 파싱 (json 없을 수 있으므로 조건부)
        if command -v jq &> /dev/null; then
            GPU_COUNT=$(echo "$GPU_CONFIG" | jq -r '.[0].Count // -1' 2>/dev/null || echo "-1")
            [ "$GPU_COUNT" = "-1" ] && GPU_COUNT="all"
            echo "    - Driver: nvidia"
            echo "    - Count: $GPU_COUNT (all GPUs)"
            echo "    - Capabilities: gpu"
        else
            echo "    - Driver: nvidia"
            echo "    - Count: all (all GPUs)"
            echo "    - Capabilities: gpu"
        fi
        echo ""
    else
        echo -e "${YELLOW}  ⚠ GPU 설정 없음${NC}"
        echo -e "${BLUE}  → docker-compose.yml의 deploy.resources.reservations.devices 확인 필요${NC}"
        echo ""
    fi
else
    echo -e "${RED}  ✗ Ollama 컨테이너 미실행${NC}"
    echo -e "${BLUE}  → 'docker compose up -d'로 스택 시작 필요${NC}"
    echo ""
fi

# ═══════════════════════════════════════════════════
# [섹션 3/5] Ollama GPU 사용 현황 (핵심!)
# ═══════════════════════════════════════════════════

echo -e "${YELLOW}[3/5] Ollama GPU 사용 현황${NC}"
echo ""

if ! docker logs ollama > /dev/null 2>&1; then
    echo -e "${RED}  ✗ Ollama 컨테이너 로그 조회 불가${NC}"
    echo ""
else
    # GPU 메모리 인식 확인
    GPU_MEMORY_LOG=$(docker logs ollama 2>&1 | grep "gpu memory" | tail -1)

    if [ -n "$GPU_MEMORY_LOG" ]; then
        echo -e "${GREEN}  ✓ Ollama GPU 인식 확인${NC}"

        # 로그에서 정보 추출
        GPU_AVAILABLE=$(echo "$GPU_MEMORY_LOG" | grep -oP 'available="\K[^"]+' || echo "?")
        GPU_FREE=$(echo "$GPU_MEMORY_LOG" | grep -oP 'free="\K[^"]+' || echo "?")

        echo "    - Available: $GPU_AVAILABLE"
        echo "    - Free: $GPU_FREE"
        echo ""
    else
        echo -e "${YELLOW}  ⚠ GPU 메모리 감지 로그 없음${NC}"
        echo -e "${BLUE}  → Ollama가 아직 모델을 로드하지 않았을 수 있습니다${NC}"
        echo ""
    fi

    # 레이어 오프로드 상태 (가장 중요!)
    LATEST_OFFLOAD=$(docker logs ollama 2>&1 | grep "offloaded.*layers to GPU" | tail -1)

    if [ -n "$LATEST_OFFLOAD" ]; then
        LAYERS_OFFLOADED=$(echo "$LATEST_OFFLOAD" | grep -oP 'offloaded \K\d+/\d+')

        # GPU vs CPU 모드 판별
        if [[ "$LAYERS_OFFLOADED" == "0/"* ]]; then
            echo -e "${RED}  ⚠ 경고: GPU 레이어 오프로드 실패!${NC}"
            echo -e "${RED}    현재: $LAYERS_OFFLOADED (CPU 모드)${NC}"
            echo ""
            echo -e "${BLUE}  영향: 모델이 CPU에서 실행되어 성능이 크게 저하됩니다${NC}"
            echo -e "${BLUE}  해결 방법: 아래 [5/5] 성능 권장사항 참고${NC}"
            echo ""
        else
            echo -e "${GREEN}  ✓ GPU 레이어 오프로드 성공${NC}"
            echo "    현재: $LAYERS_OFFLOADED layers offloaded to GPU"
            echo ""
        fi
    else
        echo -e "${YELLOW}  ⚠ 레이어 오프로드 로그 없음${NC}"
        echo -e "${BLUE}  → Ollama를 통해 모델을 실행해보세요${NC}"
        echo -e "${BLUE}    예: curl http://localhost:4444/v1/chat/completions -H 'Authorization: Bearer sk-4444' ...${NC}"
        echo ""
    fi
fi

# ═══════════════════════════════════════════════════
# [섹션 4/5] Ollama 환경변수
# ═══════════════════════════════════════════════════

echo -e "${YELLOW}[4/5] Ollama 환경변수${NC}"
echo ""

if ! docker exec ollama env > /dev/null 2>&1; then
    echo -e "${BLUE}  ⚠ Ollama 컨테이너 접근 불가${NC}"
else
    OLLAMA_ENVS=$(docker exec ollama env 2>/dev/null | grep -E "OLLAMA_|CUDA_" | sort)

    if [ -n "$OLLAMA_ENVS" ]; then
        echo "$OLLAMA_ENVS" | while IFS= read -r line; do
            echo "  $line"
        done
        echo ""

        # 중요 변수 체크
        if ! echo "$OLLAMA_ENVS" | grep -q "OLLAMA_GPU_OVERHEAD"; then
            echo -e "${YELLOW}  ⚠ OLLAMA_GPU_OVERHEAD 미설정${NC}"
            echo -e "${BLUE}    → 권장: docker-compose.yml에서 1-2GB 설정${NC}"
            echo ""
        fi

        if ! echo "$OLLAMA_ENVS" | grep -q "OLLAMA_NUM_GPU"; then
            echo -e "${YELLOW}  ⚠ OLLAMA_NUM_GPU 미설정${NC}"
            echo -e "${BLUE}    → 권장: 레이어 오프로드 문제 시 명시적으로 설정${NC}"
            echo ""
        fi
    else
        echo -e "${BLUE}  ℹ 추가 환경변수 미설정 (기본값 사용 중)${NC}"
        echo ""
    fi
fi

# ═══════════════════════════════════════════════════
# [섹션 5/5] 성능 권장사항
# ═══════════════════════════════════════════════════

echo -e "${YELLOW}[5/5] 성능 최적화 권장사항${NC}"
echo ""

# GPU 레이어 오프로드 실패 시 상세 권장사항
if [[ "$LAYERS_OFFLOADED" == "0/"* ]]; then
    echo -e "${RED}GPU 레이어 오프로드 개선 (우선순위)${NC}"
    echo ""

    echo "1️⃣  Ollama 재시작:"
    echo "   docker compose restart ollama"
    echo ""

    echo "2️⃣  환경변수 설정 (docker-compose.yml 수정):"
    echo "   ollama:"
    echo "     environment:"
    echo "       OLLAMA_GPU_OVERHEAD: \"1073741824\"  # 1GB"
    echo "       OLLAMA_NUM_GPU: \"25\"               # tinyllama/gpt-oss 레이어 수"
    echo ""

    echo "3️⃣  스택 재구축:"
    echo "   docker compose down"
    echo "   docker compose up -d"
    echo "   sleep 30"
    echo "   make gpu-status  # 재확인"
    echo ""

    echo "4️⃣  CUDA 호환성 확인:"
    echo "   docker logs ollama 2>&1 | grep -i 'cuda'"
    echo ""

    echo "5️⃣  지속 실패 시:"
    echo "   - Windows NVIDIA 드라이버 업데이트"
    echo "   - 다른 GPU 사용 프로그램 종료 (Chrome, VS Code 등)"
    echo "   - docs/wsl2-gpu-guide.md 참고"
    echo ""

elif [[ "$LAYERS_OFFLOADED" =~ ^[1-9][0-9]*/[0-9]+$ ]]; then
    # 부분 오프로드 (일부만 GPU, 일부는 CPU)
    echo -e "${YELLOW}GPU 부분 오프로드 최적화 (선택)${NC}"
    echo ""
    echo "현재 일부 레이어만 GPU에서 실행 중입니다."
    echo "더 많은 레이어를 GPU로 오프로드하려면:"
    echo ""
    echo "  1. OLLAMA_GPU_OVERHEAD 감소 (1GB → 512MB):"
    echo "     OLLAMA_GPU_OVERHEAD: \"536870912\""
    echo ""
    echo "  2. 다른 GPU 프로그램 종료"
    echo ""
    echo "  3. Ollama 재시작"
    echo ""
else
    echo -e "${GREEN}✓ GPU 설정이 정상입니다${NC}"
    echo ""
    echo "추가 최적화 (선택):"
    echo ""
    echo "  1. Flash Attention 활성화:"
    echo "     docker-compose.yml에서:"
    echo "     OLLAMA_FLASH_ATTENTION: \"1\""
    echo ""
    echo "  2. 동시 요청 처리량 조정:"
    echo "     OLLAMA_NUM_PARALLEL: \"2\" (싱글유저)"
    echo "     OLLAMA_NUM_PARALLEL: \"4\" (멀티유저)"
    echo ""
    echo "  3. 최대 로드 모델 수 조정 (VRAM 여유 따라):"
    echo "     OLLAMA_MAX_LOADED_MODELS: \"2\" (기본)"
    echo "     OLLAMA_MAX_LOADED_MODELS: \"3\" (16GB+ VRAM)"
    echo ""
fi

# ═══════════════════════════════════════════════════
# WSL2 환경 참고사항
# ═══════════════════════════════════════════════════

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}WSL2 환경 참고사항${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "📌 nvidia-smi 제한 (정상 동작):"
echo "   • 컨테이너 내부에서 nvidia-smi 실행 불가"
echo "   • 원인: WSL2 구조상 컨테이너가 /usr/lib/wsl/lib/ 경로 접근 불가"
echo "   • 해결: 호스트에서 /usr/lib/wsl/lib/nvidia-smi 사용"
echo ""
echo "📌 GPU 연산 상태 (정상):"
echo "   • nvidia-smi 불가 != GPU 미사용"
echo "   • CUDA 런타임은 정상 작동 중"
echo "   • Ollama 로그로 실제 GPU 사용 확인"
echo ""
echo "📌 추천 명령어:"
echo "   • make gpu-info      - 간략 GPU 정보"
echo "   • make gpu-status    - 상세 GPU 진단 (이 스크립트)"
echo "   • make health        - 전체 헬스 체크 (GPU 포함)"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
