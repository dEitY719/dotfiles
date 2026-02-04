# Ollama 로컬 통합 및 Claude Code 연동 계획 (Gemini)

## 1. 개요
`@docs/technic/ollama-local-claude-code-integration.md`에서 정의한 로컬 AI 코딩 환경 구축을 위해 WSL 환경에 Ollama를 직접 설치하고 관리 도구를 구현함.

## 2. 현재 상태 분석
- **Docker**: `litellm-ollama` 컨테이너가 11434 포트에서 동작 중 (v0.13.1).
- **WSL Host**: `ollama` 바이너리 부재로 인해 `ollama launch` 등 최신 기능 활용 불가.
- **Claude Code**: 설치 완료 (v2.1.31).
- **필요 모델**: `GLM 4.7 Flash` (MoE 기반 모델) 미설치.

## 3. 구현 계획
### 3.1. 통합 스크립트 생성
- **경로**: `shell-common/tools/integrations/ollama.sh`
- **주요 기능**:
    - **설치 스크립트**: WSL 환경에 Ollama 바이너리 자동 설치 및 업데이트.
    - **서비스 관리**: `systemd`를 통한 Ollama 서비스 등록 및 상태 확인.
    - **`ollama-help` 함수**: 
        - 현재 설치된 모델 목록 표시.
        - 컨텍스트 길이(64K) 설정 방법 가이드.
        - `ollama launch claude` 사용법 안내.
    - **모델 최적화**: `GLM 4.7 Flash` 모델 다운로드 및 컨텍스트 길이 최적화 설정 자동화.

### 3.2. 환경 설정
- `tox.ini` 및 `pyproject.toml` 규칙 준수.
- `dotfiles` 관리 체계에 맞춰 `shell-common` 내부에 통합하여 다른 기기에서도 재사용 가능하도록 구성.

## 4. 기대 효과
- 외부 API 비용 절감 및 데이터 보안 강화.
- `ollama launch` 기능을 통한 Claude Code와의 매끄러운 로컬 연동.
- 로컬 GPU 자원을 활용한 무제한 코딩 실험 환경 확보.
