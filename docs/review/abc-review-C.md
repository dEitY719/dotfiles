# [C] WSL + Docker Hybrid Ollama 환경 구축 계획

## 🎯 최종 목표

**WSL Ollama와 Docker Ollama를 seamless하게 통합 관리**

사용자는 동일한 명령어(`ollama_models`, `ollama_pull` 등)로 두 환경을 투명하게 사용하며, 필요시 명시적으로 선택 가능합니다.

```bash
# 자동 선택 (기본: WSL > Docker)
ollama_models

# 명시적 선택
ollama_models --local   # WSL Ollama 강제
ollama_models --docker  # Docker Ollama 강제

# 환경변수로 전역 설정
export DOTFILES_OLLAMA_BACKEND=docker
ollama_models  # Docker 사용
```

## 📋 개요

**참고 문서**: [@docs/technic/ollama-local-claude-code-integration.md](/home/bwyoon/dotfiles/docs/technic/ollama-local-claude-code-integration.md)에서 정의한 로컬 AI 코딩 환경 구축을 위해 WSL 환경에 Ollama를 직접 설치하고 관리 도구를 구현합니다.

---

## 🔍 현재 상태 분석

| 컴포넌트 | 상태 | 버전/설명 | 상태 |
|---------|------|----------|------|
| **Docker Ollama** | ✅ 운영 중 | v0.13.1 (포트 11434) | 안정적 |
| **WSL Host Ollama** | ❌ 미설치 | - | **필요** |
| **Claude Code** | ✅ 설치 완료 | v2.1.31 | 준비됨 |
| **GLM 4.7 Flash** | ❌ 미설치 | 30B MoE 모델 | **필요** |
| **API 호환성** | ⏳ 검증 필요 | Anthropic API 호환 | 진행 중 |

**목표**: Claude Code와의 로컬 LLM 통합을 위해 WSL 호스트에 Ollama 바이너리 설치 및 관리 인프라 구축

---

## ⚙️ 핵심 설계 원칙 (SOLID + Backend Abstraction)

### SOLID 평가 (목표)

| 원칙 | 점수 | 목표 | 달성 방법 |
|------|------|------|----------|
| **SRP** (Single Responsibility) | 7/10 | 설치와 런타임 분리 | `install_ollama.sh` vs `ollama.sh` |
| **OCP** (Open/Closed Principle) | 8/10 | 새 backend 확장성 | 환경변수 + 감지 로직 |
| **LSP** (Liskov Substitution) | 7/10 | 통일된 인터페이스 | `ollama_cmd()` 캡슐화 |
| **ISP** (Interface Segregation) | 8/10 | 함수 단위 분리 | `ollama_*` 단위 함수 |
| **DIP** (Dependency Inversion) | 8/10 | 구현 세부사항 은닉 | backend 선택 로직 캡슐화 |
| **총합** | **38/50** | **실용적 수준** | 단계별 개선 |

### 🏗️ Hybrid 아키텍처: WSL + Docker Ollama 통합 전략

**핵심 원칙**: WSL Ollama와 Docker Ollama를 **seamless하게 관리**

#### Backend 선택 규칙 (우선순위)

```
1️⃣  명시적 플래그 확인 (--docker 또는 --local)
     ↓ (사용자 선택 우선)
2️⃣  DOTFILES_OLLAMA_BACKEND 환경변수
     ↓ (local|docker 강제 설정)
3️⃣  자동 감지 모드 (기본)
     ├─ 로컬 ollama 바이너리 존재? → local 사용
     ├─ Docker 컨테이너 실행 중? → docker 사용
     └─ 둘 다 존재? → 로컬 우선 (WSL이 더 빠름)
4️⃣  사용 불가 → 설치 가이드 제시
```

**사용자 관점 (Seamless)**:
```bash
# 동일한 명령어 - 자동으로 올바른 backend 선택됨
ollama_models           # ← WSL Ollama 우선, 없으면 Docker
ollama_pull gpt-oss:20b # ← seamless
ollama_run gpt-oss:20b  # ← seamless

# 필요시 명시적 선택
ollama_models --docker  # ← Docker만 사용
ollama_models --local   # ← WSL Ollama만 사용
ollama_models --auto    # ← 자동 감지 (기본값)
```

#### 🔍 현재 상황 분석

