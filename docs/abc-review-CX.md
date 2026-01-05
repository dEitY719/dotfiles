# Dotfiles SOLID Review (ChatGPT)

> **Reviewer**: ChatGPT (GPT-5)
> **Review Date**: 2026-01-06
> **Scope**: `shell-common/**/*` (env, aliases, functions, tools, projects)

---

## 1. 프로젝트 구조 요약

- `env/`: 환경 변수와 기본 설정 파일 8개, 일부는 bash 전용 로직 포함
- `aliases/`: 공통 별칭 묶음 8개, 일부 파일에 함수와 복잡 로직 혼재
- `functions/`: 헬프/도구 함수 30+개, UX 라이브러리 의존
- `tools/`: `external/`(통합 스크립트), `custom/`(설치/유틸), `ux_lib/`(스타일)
- `projects/`: 프로젝트별 유틸 3개

---

## 2. SOLID 원칙 평가 (10점 만점)

- **SRP 5/10**: env/aliases 파일에 함수·도구 설치 도움말이 섞여 책임 범위가 흐려짐.
- **OCP 6/10**: 디렉터리 추가만으로 확장 가능하지만 공용 영역에 bash 전용 코드가 섞여 확장 시 수정 부담이 생김.
- **LSP 5/10**: POSIX를 표방하지만 `#!/bin/bash`, `declare`, `local -A` 등이 공용 파일에 존재해 zsh/posix 대체성이 흔들림.
- **ISP 6/10**: alias 이름 충돌(`ai`)과 헬프/UX 출력이 파일마다 제각각이라 사용자가 좁은 인터페이스만 소비하기 어려움.
- **DIP 6/10**: 다수 스크립트가 UX 라이브러리를 우회하거나 직접 `echo`/이모지에 의존해 공용 추상화(ux_lib)와 분리됨.

---

## 3. 발견된 이슈

### High

- `shell-common/env/proxy.sh:1-116`: 환경 변수 정의 파일이 UX 로더, 헬프 함수, 진단 alias까지 모두 포함. POSIX가 아닌 `#!/bin/bash`와 `declare`를 사용하고 이모지/직접 `echo`도 섞여 SRP·출력 규칙 모두 위반.
- `shell-common/aliases/directory.sh:37-207`: 별칭 파일에 대형 `cp_wdown` 함수가 포함되고 `local -a`, `compgen`, 프로세스 제어까지 수행. POSIX shebang과 달리 bash 전용 구문을 사용해 공용 로더에서 치환 가능성이 낮아짐.
- Alias 충돌 `ai`: `shell-common/aliases/mytool.sh:15`(agents_init)와 `shell-common/tools/external/apt.sh:21`(apt install)이 서로 덮어써 용도별 인터페이스가 겹침.

### Medium

- `shell-common/env/security.sh:1-33` 및 `shell-common/env/security.local.example:11-16`: env 레이어에 bash 전용 `BASH_SOURCE` 사용과 다수 이모지 포함. 로컬 템플릿도 “No Emojis” 규칙을 위반하고 UX 없이 직접 `echo` 패턴을 유도.
- `shell-common/tools/external/git.sh:127-178` 및 `shell-common/tools/custom/init.sh:28-46`: 공용 출력 규칙을 벗어나 직접 `echo`와 이모지를 사용하며 UX 추상화 없이 사용자 메시지를 생성. DIP와 스타일 일관성을 해침.

### Low

- `shell-common/README.md` vs 실제 코드: README는 env/aliases가 “POSIX, 별칭/환경 전용”이라 서술하지만 `env/proxy.sh`, `aliases/kill.sh` 등은 함수·bash 구문을 포함해 문서/구현 불일치.

---

## 4. 액션 아이템 (우선순위 순)

1. `env/proxy.sh`를 환경 변수 전용 파일로 축소하고, 헬프/alias/진단 래퍼를 `functions/` 또는 `tools/custom/`로 이동 후 POSIX/ux_lib 스타일로 재작성.
2. `aliases/directory.sh`에서 `cp_wdown`를 별도 함수/스크립트로 분리하고 bash 전용이면 명시적 가드(`[[ $- == *i* ]]` 등)와 적절한 위치(`functions/` 또는 `tools/custom/`)로 이동.
3. `ai` 충돌 제거: apt 별칭을 다른 접두사로 바꾸거나 agents_init 단축키를 프로젝트 전용 접두사로 변경해 인터페이스 분리.
4. 보안/도구 스크립트의 이모지와 직접 `echo`를 UX 함수로 교체하고, bash 전용 구문 사용 시 파일 레이어(공용 vs bash 전용)와 문서를 일치시키기.
5. README를 실제 책임 분리에 맞게 업데이트하거나 코드 정리를 통해 “env=export-only, aliases=alias-only” 계약을 복원.

---

## 5. 결론

- **총점: 28/50** (SRP와 LSP 편차가 가장 큼)
- 핵심 위험은 공용 레이어에 섞인 bash 전용 로직과 alias 충돌로, 사용자가 기대하는 일관된 인터페이스와 POSIX 호환성을 약화시킴. 우선 환경/별칭 파일을 분리 정리하고 출력 규칙을 단일 UX 추상화에 맞추는 리팩터링이 필요함.
