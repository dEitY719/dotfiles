# Command Delivery Model — 함수 vs PATH 실행파일

## 목적

셸 명령을 만들기 **전에** 가장 먼저 결정해야 하는 축 — **전달 방식(delivery
model)**의 SSOT다. 즉 명령을 **셸 함수**로 제공할지
**PATH 위의 실행파일**로 제공할지를 정한다.

이것은 [`command-design-pattern.md`](./command-design-pattern.md)(함수의 *내부
구조* — dispatcher/sub-function)의 **한 단계 위 축**이다. 내부 구조를 고민하기
전에, 애초에 함수여야 하는지부터 결정한다 (step 0).

## 적용 범위

- 새 셸 명령을 추가하기 직전의 설계 결정
- 기존 명령의 전달 방식 전환 (함수 ↔ 실행파일, 예: #1023 / PR #1024)

## 1. 핵심 원리

| 전달 방식 | 프로세스 경계 | 비-인터랙티브 자식에서 보임? |
|-----------|---------------|------------------------------|
| 셸 함수 | **넘지 못함** | 아니오 |
| PATH 실행파일 | **넘음** (export env) | 예 |

- **셸 함수는 프로세스 경계를 못 넘는다.** 부모 셸에서 정의돼도 자식 프로세스로
  상속되지 않는다. `bash -c "myfunc"`처럼 새 셸을 띄우면 그 함수는 존재하지 않는다.
- **PATH는 exported env라 모든 자식 프로세스로 상속된다.** 그래서 PATH 위의
  실행파일은 인터랙티브/비-인터랙티브 어디서든, 어떤 자식 셸에서든 잡힌다.

## 2. 인터랙티브 vs 비-인터랙티브

dotfiles의 함수는 인터랙티브 셸에서만 로드된다. 모든 함수 파일 맨 앞의
interactive 가드가 비-인터랙티브 셸에서 source를 조기 종료시키기 때문이다:

```sh
case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac
```

- **인터랙티브 셸** (`$-`에 `i` 포함) — 사람이 직접 타이핑하는 터미널. 함수가
  로드돼 있다.
- **비-인터랙티브 셸** — 스크립트, cron, 그리고 **AI 코딩 에이전트(Claude Code
  등)의 `bash -c "..."`**. 함수는 로드되지 않는다.

AI 에이전트는 명령을 `bash -c "..."` 비-인터랙티브 셸로 실행하므로, **함수 형태
명령은 AI가 호출할 수 없다** (#1023에서 실증 — 함수였던 `obsidian`을 AI가 못
불러서 PATH 실행파일로 전환).

## 3. 결정 트리

```
부모 셸 상태(cwd / 현재 셸 env / alias)를 바꿔야 하나?
     │
     ├── 예 ──> 반드시 함수
     │          (실행파일은 자식 프로세스라 부모 cwd/env를 못 바꾼다)
     │
     └── 아니오
          │
     AI / 스크립트 / cron(비-인터랙티브)도 이 명령을 호출하나?
          │
          ├── 예 ──> PATH 실행파일
          │
          └── 아니오(인터랙티브 사람만) ──> 함수 OK
```

순서가 중요하다. **"부모 셸 상태 변경" 조건이 최우선**이다 — `cd` 래퍼처럼 부모
셸을 바꿔야 하는 명령은, AI가 쓰든 말든 실행파일로는 구현이 불가능하다.

## 4. 균형추 — "AI용 = 무조건 실행파일"이 아니다

비-인터랙티브 호출이 필요하다고 해서 항상 실행파일인 것은 아니다. **부모 셸
상태를 바꿔야 하는 명령(`cd`, 현재 셸 env/alias 변경 등)은 반드시 함수여야
한다.** 실행파일은 별도 자식 프로세스에서 돌고 종료되므로 부모의 cwd나 env를
바꿀 수 없다. 이 경우 "AI가 비-인터랙티브로 못 쓴다"는 비용을 감수하고 함수로
간다 — 셸 상태 변경이 명령의 본질이기 때문이다.

## 5. 배치 / 로딩

| 전달 방식 | 위치 | 로딩 |
|-----------|------|------|
| 함수 | `shell-common/functions/*.sh` | 로더가 자동 source (인터랙티브 전용, interactive 가드 적용) |
| 실행파일 | `<module>/bin/<cmd>` | `~/.local/bin/<cmd>` 심링크 (`setup.sh`) + `shell-common/config/symlinks.conf` 등록 |

실행파일 추가 절차:

1. `<module>/bin/<cmd>` 작성 (`#!/bin/sh`, 실행 권한, POSIX).
2. `shell-common/config/symlinks.conf`에 `TARGET|SOURCE|DESC` 한 줄 추가 —
   `${HOME}/.local/bin/<cmd>|${HOME}/dotfiles/<module>/bin/<cmd>|설명`.
3. `setup.sh` 실행 → `~/.local/bin` 심링크 생성 (PATH 위라 모든 자식에서 보임).

## 6. 레퍼런스 구현 (repo 안에 양쪽 다 존재)

| 명령 | 전달 방식 | 위치 | 왜 그 방식인가 |
|------|-----------|------|----------------|
| `obsidian` | **PATH 실행파일** | `obsidian/bin/obsidian` (#1023) | AI가 `bash -c "obsidian search ..."` 비-인터랙티브로 호출. 부모 셸 상태 변경 없음 → 실행파일 가능. |
| `obsidian-claude` | **함수** | `shell-common/functions/obsidian_claude.sh` | vault로 `cd` 후 claude 실행 → **부모 셸 cwd를 바꿔야** 함 → 반드시 함수. |

두 명령의 대비가 결정 트리를 그대로 보여준다: `obsidian`은 셸 상태를 안 바꾸고
AI가 써야 해서 실행파일, `obsidian-claude`는 `cd`가 본질이라 (AI 비-인터랙티브
사용을 포기하고) 함수다.

## 7. 참조

- [`command-design-pattern.md`](./command-design-pattern.md) — 함수로 결정된
  경우의 *내부 구조* (dispatcher / sub-function / Type 2A·2B)
- [`command-guidelines.md`](./command-guidelines.md) — help 인터페이스·출력 정책
- `shell-common/config/symlinks.conf` — 실행파일 심링크 SSOT
- `obsidian/bin/obsidian` — 실행파일 참조 구현 (#1023)
- `shell-common/functions/obsidian_claude.sh` — 함수 참조 구현 (셸 상태 변경)
- 학습 출처: #1023, PR #1024 (함수 → PATH 실행파일 전환)
- Issue #1025 — 본 문서 추출 근거