| 상황 | WSL Ollama | Docker Ollama | 선택 우선순위 |
|------|-----------|---------------|-------------|
| **현재** | ❌ 미설치 | ✅ 0.13.1 운영 | Docker만 |
| **Phase 1 후** | ✅ 설치 | ✅ 0.13.1 운영 | **WSL (로컬이 더 빠름)** |
| **사용자 강제** | - | - | `--docker` 또는 `--local` |

---

**캡슐화 함수들**:
- `ollama_backend_detect()`: 현재 backend 판정
- `ollama_cmd()`: 실행 경로 자동화 (`ollama ...` or `docker exec`)
- `ollama_api_base_url()`: API 엔드포인트 반환
- `ollama_normalize_model_name()`: `gpt-oss-20b` → `gpt-oss:20b` 변환

---

## 🎯 Phase 1: 기초 인프라 구축

### 1.1 WSL 호스트 Ollama 바이너리 설치 스크립트

**목표**: WSL 호스트에 Ollama 바이너리 자동 설치 및 재현성 확보

**경로**: `shell-common/tools/custom/install_ollama.sh`

**작업 사항**:
- 사전 확인: 이미 설치되어 있으면 버전 출력 후 종료
- 공식 설치 스크립트 기반 설치: `curl https://ollama.ai/install.sh | sh`
- 설치 후 검증: `ollama --version` 확인
- **포트 충돌 감지**: 도커가 11434를 점유 중이면 경고 및 해결 방법 안내
  - 도커 일시 중지: `docker stop ollama`
  - 로컬 포트 변경: `OLLAMA_HOST=127.0.0.1:11435`

**규칙 준수**:
- UX 라이브러리 사용 (ux_header, ux_section, ux_bullet 등)
- `shell-common/tools/custom/` 규칙: 파일 맨 끝에 `direct-exec guard` 추가
  ```bash
  # Direct execution guard (script 직접 실행 시에만 동작)
  if [ "$0" = "${BASH_SOURCE[0]}" ] || [ "$0" = "$ZSHNAME" ]; then
    main "$@"
  fi
  ```

**산출물**:
```
shell-common/tools/custom/install_ollama.sh
├─ Pre-check (이미 설치됨)
├─ Install logic (네트워크 + sudo 필요)
├─ Post-install validation
└─ Port conflict detection & resolution
```

---

### 1.2 Backend 감지 및 명령 통합 (integrations/ollama.sh)

**목표**: Docker와 로컬 바이너리를 자동으로 감지하여 통일된 인터페이스 제공

**경로**: `shell-common/tools/integrations/ollama.sh`

**핵심 캡슐화 함수**:

| 함수 | 역할 | 예시 |
|------|------|------|
| `ollama_backend_detect()` | 현재 사용 가능한 backend 판정 | → local \| docker \| unavailable |
| `ollama_cmd()` | 실행 경로 자동 선택 | `ollama_cmd list` → local or docker 자동 |
| `ollama_api_base_url()` | API 엔드포인트 반환 | → http://127.0.0.1:11434 |
| `ollama_normalize_model_name()` | 모델명 정규화 | gpt-oss-20b → gpt-oss:20b |

**작업 사항**:
- Backend 선택 규칙 구현 (위의 우선순위 로직)
- 환경변수 지원: `DOTFILES_OLLAMA_BACKEND`, `DOTFILES_OLLAMA_DOCKER_CONTAINER`
- Cross-shell 호환성 (bash/zsh): `$SHELL_COMMON` 기반 경로만 사용
- 출력 일관성: ux_lib 기반 (`ux_info`, `ux_error`, `ux_section` 등)

**산출물**:
```
shell-common/tools/integrations/ollama.sh
├─ ollama_backend_detect()
├─ ollama_cmd()
├─ ollama_api_base_url()
└─ ollama_normalize_model_name()
```

---

### 1.3 환경변수 설정 (Profile Integration)

**목표**: bash/zsh 초기화 시 Ollama 환경변수 자동 설정

**위치**: `~/.bashrc` / `~/.zshrc` 또는 `shell-common/env/ollama.env`

**설정 항목**:
```bash
export OLLAMA_NUM_CTX=65536          # 64K 컨텍스트
export OLLAMA_NUM_GPU=-1             # GPU 자동 감지
export OLLAMA_KEEP_ALIVE=5m          # 메모리 효율
export DOTFILES_OLLAMA_BACKEND=auto  # 또는 local|docker 강제
export DOTFILES_OLLAMA_DOCKER_CONTAINER=ollama
```

