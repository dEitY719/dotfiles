---
status: approved
---

# dotfiles 제품 요구사항 (Entry SSOT)

> **버전**: v1 (2026-05-16) — Initial draft, issue #660 docs/ 재정렬과 함께 entry 파일 신설
> **대상 시스템**: dotfiles — 멀티-쉘·멀티-머신 개발 환경 표준화 + AI 코딩 에이전트 통합
> **포맷**: D-XX 확정 의사결정 · F-XX 기능 · NF-XX 비기능 · O-XX 미해소 결정
> **벤치마크**: `para/project/agent-toolbox/docs/requirement/product-requirements.md` (v7 구조 참고)

## 1. 프로젝트 개요

dotfiles 는 bash/zsh 두 쉘과 다중 머신(WSL2 home / external work-pc)에서 **동일한 개발 경험을 재현 가능하게 만드는 모듈식 dotfiles 시스템**이다. 단순 설정 파일 묶음을 넘어, AI 코딩 에이전트(Claude Code · Codex · Gemini) 와 GitHub 워크플로(issue → implement → commit → PR → review reply → merge) 를 1급 시민으로 통합한다.

핵심 가치 명제:

- **One-command bootstrap** — 신규 머신에서 `./setup.sh && ./install.sh` 만으로 동일 환경 구축
- **POSIX-first shared layer** — `shell-common/` 는 bash/zsh 모두에서 안전하게 동작 (sourcing guard · interactive guard · `[ ]` 호환 문법)
- **AI agent SSOT** — `claude/skills/` 한 곳에 스킬 정의, 모든 사용자(SSOT) · 멀티 계정 (`~/.claude*/skills` symlink) 으로 배포
- **GitHub-as-IDE** — issue → PR 까지 5-step composition (`/gh:issue-flow`) 으로 자동화

## 2. 확정된 의사결정 (D-01 ~)

