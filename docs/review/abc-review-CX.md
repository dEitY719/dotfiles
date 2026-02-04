# [CX] WSL 환경 Ollama 통합 구현 계획 (Docker 컨테이너 + 로컬 바이너리)

## 1. Reviewer Info

- Reviewer: ChatGPT (GPT-5.2, Codex CLI)
- Date: 2026-02-04
- Scope: dotfiles에 Ollama 실행/관리/도구연동(Claude Code, LiteLLM)을 표준화

## 2. Current State Summary

- Docker 컨테이너 `ollama` 내부에서 `ollama 0.13.1`이 `serve`로 실행 중
- WSL 호스트에는 `ollama` 바이너리가 설치되어 있지 않음 (`command -v ollama` 실패)
- 과거 `litellm` 프로젝트에서 `gpt-oss-20b`(Ollama 표기: `gpt-oss:20b`) 모델을 사용한 이력 있음

이 상태에서 필요한 것은 “도커 기반 Ollama”와 “WSL 로컬 Ollama”를 모두 지원하는 일관된 UX(명령어/헬프/설치)입니다.

## 3. Project Structure (Relevant)

- `shell-common/tools/integrations/`: 외부 도구 wrapper (자동 로드; bash/zsh 공용을 목표)
- `shell-common/tools/custom/`: 직접 실행하는 유틸 스크립트 (반드시 direct-exec guard 필요)
- `shell-common/functions/`: 쉘 함수(자동 로드; aliases 이후 로드)
- `shell-common/aliases/`: alias 전용(자동 로드; 함수보다 먼저 로드)
- `docs/technic/ollama-local-claude-code-integration.md`: 최종 목표(예: `ollama launch claude`)에 대한 방향성 문서

## 4. SOLID Evaluation (Target Design)

- SRP (7/10): “Ollama 통합”을 한 파일로 묶되, 설치(install)와 런타임 wrapper를 분리하면 점수 상승
- OCP (8/10): backend(로컬/도커) 추가를 env var + 감지 로직으로 확장 가능
- LSP (7/10): 동일한 사용자 명령이 backend에 따라 동작만 바뀌고 의미는 유지돼야 함
- ISP (8/10): `ollama_*` 단위 함수 + 얇은 사용자 명령 조합으로 과도한 만능함수 방지
- DIP (8/10): “로컬 바이너리/도커 exec” 구현 세부사항을 `ollama_cmd`에 캡슐화

총점: 38/50

## 5. Issues (Why This Plan Is Needed)

### High

- Backend 불명확성: 현재는 도커 컨테이너 기반만 암묵적으로 가정(WSL 로컬 설치/연동 시 충돌 가능)
- 도움말 불완전: `ollama_help`가 도커 명령만 안내하므로 “로컬 설치 후” UX가 단절됨
- 포트 충돌 리스크: 도커가 `11434`를 이미 점유 중이면 로컬 `ollama serve`는 기본 설정으로 충돌

### Medium

- Alias 위치: alias는 `shell-common/aliases/`에 있어야 로딩 순서/규칙이 명확해짐
- Cross-shell 호환: `BASH_SOURCE` 등 bash 전용을 피하고 `$SHELL_COMMON` 기반 경로를 사용해야 함
- 출력 일관성: ux_lib 기반 출력으로 통일(도구별 임의 `echo` 남발 방지)

### Low

- 모델 이름 혼선: 사용자 기억(`gpt-oss-20b`)과 Ollama 태그(`gpt-oss:20b`) 차이로 사용성 저하

## 6. Implementation Plan (Action Items)

### P0. `shell-common/tools/integrations/ollama.sh` 신규 생성

목표: “명령 1개(또는 함수 1세트)”로 로컬/도커 backend를 통일해 사용 가능하게 만들기.

핵심 설계:

- Backend 선택 규칙(우선순위):
  1. `DOTFILES_OLLAMA_BACKEND`가 `local|docker`면 강제
  2. 로컬 `ollama` 바이너리 존재 시 `local`
  3. 도커 컨테이너 이름(기본 `ollama`)이 존재하고 exec 가능하면 `docker`
  4. 그 외: 사용 불가로 안내