**산출물**: 환경변수 설정 파일 (추후 symlink로 로드)

---

## 🎯 Phase 2: 사용자-facing 함수 및 Alias (P0/P1/P2)

### P0: 기본 관리 함수 (필수)

**목표**: 사용자가 사용하는 고수준 함수들 구현

**경로**: `shell-common/tools/integrations/ollama.sh` 계속

| 함수 | 기능 | 예시 | Backend |
|------|------|------|---------|
| `ollama_version` | Ollama 버전 확인 | `ollama_version` | 자동 |
| `ollama_status` | 현재 상태/포트 확인 | `ollama_status` | 자동 |
| `ollama_models` | 설치된 모델 목록 | `ollama_models` | 자동 |
| `ollama_pull` | 모델 다운로드 | `ollama_pull gpt-oss:20b` | 자동 |
| `ollama_rm` | 모델 삭제 | `ollama_rm tinyllama` | 자동 |
| `ollama_show` | 모델 상세 정보 | `ollama_show gpt-oss:20b` | 자동 |
| `ollama_run` | 모델 실행 (대화) | `ollama_run gpt-oss:20b` | 자동 |

**규칙**:
- 모든 함수는 내부적으로 `ollama_cmd()` 사용
- 모델명 정규화 자동 적용 (`ollama_normalize_model_name`)
- UX 라이브러리로 출력 통일

---

### P1: 고급 관리 함수 (선택)

**목표**: Docker 전용 또는 고급 기능

| 함수 | 기능 | 예시 | 필수성 |
|------|------|------|--------|
| `ollama_logs` | Docker 컨테이너 로그 | `ollama_logs -f` | Docker only |
| `ollama_stats` | Docker 리소스 사용량 | `ollama_stats` | Docker only |
| `ollama_prompt` | 단일 프롬프트 실행 | `ollama_prompt gpt-oss:20b "설명"` | 선택 |

---

### P2: Alias 및 Help 함수 개선 (Hybrid 구조)

**목표**: WSL + Docker 이중 환경에서 seamless한 도움말 및 alias 제공

**경로**:
- `shell-common/functions/ollama_help.sh` (개선)
- `shell-common/aliases/ollama_aliases.sh` (신규)

#### 현재 상태 (Docker 전용)
```bash
# 현재 ollama_help.sh:58
alias ollama-help='ollama_help'  # ← Docker 명령만 표시
# 예: docker exec ollama ollama list
```

#### 개선 후 (Hybrid)
```bash
# ollama_help() 함수 개선
ollama_help [--docker|--local|--auto|--backend]
  --auto    (기본) 현재 활성 backend에 맞춘 도움말 표시
  --docker  Docker 전용 명령 표시
  --local   WSL Ollama 전용 명령 표시
  --backend 현재 감지된 backend 상태 표시

# 예시 동작
$ ollama-help --auto
# Phase 1 전: Docker 명령만 표시
# Phase 1 후: WSL Ollama 명령 표시 (로컬이 기본)

$ ollama-help --docker
# Docker 전용 명령만 표시 (언제든 사용 가능)
```

#### 함수 개선 사항

| 항목 | 현재 (Docker Only) | 개선 후 (Hybrid) |
|------|------------------|-----------------|
| **명령 예시** | `docker exec ollama ollama list` | `ollama_models` (자동 선택) |
| **backend 선택** | 고정 (Docker) | 자동 감지 + 명시적 옵션 |
| **포트 정보** | 11434 (Docker) | 11434 또는 환경변수 기반 |
| **상태 표시** | 없음 | 현재 활성 backend 표시 |
| **혼합 환경 대응** | 불가능 | ✅ seamless 지원 |

**산출물**:
```
shell-common/functions/ollama_help.sh (개선)
├─ ollama_help() 함수 재설계
│  ├─ --auto (기본): 활성 backend에 맞춤
│  ├─ --docker: Docker 명령 표시
│  ├─ --local: WSL 명령 표시
│  ├─ --backend: 현재 감지된 backend 표시
│  └─ 실시간 backend 감지 통합
│
└─ Alias 정의
   ├─ alias ollama-help='ollama_help --auto'
   ├─ alias llm-help='ollama_help --auto'
   └─ alias ollama-status='ollama_status'

shell-common/aliases/ollama_aliases.sh (신규)
└─ User-friendly aliases (자동 로드)
```

