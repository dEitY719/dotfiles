# abc-review-CX

## Reviewer info

- **Reviewer**: CX (GPT-5.2 / Codex CLI)
- **Date**: 2026-02-02
- **Scope**: `docs/review/abc-review-CM.md`, `docs/review/abc-review-R.md` 문서 내용(개선 제안/리뷰 품질) 피드백

## 전제: SSOT 섹션은 평가 제외

- SSOT는 `~/para/archive/rca-knowledge`로 결정되어 있으므로, 두 문서의 SSOT 관련 주장/액션 아이템은 현 기준과 불일치합니다.
- 본 문서에서는 **SSOT 자체의 타당성 평가**는 생략하고, “문서가 현재 합의와 다르다”는 점만 정정 포인트로 다룹니다.

## 전체 총평

- 두 문서 모두 “초기화 로더(`bash/main.bash`, `zsh/main.zsh`)가 책임이 크다”는 핵심을 잘 짚었습니다.
- 다만 일부는 **레포 현재 상태와 불일치**(이미 존재하는 파일/동작을 “없다”로 서술)하거나, **프로젝트 규칙(경로 하드코딩/출력 UX/이모지 금지)**을 문서에서 충분히 반영하지 못했습니다.

## 좋은 점

### `abc-review-CM.md`에서 좋았던 점

- `bash/main.bash`/`zsh/main.zsh`의 책임 과다(SRP)와 로딩 로직 확장(OCP) 문제를 명확히 구조화했습니다.
- 개선안을 “모듈 분리 → 로더 추상화 → 테스트 추가”로 연결해 **실행 가능한 흐름**을 제시했습니다.

### `abc-review-R.md`에서 좋았던 점

- 문서 포맷(리뷰어 정보 → 구조 요약 → 평가 → 이슈/액션)이 `docs/AGENTS.md`의 리뷰 템플릿에 가장 가깝습니다.
- 리스크 기반(High/Medium/Low)으로 우선순위를 제시해 실행 계획으로 전환하기 쉽습니다.

## 정정이 필요한 사실(중요)

### `abc-review-CM.md`

- `shell-common/tools/integrations/opencode.sh`는 “신규 생성”이 아니라 **이미 존재**합니다. 현재 문제는 `bash/main.bash` 하단에 있는 `export PATH=/home/bwyoon/.opencode/bin:$PATH` 같은 **하드코딩/중복**에 더 가깝습니다.
- `shell-common/util/` 디렉터리는 현재 구조에 없습니다. 새 디렉터리를 도입하려면 `shell-common/AGENTS.md`의 구조/로딩 규칙과 함께 설계를 제시하는 편이 안전합니다.
- 문서 메타데이터의 `생성일: $(date '+%Y-%m-%d')`는 마크다운에서 실행되지 않아 **그대로 문자열로 남습니다**. 실제 날짜로 고정하거나 생성 파이프라인을 명시하세요.

### `abc-review-R.md`

- `shell-common/tools/custom/make_jira.sh`, `shell-common/tools/custom/make_confluence.sh`는 **이미 존재**합니다(또한 `shell-common/aliases/work-aliases.sh`에 alias도 존재). “제안만 있고 구현되지 않았다”는 진술은 수정이 필요합니다.
- “주요 AGENTS 파일” 링크가 `AGENTS.md:1` 같은 형태로 되어 있는데, 표준 마크다운 링크로는 동작하지 않습니다. 예: `../../AGENTS.md`, `../AGENTS.md`, `../../shell-common/AGENTS.md`처럼 상대 경로로 바꾸는 편이 좋습니다.

## 문서 품질/표현 개선(SSOT 제외)

### High

- 두 문서의 마지막에 있는 `# 대답하지 말고 기다려.` 문구는 리뷰 산출물로는 부적절합니다(에이전트 프롬프트 잔재로 보임). 삭제를 권장합니다.
- 규칙 반영: 프로젝트는 “이모지 금지”, “출력은 `ux_lib`로 통일”, “경로 하드코딩 금지($HOME 사용)” 같은 골든 룰이 있습니다. 관련 개선안을 낼 때는 해당 룰 위반 사례를 **구체 파일/라인 단위로** 연결해 주는 편이 설득력이 큽니다.

### Medium

- 근거 강화: “책임 혼합”, “조건 블록 과다”, “LSP 위반” 같은 평가는 동의하더라도, 최소 1~2개의 구체 예시(함수/파일/명령)로 근거를 붙이면 합의 비용이 줄어듭니다.
- 리팩터링 제안은 “새 파일 추가”만으로 끝내지 말고, “어떤 로딩 단계에서 어떻게 포함되는지(자동 소스 vs 직접 실행)”를 함께 적어야 안전합니다.

### Low

- 용어 통일: `tools/integrations` vs `tools/integration`, `shell-common/util` 같은 새 분류 제안은 실제 트리와 일치하도록 표현을 정리하세요.

## 액션 아이템(추천)

- [ ] **P0**: 두 문서에서 SSOT 섹션을 현 합의(`~/para/archive/rca-knowledge`)에 맞게 정정하거나, “본 레포 범위 밖”으로 명확히 제외
- [ ] **P0**: 사실 오류 정정(이미 존재하는 `opencode.sh`, `make_jira.sh`, `make_confluence.sh`) 및 링크 경로 수정
- [ ] **P1**: `bash/main.bash`, `zsh/main.zsh`의 로더 책임 분리 제안은 “현 구조 제약(부트스트랩 단계/크로스쉘/자동 소싱 규칙)”을 반영한 형태로 재작성
- [ ] **P1**: 문서 말미의 프롬프트 잔재 제거 및 생성일 표기 고정(또는 생성 방식 명시)