- 컨테이너 이름/옵션:
  - `DOTFILES_OLLAMA_DOCKER_CONTAINER` 기본값: `ollama`
- 구현 캡슐화:
  - `ollama_backend_detect`
  - `ollama_cmd ...` (실행 경로를 `ollama ...` 또는 `docker exec <container> ollama ...`로 통일)
  - `ollama_api_base_url` (예: `http://127.0.0.1:11434`)
  - (선택) `ollama_normalize_model_name`로 `gpt-oss-20b` → `gpt-oss:20b` 변환

사용자-facing 함수(예시):

- `ollama_version`, `ollama_status`
- `ollama_models` (`ollama list`)
- `ollama_pull <model>`, `ollama_rm <model>`, `ollama_show <model>`
- `ollama_run <model> [prompt...]`
- (도커일 때만 의미 있는) `ollama_logs`, `ollama_stats`

### P0. 설치 스크립트 추가: `shell-common/tools/custom/install_ollama.sh`

목표: WSL 호스트에 Ollama 바이너리 설치를 재현 가능하게 만들기.

- 동작:
  - 이미 설치되어 있으면 버전 출력 후 종료
  - Linux 공식 설치 스크립트 기반 설치(네트워크 필요, sudo 필요)
  - 설치 후 `ollama --version` 확인
  - (선택) 포트 충돌 안내: 도커가 `11434`를 쓰는 중이면 도커 중단 또는 로컬 포트 변경 가이드 제공
- UX/규칙:
  - ux_lib 사용
  - `shell-common/tools/custom/` 규칙에 따라 파일 맨 끝에 direct-exec guard 추가

### P0. 도움말/명령 UX 정리: `ollama-help`

목표: 도움말이 “도커/로컬 모두”를 안내하고, 실제 실행도 자동 선택으로 이어지게 만들기.

- `shell-common/functions/ollama_help.sh`:
  - `--docker`, `--local`, `--auto`(기본) 옵션으로 도움말 섹션 분리
  - 가능하면 `ollama_cmd`를 사용해 “실제 실행 예시”가 현재 backend에 맞게 보이도록 구성
- `shell-common/aliases/ollama_aliases.sh` 신규:
  - `alias ollama-help='ollama_help'`
  - `alias llm-help='ollama_help'`
  - (선택) `alias ollama-models='ollama_models'` 같은 사용자 명령 체계는 합의 후 결정

### P1. Claude Code/LiteLLM 연동 포인트 정리

- `docs/technic/ollama-local-claude-code-integration.md`에 맞춰 아래를 검증/문서화:
  - `ollama launch claude` 서브커맨드가 현재 사용하는 Ollama(도커/로컬)에서 실제로 제공되는지 확인
  - LiteLLM에서 사용할 endpoint 및 모델명 표기(`gpt-oss:20b`) 고정

### P2. 최소 검증(테스트/스모크) 추가

- bash/zsh에서 동일하게 로드되는지 확인하는 스모크 테스트 추가(가능하면 `tests/`에 자동화)
- “도커만 있는 환경”, “로컬만 있는 환경”, “둘 다 있는 환경”을 각각 가정한 분기 테스트

## 7. Validation Checklist (Manual First)

- WSL 로컬 설치 전(도커만 존재):
  - `ollama-help --docker` 출력 확인
  - `ollama_models`가 `docker exec ...`로 동작하는지 확인
- WSL 로컬 설치 후(로컬 존재):
  - `DOTFILES_OLLAMA_BACKEND=local`에서 로컬 `ollama`로 동작하는지 확인
  - 도커와 포트 충돌 여부 확인(11434)
- 모델:
  - `ollama_pull gpt-oss:20b` 또는 `ollama_pull gpt-oss-20b`가 기대대로 처리되는지 확인

## 8. Conclusion

`integrations/ollama.sh`로 “backend 추상화”를 만들고, `install_ollama.sh`로 “WSL 로컬 설치 재현성”을 확보한 뒤,
`ollama-help`를 “도커/로컬 동시 안내”로 확장하면 문서의 최종 목적(로컬 AI 코딩 환경)으로 자연스럽게 이어집니다.