#### 🔄 Transition Plan (Migration)

**Phase 1 시작 전** (현재):
```bash
$ ollama-help
# → Docker 명령만 표시
```

**Phase 1 후** (WSL Ollama 설치):
```bash
$ ollama-help
# → WSL Ollama 명령 표시 (로컬 우선)
# 하지만 docker-help 섹션도 보조로 표시 가능

$ ollama-help --docker
# → Docker 전용 명령만 표시
```

---

## 🎯 Phase 3: Claude Code/LiteLLM 통합 (P1)

### 3.1 Ollama Launch 설정

**목표**: `ollama launch claude` 명령어 작동 확인

**작업 사항**:
- Ollama 버전 확인 (0.13.0+에서 지원)
- Claude Code 호환성 검증: v2.1.31 호환 확인
- API 호환성: Anthropic API 호환 설정
- 포트 연결 확인 (11434 또는 환경변수 포트)

**참고 문서**:
```
@docs/technic/ollama-local-claude-code-integration.md
└─ "2. Ollama Launch: 원클릭 AI 실행의 마법" 섹션
```

---

### 3.2 LiteLLM 연동 검증

**목표**: LiteLLM 프로젝트에서 로컬 Ollama 사용 가능 확인

**작업 사항**:
- LiteLLM 설정 파일(`litellm_settings.yml`)에서 Ollama endpoint 지정
  - Docker: `http://ollama:11434` (컨테이너 네트워크)
  - 로컬: `http://127.0.0.1:11434` (WSL 호스트)
- 모델명 표기 표준화: `gpt-oss:20b` (Ollama 태그)
- API 테스트: `ollama_cmd list` 후 LiteLLM에서 확인

---

### 3.3 컨텍스트 길이 최적화 검증

**목표**: 64K 컨텍스트 설정이 제대로 작동하는지 확인

**작업 사항**:
- `ollama_show <model>` 명령어로 context length 확인
- 모델별 컨텍스트 길이 표시 함수 추가
- 설정 변경 방법 문서화

**예상 출력**:
```
$ ollama_show gpt-oss:20b
  context length      131072    ✓ (충분함)
```

---

## 🚨 현재 주요 이슈 (Issues)

### 🔴 High Priority

| 이슈 | 현재 상황 | 영향 | 해결 방법 |
|------|---------|------|----------|
| **도움말 Docker 전용** | `ollama_help.sh:58`이 Docker만 가정 | WSL Ollama 설치 후 명령어 통일 불가 | Hybrid 아키텍처 + `--auto/--docker/--local` |
| **Backend 불명확성** | 현재 Docker 고정 → Phase 1 후 충돌 | WSL 설치 시 두 Ollama 간 우선순위 불명확 | Backend 선택 규칙 명시 (로컬 우선) |
| **포트 충돌 리스크** | Docker 11434 점유 → 로컬 11434 충돌 | WSL Ollama 설치 후 포트 경합 | 설치 스크립트에서 감지 + 대체 포트 설정 |
| **모델 저장소 분리** | Docker: `/root/.ollama`, WSL: `~/.ollama` | 모델이 두 곳에 분산 저장 | 사용자 선택: 통합 또는 분리 운영 |

### 🟡 Medium Priority

| 이슈 | 영향 | 해결 방법 |
|------|------|----------|
| **Alias 위치** | Alias가 함수 파일에 혼재 → 로딩 순서 혼란 | `shell-common/aliases/ollama_aliases.sh` 신규 생성 |
| **Cross-shell 호환** | `BASH_SOURCE` 등 bash 전용 코드 → zsh 미지원 | `$SHELL_COMMON` 기반 경로만 사용 |
| **출력 일관성** | 도구별 `echo` 남발 → 스타일 통일 불가 | ux_lib (`ux_info`, `ux_error` 등) 강제 사용 |

### 🟢 Low Priority

| 이슈 | 영향 | 해결 방법 |
|------|------|----------|
| **모델명 혼선** | 사용자 기억 `gpt-oss-20b` vs Ollama `gpt-oss:20b` | `ollama_normalize_model_name()` 함수로 자동 변환 |
| **테스트 부족** | Docker/로컬/혼합 환경 검증 불완전 | 스모크 테스트 추가 (P2) |

---

## 🎯 Phase 4: 자동화 및 최적화 (P2)

