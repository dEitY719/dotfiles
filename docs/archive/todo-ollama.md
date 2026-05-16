# Ollama WSL + Docker Hybrid Integration - TODO List
# Last Updated: 2026-02-04 18:50 KST

## ✅ 완료된 항목 (2026-02-04)

### Phase 1: 기초 인프라 구축
- ✅ install_ollama.sh: 오프라인 설치 모드 구현
- ✅ ollama.sh (integrations): Backend 감지 및 통합 함수 구현
- ✅ shell-common/env/ollama.sh: 환경변수 중앙화
- ✅ ollama-status-env: 환경 설정 검증 명령어
- ✅ install-ollama 공식 스크립트로 변경 (ollama.com 사용)
- ✅ WSL Ollama 0.15.4 설치 완료
- ✅ systemd 서비스 설정 (포트 11434)

### Phase 2: 분리 운영 정책 수립
- ✅ Docker Ollama (11434) vs WSL Ollama (11435) 분리 전략 결정
- ✅ ollama-restart 시스템 관리 명령어 추가
- ✅ 포트 11434에서 WSL Ollama 기본 실행 (Docker 중지 상태)

## ⏳ 진행 중인 항목

### GLM-4.7-Flash 다운로드
- 📥 다운로드 진행 중: 2% (422 MB / 19 GB, 약 17분 소요)
- 예상 완료 시간: 18:50 + 17분 ≈ 19:07

---

## 🚀 다음 해야할 일 (내일 또는 다음 작업)

### 1️⃣ GLM-4.7-Flash 검증 (우선순위: 높음)
- [ ] 다운로드 완료 확인: `ollama-models`
- [ ] 모델 실행 테스트: `ollama-run glm-4.7-flash`
- [ ] 메모리 및 GPU 사용량 모니터링

### 2️⃣ 분리 운영 구조 완성
- [ ] Docker Ollama 재시작: `docker start ollama`
- [ ] 포트 상태 확인: `sudo ss -lntp | grep -E '11434|11435'`
- [ ] 양쪽 모델 동시 운영 테스트
  - gpt-oss:20b (Docker, 11434)
  - glm-4.7-flash (WSL, 11434)

### 3️⃣ ollama-pull Wrapper 함수 버그 수정
- [ ] ollama-pull vs ollama pull 동작 차이 진단
- [ ] 함수 정의 확인: `type ollama-pull` / `declare -f ollama-pull`
- [ ] 버그 원인 파악 및 수정
- [ ] 테스트: `ollama-pull <model>` 정상 작동 확인

### 4️⃣ Claude Code / AI Agent 통합
- [ ] Claude Code와 WSL Ollama (11434) 연동 테스트
- [ ] LiteLLM과 Docker Ollama (11434) 연동 테스트
- [ ] ollama-launch claude 명령어 검증

### 5️⃣ 환경 최적화
- [ ] OLLAMA_HOST 환경변수 ~/.bashrc에 고정 (필요시)
- [ ] ollama-local, ollama-docker alias 추가 (선택사항)
- [ ] 포트별 wrapper 함수 정리

---

## 📊 현재 상태 요약

| 항목 | 상태 | 상세 |
|------|------|------|
| **WSL Ollama** | ✅ 설치됨 | 0.15.4, 포트 11434, systemd 실행 중 |
| **GLM-4.7-Flash** | 📥 다운로드 중 | 2% (약 17분 소요) |
| **Docker Ollama** | 🛑 중지됨 | 필요시 재시작 가능 |
| **포트 분리** | ✅ 정책 수립 | 11434 (기본), 11435 (예약) |
| **시스템 관리** | ✅ 개선됨 | ollama-restart 명령어 추가 |

---

## 🔗 관련 문서
- @docs/review/abc-review-C.md - Ollama 통합 계획
- shell-common/tools/custom/install_ollama.sh - 설치 스크립트
- shell-common/tools/integrations/ollama.sh - 백엔드 통합 함수
- shell-common/env/ollama.sh - 환경변수 중앙화

---

## 🛠️ 신규 프로젝트: my-cli 개발 (2026-02-19)

### 1️⃣ 초기 설계 및 준비 (우선순위: 보통)
- [x] 설계 문서 작성: `@docs/feature/my-cli/requirements/req-abc-c.md`
- [ ] 동료 리뷰 및 피드백 반영
- [ ] 프로젝트 스캐폴딩 생성 (Python Typer 기반)

### 2️⃣ 핵심 기능 구현
- [ ] Shell Help Discovery 로직 (Python)
- [ ] Category-based UI (Rich)
- [ ] Fuzzy matching & Ambiguity handling

---

**다음 퇴근: 복귀 시 GLM-4.7-Flash 다운로드 완료 확인 + 분리 운영 테스트 + my-cli 리뷰 시작**