| #    | 주제 | 결정 | 영향 |
|------|------|------|------|
| D-01 | **Shared shell layer 호환성** | `shell-common/` 는 **POSIX sh** 호환 — `>/dev/null 2>&1`, `[ ]`, `#!/bin/sh` 사용. `[[ ]]`/`&>` 금지. | `shell-common/AGENTS.md` Critical Rules 강제. CI 의 shellcheck/shfmt 게이트. |
| D-02 | **UX 라이브러리 사용 강제** | 모든 사용자 표시 출력은 `shell-common/tools/ux_lib/ux_lib.sh` 의 `ux_header`/`ux_success`/`ux_error`/`ux_info` 경유. raw `echo`/`printf`/`tput` 금지. | `shell-common/tools/ux_lib/UX_GUIDELINES.md` SSOT. devx:ux-guidelines 스킬로 audit. |
| D-03 | **No-emoji 원칙** | 모든 출력·문서·커밋 메시지에 emoji 금지 (token 효율). **단일 예외**: `ai-metrics` footer 의 `📊 👤 🤖` 글리프 (#317 F-2 + PR #320 SSOT). | CLAUDE.md root 룰. Pre-commit hook `emoji_check.sh` (해당 시) 또는 grep 게이트. |
| D-04 | **Git 2-tier hook system** | `git/` 하위 표준 hooks + 사용자 확장 layer. Config SSOT 는 `git/config/hook-config.sh`. 디버그 `GIT_HOOKS_DEBUG=1`. | hook 추가 시 `git/config/hook-config.sh` 만 갱신, fall-through 보장. |
| D-05 | **AI 스킬 SSOT 위치** | `~/dotfiles/claude/skills/` 가 정본. `~/.claude/skills` · `~/.claude-personal/skills` 는 symlink (downstream). 동료팀 공유 레포 = `dEitY719/claude-skills`. | 스킬 편집은 dotfiles 레포에서만. memory: `reference_claude_skills_ssot`. |
| D-06 | **멀티 머신 환경 분기** | 머신별 차이는 `bash/development.local.sh` + `PYTEST_ADDOPTS` 환경변수 오버라이드로 흡수. 호스트명·OS 분기를 코드에 직접 박지 않는다. | memory: `project_multi_machine_dev_env`. |
| D-07 | **GitHub PR 자동화 5-step composition** | issue 처리 표준 흐름 = `/gh:issue-flow <N>` = implement → commit → PR → schedule pr-reply → resolve conflict. 직접 main 커밋 금지 — 항상 feature 브랜치 + worktree. | memory: `feedback_feature_branch_before_work`, `feedback_session_continuity`. |
| D-08 | **Interactive guard 표준 형태** | 출력 산출 파일은 `case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac` 사용. 단순 형태 (`[[ $- != *i* ]] && return`) 는 bats/CI 회귀 유발 (PR #497 2건). | memory: `feedback_interactive_guard_force_init`. |
| D-09 | **commit 메시지 strict policy** | Conventional commits + `Closes/Fixes` 만 (Refs/Resolves/See 금지). body line ≤ 72 자. | memory: `reference_commit_msg_hook_policy`. commit-msg hook 강제. |
| D-10 | **워크트리 기반 격리 작업** | 한 conversation = 한 워크트리. `ai-worktree:spawn` / `ai-worktree:teardown` 스킬로 라이프사이클 관리. | 멀티 AI 에이전트 동시 작업 환경. |

## 3. 기능 요구사항 (F-XX)

표 범례 — **중요도/난이도**: 상 / 중 / 하. **P-tier**: P0 (Core) · P1 (Phase 2) · P2 (Phase 3) · P3 (Backlog).

### 3.A Shell 환경 (bash + zsh + shared)

| ID | 기능 | 상세 | 중요도 | P-tier | 상세 링크 |
|----|------|------|--------|--------|----------|
| F1 | 멀티-쉘 entry loader | `bash/main.bash`, `zsh/main.zsh` 가 `shell-common/` 의 POSIX 모듈을 안전 sourcing | 상 | P0 | `bash/AGENTS.md`, `zsh/AGENTS.md` |
| F2 | 통합 UX 라이브러리 | `ux_header`/`ux_success`/`ux_error`/`ux_info` 등 의미적 출력 함수 | 상 | P0 | `shell-common/tools/ux_lib/UX_GUIDELINES.md` |
| F3 | Tool integrations | `shell-common/tools/integrations/` — 외부 도구 (gh, fzf, ollama, gcp 등) 1-파일 통합 | 상 | P0 | `shell-common/AGENTS.md` "3-Step Pattern" |
| F4 | Help 함수 표준 | `*_help.sh` 패턴 + ux 함수 일관 사용 | 중 | P0 | memory: `feedback_help_ux_rules` |
| F5 | `tools/custom/` 명시 호출 | auto-source 금지 영역, 사용자가 명시적으로 invoke | 중 | P0 | `shell-common/AGENTS.md` |

### 3.B Git workflow

| ID | 기능 | 상세 | 중요도 | P-tier |
|----|------|------|--------|--------|
| F6 | 2-tier hook system | 표준 hooks (`git/hooks/`) + checks (`git/hooks/checks/`) | 상 | P0 |
| F7 | pre-commit 게이트 | shellcheck, shfmt, ruff, mypy, pipe-loop check, zsh emulation check, emoji check | 상 | P0 |
| F8 | commit-msg strict policy | Conventional + Closes/Fixes only + 72-char body | 상 | P0 |
| F9 | Worktree 자동화 | `gwt create/teardown` + `--wt-name` 명령 | 상 | P0 |
| F10 | Branch cleanup | `gbr teardown` — `[gone]` 감지 후 merge 된 브랜치 prune | 중 | P0 |

### 3.C AI 코딩 에이전트 통합

| ID | 기능 | 상세 | 중요도 | P-tier |
|----|------|------|--------|--------|
| F11 | Claude skill SSOT 배포 | `claude/skills/` symlink 모드로 모든 계정 인스턴스에 동기화 | 상 | P0 |
| F12 | Multi-account 지원 | `~/.claude*/skills` directory-level symlink | 상 | P0 |
| F13 | gh:issue-flow composition | issue → implement → commit → PR → schedule → resolve | 상 | P0 |
| F14 | gh:pr-reply 자동 응답 | 리뷰 코멘트 분류 후 accept/decline 답변 | 상 | P0 |
| F15 | AI metrics footer 자동 부착 | issue/PR 본문에 tokens · human-h · ai-min 기록 (#317 / #320) | 중 | P0 |
| F16 | Codex/Gemini 위임 경로 | `codex:rescue`, `gh:pr-review --ai <codex\|gemini\|claude>` | 중 | P1 |

### 3.D 문서·온보딩

| ID | 기능 | 상세 | 중요도 | P-tier |
|----|------|------|--------|--------|
| F17 | 5-디렉토리 docs 구조 | `.ssot` / `requirement` / `guide` / `feature` / `archive` | 상 | P0 (#660) |
| F18 | guide/ 통합 가이드 | setup·team-git·learnings·playbooks·technic·superpowers-ko | 상 | P0 |
| F19 | Setup HTML 출력 | `dotfiles-setup-guide.html` — setup.sh 의 사람 친화 변환본 | 중 | P0 |

## 4. 비기능 요구사항 (NF-XX)

| ID | 항목 | 기준 |
|----|------|------|
| NF1 | 멀티-쉘 호환 | bash 4.x+ 및 zsh 5.x+ 양쪽에서 모든 `shell-common/` 모듈 동작 |
| NF2 | 멀티-머신 환경 | WSL2 (home) · 외부 work-pc 양쪽에서 `setup.sh` 멱등 (memory: `project_multi_machine_dev_env`) |
| NF3 | POSIX sh 호환 | `shell-common/` 는 dash-safe (POSIX) — bashism/zshism 금지 |
| NF4 | shellcheck/shfmt zero-warning | `mise run lint-sh` 통과 (shellcheck + shfmt diff) |
| NF5 | bats + pytest + golden rules 통과 | `./tests/test` 전 단계 PASS |
| NF6 | No-emoji 정책 | ai-metrics footer 외 모든 영역 emoji 검출 시 PR 차단 |
| NF7 | symlink-based deploy | 직접 `~/.bashrc` 쓰기 금지 — 항상 `setup.sh` 경유 symlink |
| NF8 | Interactive guard 표준 | 모든 출력 산출 파일은 `case $- in *i*) ;; *) [ -n "${DOTFILES_FORCE_INIT-}" ] || return 0 ;; esac` 사용 |

## 5. Open Questions (O-XX)

- **O-01: requirement/ 의 trd/ / use-cases/ 확장** — agent-toolbox 의 4 단 구조(`product-requirements.md` + `trd/` + `use-cases/` + `development-process.md`) 중 dotfiles 가 어디까지 받아들일지. 현 시점 1-파일 entry 만 도입, 후속 이슈에서 확장 판단.
- **O-02: AGENTS.md vs CLAUDE.md 통합** — root `CLAUDE.md` 와 `docs/AGENTS.md` 의 정책 영역이 일부 중복. SSOT 일원화 검토 필요.
- **O-03: superpowers-ko 의 외부 공유 채널** — `claude-skills` 레포로 별도 export 할지, dotfiles 내부에서만 유지할지.
- **O-04: ai-metrics 자동 부착 범위** — 현재 issue/PR/일부 commit 자동, skill comment 까지 확장 여부.

## 6. 상세 문서 링크

- 정책 SSOT: [`docs/.ssot/`](../.ssot/README.md) — 명령 UX · env vars · 보드 운영 · 커밋 표준 · Discussions 정책
- 피처별 설계: [`docs/feature/`](../feature/) — 10+ 피처 번들 + superpowers-plans/specs
- 사람-팀원 가이드: [`docs/guide/`](../guide/README.md) — setup · team-git · learnings · playbooks · technic · superpowers-ko
- 보관 자료: [`docs/archive/`](../archive/README.md) — postmortem · review-2026 · company · diagram · 도래일 지난 todo
- 루트 컨텍스트: [`AGENTS.md`](../../AGENTS.md), [`CLAUDE.md`](../../CLAUDE.md)