### 4.1 검증 및 테스트 (Validation Checklist)

**목표**: 다양한 환경에서 올바르게 작동하는지 수동 검증

**시나리오별 검증**:

#### A) Docker만 존재하는 경우
```bash
# 도커 환경 전용 명령 확인
ollama_backend_detect  # → docker
ollama-help --docker   # Docker 명령만 표시
ollama_models          # docker exec ollama ollama list 실행
```

#### B) 로컬 바이너리만 존재하는 경우
```bash
# 로컬 환경 전용 명령 확인
ollama_backend_detect  # → local
ollama-help --local    # 로컬 명령만 표시
ollama_models          # /usr/bin/ollama list 실행
```

#### C) 둘 다 존재하는 경우 (우선순위 테스트)
```bash
# 로컬이 우선되는지 확인
DOTFILES_OLLAMA_BACKEND=auto ollama_backend_detect  # → local (우선)
# 또는 환경변수로 강제
DOTFILES_OLLAMA_BACKEND=docker ollama_backend_detect  # → docker (강제)
```

#### D) 모델 정규화 테스트
```bash
# 사용자 입력을 Ollama 태그로 변환
ollama_pull gpt-oss-20b  # → gpt-oss:20b로 자동 변환
```

---

### 4.2 포트 충돌 해결 및 모니터링

**목표**: 11434 포트 충돌 감지 및 자동 해결

**작업 사항**:
- `install_ollama.sh`에서 포트 충돌 감지
  ```bash
  lsof -i :11434  # 포트 사용 중인 프로세스 확인
  ```
- 해결 옵션 제시:
  1. 도커 일시 중지: `docker stop ollama`
  2. 로컬 포트 변경: `export OLLAMA_HOST=127.0.0.1:11435`
- `ollama_status` 함수에서 현재 포트 및 상태 표시

---

## 💡 기대 효과

| 항목 | 효과 | 비고 |
|------|------|------|
| **비용 절감** | 외부 API 비용 0원 | Claude API 호출 없이 로컬 처리 |
| **데이터 보안** | 100% 프라이빗 | 모든 데이터가 로컬 환경에서만 처리 |
| **개발 경험** | 무제한 실험 가능 | API 레이트 리밋 없음, 토큰 제한 없음 |
| **학습 가치** | AI 내부 동작 이해 | 모델 구조, MoE 메커니즘 실험 가능 |
| **백업 환경** | 클라우드 서비스 장애 대응 | Claude Code 대체 수단 확보 |
| **재사용성** | 다중 환경 지원 | Docker, WSL, 로컬 Linux 모두 지원 |

---

## 📁 디렉토리 구조 및 파일 목록

```
shell-common/
├── functions/
│   ├── ollama_help.sh (개선)
│   │   └─ ollama_help() - Docker/Local/Auto 모드 지원
│   │
├── aliases/
│   └── ollama_aliases.sh (신규)
│       ├─ alias ollama-help='ollama_help'
│       └─ alias llm-help='ollama_help'
│
├── tools/
│   ├── integrations/
│   │   └── ollama.sh (신규)
│   │       ├─ Backend Detection Layer
│   │       │  ├─ ollama_backend_detect()
│   │       │  ├─ ollama_cmd()
│   │       │  ├─ ollama_api_base_url()
│   │       │  └─ ollama_normalize_model_name()
│   │       │
│   │       ├─ P0: Basic Functions (필수)
│   │       │  ├─ ollama_version()
│   │       │  ├─ ollama_status()
│   │       │  ├─ ollama_models()
│   │       │  ├─ ollama_pull()
│   │       │  ├─ ollama_rm()
│   │       │  ├─ ollama_show()
│   │       │  └─ ollama_run()
│   │       │
│   │       └─ P1: Advanced Functions (선택)
│   │           ├─ ollama_logs()
│   │           ├─ ollama_stats()
│   │           └─ ollama_prompt()
│   │
│   └── custom/
│       └── install_ollama.sh (신규)
│           ├─ Pre-check logic
│           ├─ Installation
│           ├─ Post-validation
│           └─ Port conflict detection
│
└── env/
    └── ollama.env (신규)
        ├─ OLLAMA_NUM_CTX=65536
        ├─ OLLAMA_NUM_GPU=-1
        ├─ OLLAMA_KEEP_ALIVE=5m
        └─ DOTFILES_OLLAMA_BACKEND=auto
```

