# superpowers

> 자동 생성 문서입니다. 직접 편집하지 마세요 — 내용은 `shell-common/functions/superpowers_help.sh` 의 row 함수가 SSOT 입니다.
> 재생성: `shell-common/tools/custom/gen_command_docs.sh --topic superpowers --force`

## 호출

- Help 진입점: `superpowers-help [section|--list|--all]`
- 통합 라우팅: `my-help superpowers [section]`
- Alias: `superpowers-help`

## 요약 (superpowers-help)

- Usage: superpowers-help [section|--list|--all]
- sections
    - process: brainstorming | plans | TDD | debugging | verify
    - execution: parallel agents | subagents | worktrees
    - review: request | receive | finishing branch
    - meta: using-superpowers | writing-skills
    - flow: feature & bug-fix lifecycles
    - location: skill files path
    - usage: invocation tips
    - details: superpowers-help <section>

## 섹션

### process

- **brainstorming** — Creative work, feature design, requirements exploration before implementation
- **writing-plans** — Multi-step task planning from spec/requirements, before touching code
- **executing-plans** — Execute written implementation plans in separate sessions with review checkpoints
- **systematic-debugging** — Bug/test failure diagnosis - root cause analysis before proposing fixes
- **test-driven-development** — Red-green-refactor: write tests before implementation code
- **verification-before-completion** — Run verification commands and confirm output before claiming done

### execution

- **dispatching-parallel-agents** — Run 2+ independent tasks concurrently without shared state
- **subagent-driven-development** — Execute implementation plans with independent sub-agents
- **using-git-worktrees** — Isolated feature work via git worktrees with safety checks

### review

- **requesting-code-review** — Request review after feature completion or before merge
- **receiving-code-review** — Handle review feedback with technical rigor, not blind agreement
- **finishing-a-development-branch** — Branch integration: merge, PR, or cleanup options

### meta

- **using-superpowers** — Skill discovery and invocation at conversation start
- **writing-skills** — Create, edit, or verify skills before deployment

### flow

- Feature Development (full lifecycle):
1. brainstorming          - explore requirements, design spec
2. writing-plans          - break spec into bite-sized tasks
3. executing-plans        - execute tasks (TDD per step)
4.   or subagent-driven-development (parallel, same session)
5. requesting-code-review - dispatch reviewer subagent
6. receiving-code-review  - evaluate & apply feedback
7. finishing-a-dev-branch - merge, PR, or cleanup
- verification-before-completion runs at every completion claim.
- test-driven-development runs inside each execution step.
- Bug Fix (shorter cycle):
1. systematic-debugging   - root cause analysis first
2. test-driven-development - write failing test for the bug
3. verification-before-completion
4. finishing-a-dev-branch - merge the fix
- Parallel tasks: use dispatching-parallel-agents or using-git-worktrees

### location

- Superpowers plugin not found. Install via Claude Code marketplace.
- Expected: ~/.claude/plugins/cache/superpowers-dev/superpowers/<version>/skills/

### usage

- Invoke in Claude Code: /brainstorm, /write-plan, /execute-plan
- Read a skill: cat <skills_path>/<skill-name>/SKILL.md
- Priority: Process skills first, then implementation skills

## 엣지케이스 / 의도된 동작

아직 정리된 항목이 없습니다. 소스 주석에만 있는 동작을 발견하면
`docs/guide/commands/.notes/superpowers.md` 에 추가한 뒤 이 문서를 재생성하세요.

## 소스

- `shell-common/functions/superpowers_help.sh`
- 인터페이스 규칙: `docs/.ssot/command-guidelines.md`