---

## 📊 Implementation Priority (P0/P1/P2)

| Priority | Phase | 항목 | 예상 진도 |
|----------|-------|------|----------|
| **P0** | Phase 1 | Backend 감지 + 통합 명령 (`ollama_backend_detect`, `ollama_cmd`) | 🔴 **필수** |
| **P0** | Phase 1 | 설치 스크립트 (`install_ollama.sh`) | 🔴 **필수** |
| **P0** | Phase 2 | 기본 관리 함수 (버전, 상태, 모델 조회 등) | 🔴 **필수** |
| **P0** | Phase 2 | Alias 재정렬 (`ollama_aliases.sh`) | 🔴 **필수** |
| **P1** | Phase 3 | Claude Code / LiteLLM 연동 검증 | 🟡 **중요** |
| **P1** | Phase 3 | 컨텍스트 길이 검증 | 🟡 **중요** |
| **P1** | Phase 4 | 포트 충돌 해결 | 🟡 **중요** |
| **P2** | Phase 4 | 테스트 자동화 (스모크 테스트) | 🟢 **선택** |
| **P2** | Phase 4 | 성능 모니터링 함수 | 🟢 **선택** |

---

## 🔧 기술 스택

| 도구 | 버전 | 용도 | 상태 |
|------|------|------|------|
| **Ollama** | 0.13.1+ (Docker) | 로컬 LLM 실행 엔진 | ✅ 설치됨 (Docker) |
| **Ollama** | 최신 (WSL) | 로컬 LLM 실행 엔진 | ⏳ WSL 설치 필요 |
| **GLM 4.7 Flash** | 최신 | 기본 모델 (30B MoE) | ❌ 미설치 |
| **Claude Code** | v2.1.31 | IDE 및 AI 코딩 에이전트 | ✅ 설치됨 |
| **Bash/Zsh** | 현재 | 쉘 함수 및 자동화 | ✅ 사용 가능 |
| **Docker** | 설치됨 | 컨테이너 Ollama | ✅ 동작 중 |

---

## 🖥️ 시스템 요구사항

| 요구사항 | 최소사양 | 권장사양 | 비고 |
|---------|---------|---------|------|
| **WSL 버전** | WSL2 | WSL2 + Ubuntu 22.04 | 64K 컨텍스트 처리 필수 |
| **GPU** | 선택사항 | NVIDIA RTX 30xx 이상 | CUDA 지원 필수 (추천) |
| **VRAM** | 8GB | 16GB+ | GLM 4.7 Flash: ~10-15GB |
| **메모리** | 16GB | 32GB+ | 컨텍스트 길이 64K 운영용 |
| **저장소** | 50GB | 100GB+ | 모델 다운로드 및 임시 파일 |
| **네트워크** | 필요 없음 | - | 모든 처리가 로컬에서 수행 |

---

## 📊 Phase별 예상 진행도

| Phase | 설명 | 예상 진도 |
|-------|------|----------|
| Phase 1 | 기초 인프라 | 🔄 **진행 중** |
| Phase 2 | 쉘 함수 | ⏳ **대기** |
| Phase 3 | Claude Code 통합 | ⏳ **대기** |
| Phase 4 | 자동화 및 최적화 | ⏳ **대기** |

---

## 🚀 다음 단계

1. **shell-common/tools/integrations/ollama.sh** 파일 생성
2. Phase 1 구현: `ollama_install_host()`, `ollama_setup_env()`
3. Phase 2 구현: 관리 함수 개발
4. Phase 3 구현: Claude Code 통합 테스트
5. Phase 4 구현: 성능 최적화

---

## 📝 참고 문서

- [@docs/technic/ollama-local-claude-code-integration.md](/home/bwyoon/dotfiles/docs/technic/ollama-local-claude-code-integration.md)
  - 로컬 AI 코딩의 기초 개념, 성능 기대치, 장단점 분석

- [@docs/review/abc-review-G.md](/home/bwyoon/dotfiles/docs/review/abc-review-G.md)
  - 동료의 통합 설계 의견 (Gemini 관점)

- [@shell-common/functions/ollama_help.sh](/home/bwyoon/dotfiles/shell-common/functions/ollama_help.sh)
  - 현재 ollama-help 함수 (Docker 방식 중심)

- [Ollama 공식 문서](https://ollama.ai)
  - 공식 설치 가이드 및 모델 라이브러리

---

## 🔄 협력 이력 및 버전 관리

| 버전 | 작성자 | 주요 기여사항 |
|------|--------|----------------|
| v1.0 | Claude | 초기 계획 (4 Phase 구조, 기대효과, 시스템 요구사항) |
| v2.0 | Claude | 동료 G 피드백 통합 (현재 상태, 재사용성) |
| **v3.0** | **Claude** | **동료 CX 피드백 통합 + SOLID 평가 + P0/P1/P2 우선순위** ✓ |

**동료들의 주요 피드백**:

- **동료 G (abc-review-G.md)**:
  - 현실적인 상황 분석 (Claude Code v2.1.31, GLM 미설치)
  - 기대 효과 명시 (비용 절감, 보안 강화)
  - Dotfiles 재사용성 강조

- **동료 CX (abc-review-CX.md)**:
  - SOLID 원칙 평가 (설계 품질 38/50)
  - 구체적 Backend 선택 규칙 (우선순위 로직)
  - P0/P1/P2 우선순위 기반 구현 계획
  - 실전적 검증 체크리스트
  - Direct-exec guard, 포트 충돌 감지 등 세부 구현 사항

---

**Last Updated**: 2026-02-04
**Status**: ✅ **V3.1 완성** (WSL + Docker Hybrid 아키텍처 확정) → **Phase 1 구현 시작 준비 완료**

**V3.1 핵심 추가 사항**:
- ✅ Hybrid 아키텍처 명확화 (seamless + smart)
- ✅ Backend 선택 규칙 구체화 (우선순위 로직)
- ✅ `ollama-help` 개선 전략 (--docker/--local/--auto)
- ✅ 모델 저장소 전략 (분리 vs 통합)

---

## 🏗️ 아키텍처 결정 가이드 (WSL + Docker 통합)

### 시나리오별 사용 전략

---

#### Scenario A: Docker Ollama 전용 (현재, Phase 1 전)
```bash
$ ollama_models
# → docker exec ollama ollama list 실행
# 모든 모델이 Docker 볼륨에 저장 (/root/.ollama)
```

---

#### Scenario B: WSL + Docker 이중 운영 (권장, Phase 1 후)
```bash
# 1️⃣ 기본 (로컬 우선)
$ ollama_models
# → WSL Ollama 사용 (더 빠름)

# 2️⃣ Docker가 필요한 경우 (LiteLLM 테스트 등)
$ ollama_models --docker
# → Docker Ollama 사용

# 3️⃣ 환경변수로 강제
$ export DOTFILES_OLLAMA_BACKEND=docker
$ ollama_models
# → Docker Ollama 사용 (환경 변수 설정 해제까지)
```

---

#### Scenario C: WSL Ollama 전용 (선택)
```bash
# Docker를 중단하고 WSL만 사용하려면:
$ docker stop ollama
$ ollama_models
# → WSL Ollama 사용

# 또는 강제 설정:
$ export DOTFILES_OLLAMA_BACKEND=local
```

### 🎯 모델 저장소 전략

| 전략 | 장점 | 단점 | 추천 |
|------|------|------|------|
| **분리 운영** | 각 환경 독립적 관리, 용량 최소화 | 모델 중복 다운로드 필요 | 테스트 환경 |
| **통합 운영** | 한 번 다운로드 → 양쪽 모두 접근 | 복잡한 마운트 설정 | ❌ 비추천 |
| **우선순위 기반** | WSL에서 필요한 모델만 설치 | 약간의 추가 관리 | ✅ **권장** |

**추천 전략**:
- **WSL Ollama**: 주로 사용하는 모델 (GLM 4.7 Flash, gpt-oss:20b)
- **Docker Ollama**: LiteLLM 테스트, 별도 실험 모델

---

## 🚀 다음 액션 (Next Steps)

1. ✅ 계획 문서 완성 (V3.0)
2. ⏳ **Phase 1 구현 시작**:
   - `shell-common/tools/custom/install_ollama.sh` 작성
   - `shell-common/tools/integrations/ollama.sh` 작성 (Backend 감지 로직)
3. ⏳ **Phase 2 구현**: 사용자 함수 + Alias 정리
4. ⏳ **Phase 3 검증**: Claude Code / LiteLLM 연동
5. ⏳ **Phase 4 테스트**: 모든 시나리오 검증
