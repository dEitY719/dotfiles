---
name: gh:issue-create
description: >-
  Save the current conversation as a GitHub issue in the current repository.
  Use when the user runs /gh:issue-create, /gh-issue-create, or asks to "이 대화 이슈로 등록",
  "chat을 깃허브 이슈로 남겨", "기록용 이슈 만들어". Summarizes the conversation so
  far into a structured issue body keyed by conventional-commit prefix
  (feat / fix / refactor / perf / docs / test / chore / misc),
  creates it via `gh issue create` on the target remote's repo without asking
  for confirmation, and prints only the issue number and URL. Do NOT over-
  compress — the issue is reused for PR drafts and blog posts, so preserve
  reasoning, decisions, and concrete details.
  Accepts an optional remote name argument (e.g., `/gh-issue-create upstream`) to
  target a different remote's repository instead of origin. When the
  target repo ships a `.gh-issue-defaults.yml`, default labels and a
  milestone are auto-applied per that file (Step 2.5); pass
  `--no-auto-labels` to opt out or `--auto-label-debug` for the dispatch
  trace. Pass `--as-discussion <category>` (`Ideas` / `Q&A` /
  `Announcements` / `Lessons`) to route the same conversation to
  [[gh-discussion-create]] without re-running a different skill (#619).
  Accepts `-h`/`--help`/`help` to print usage.
allowed-tools: Bash, Read, Grep
---

# gh:issue-create — Conversation → GitHub Issue

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and
output its content verbatim, then stop. No API calls.

## Role

Convert the current chat into a well-structured GitHub issue on the target
repo. Execute immediately without confirmation. Print only the issue
number + URL at the end.

## Options

| Argument | Description | Default |
|----------|-------------|---------|
| `[remote]` (positional) | Target remote name. Resolved to `TARGET_REPO=<owner>/<repo>`. Fails fast if missing. | `origin` |
| `--no-auto-labels` | Skip Step 2.5 entirely; user `--label` flags remain in effect. | off |
| `--auto-label-debug` | Verbose stderr trace of Stage-1 detection and the kept/dropped label sets. | off |
| `--label <name>` | User label, union with Step 2.5 auto-labels. Repeatable. | — |
| `--assignee @me` | Only added when the user explicitly asks. | off |
| `--as-discussion <category>` | Route to [[gh-discussion-create]] instead of creating an Issue. Category is one of `Ideas` / `Q&A` / `Announcements` / `Lessons` (case-insensitive). Skips Step 2.5 (auto-labels) and Step 4's `gh issue create` — Discussions do not carry labels/milestones. `--label` / `--assignee` flags, if also passed, are ignored with a 1-line warning. | off |
| `GH_DISABLE_AI_METRICS=1` (env) | Skip ai-metrics footer append in Step 4. | off |
| `-h`/`--help`/`help` | Print `references/help.md` verbatim and stop. | — |

## Step 1: Detect Repo Context

Record `START_TS=$(date +%s)` immediately for Step 3.5. Parse the
positional remote arg and the flags above. Confirm we're in a git repo
(`git rev-parse --show-toplevel`) and resolve `TARGET_REPO=<owner>/<repo>`
via the remote — full substeps in `references/repo-resolution.md`.
Never silently fall back to `origin` when the user-supplied remote is
missing.

### Step 1.1: `--as-discussion` parse

If `--as-discussion <category>` is present, bind `DISCUSSION_MODE=1` and
`CATEGORY=<value>`. Validate `<value>` against the allow-list
`Ideas` / `Q&A` / `Announcements` / `Lessons` (case-insensitive); on
mismatch, print the four allowed values and **exit 3** without calling
any API. When `DISCUSSION_MODE=1` and the user also supplied `--label`
or `--assignee`, emit a 1-line warning to stderr and drop those flags
(Discussions do not carry labels/assignees):

```
[gh-issue-create] --as-discussion: dropping --label/--assignee (Discussions do not carry these)
```

When `DISCUSSION_MODE` is unset the legacy issue path is unchanged.

## Step 2: Classify the Conversation

Read `references/prefix-table.md` and pick exactly one conventional-commit
prefix as the dominant intent. The reference also covers the disambiguation
rules (default to `misc`; large-`feat` heuristic) and title formatting.

## Step 2.1: Clarification & Scope Guard

Apply `references/clarification.md` trigger signals (동사 없는 명사 나열 /
컴포넌트 ≥3 혼재 / feature 범위 미정의). 매치되면 1~2줄 확인 또는 분리안을
사용자에게 보내고 응답 전에는 `gh issue create` 호출 금지. 사용자가
"한 이슈로" 라고 답하면 그대로 생성 — 강제 분할 아닌 안전망.

## Step 2.5: Auto-labels + Milestone (opt-in via SSOT)

Skip entirely when `--no-auto-labels` **or** `DISCUSSION_MODE=1` is set.
Discussions do not carry labels or milestones (#619 F-3) — running the
auto-label dispatch and then discarding the result would be wasteful
and noisy. Otherwise read `references/auto-labels.md` and follow
verbatim (Stage-1 signal → SSOT load → label union → `gh label list`
validation → milestone resolution). Stash kept labels + milestone for
Step 4. `--auto-label-debug` emits the Stage-1 trace per the same
reference.

## Step 3: Draft the Issue Body

`references/templates/<prefix>.md` 에 정의된 본문 골격을 그대로 사용한다.
타이틀 포맷은 Step 2 의 `references/prefix-table.md` 참조. 본문은 사용자 대화 언어로
작성하고 (한국어 대화 → 한국어 이슈) **over-compress 금지** — 파일
경로·명령 출력·결정·근거를 그대로 유지한다. 200 줄짜리 이슈도 정상.

When `DISCUSSION_MODE=1`, swap the Acceptance Criteria section for an
**Open Questions** section and use the matching skeleton from
[[gh-discussion-create]]'s `references/rfc-template.md`
(Ideas/Q&A/Announcements/Lessons variants). All other detail-preservation
rules remain identical — Discussions are not a license to compress.

## Step 3.5: Compute AI Metrics

Read `references/metrics-baseline.md` and bind `TOKENS`, `HUMAN_H`,
`ELAPSED` for Step 4. Inputs: `START_TS` from Step 1, the prefix from
Step 2, the drafted title + body. For `feat`, infer size (small /
medium / large) from the conversation scope.

## Step 4: Create the Issue (or Discussion)

Read `references/create-cmd.md` and paste the matching bash block
verbatim:

- **Issue path** (default, `DISCUSSION_MODE` unset) — `mktemp` body
  file, `GH_DISABLE_AI_METRICS=1` short-circuit (issue #399),
  ai-metrics footer printf, and `gh issue create` with `LABEL_ARGS` /
  `MILESTONE_ARGS` from Step 2.5.
- **Discussion path** (`DISCUSSION_MODE=1`) — same body file +
  ai-metrics footer, then source
  `shell-common/functions/gh_discussion.sh` and run the three lookups
  (`_gh_discussion_repo_id`, `_gh_discussion_category_id`,
  `_gh_discussion_create`). Print the Discussion URL instead of an
  issue URL. If the helper is missing, fail with
  `[FAIL] gh-discussion helper not found at $DOTFILES_ROOT/shell-common/functions/gh_discussion.sh`
  and exit 1.

확인 질문하지 말고 즉시 실행.

## Step 5: Report

Issue 경로 성공 시:

```
[OK] Issue: #123, URL: https://github.com/owner/repo/issues/123
Next: /gh:issue-implement 123
```

Discussion 경로 (`DISCUSSION_MODE=1`) 성공 시 — Discussion URL 만 출력:

```
[OK] Discussion (<category>): https://github.com/owner/repo/discussions/45
Next: /gh-discussion-convert 45   # when decision lands
```

실패 시 (gh stderr 또는 helper stderr 첫 줄을 인용):

```
[FAIL] <stderr first line>
Next: <recovery step — e.g. `gh auth login`, fix `.gh-issue-defaults.yml`, enable Discussions in repo settings>
```

## Constraints

- `--assignee @me` 는 사용자 요청이 있을 때만 추가.
- 라벨/마일스톤 은 (a) 사용자 명시 또는 (b) Step 2.5 의 SSOT 기반
  자동 적용 일 때만 부착. 자동 적용 결과는 항상 `gh label list` 검증
  통과한 라벨만 유지 — 미존재 라벨 자동 생성 금지.
- 항상 `--repo "$TARGET_REPO"` — 암묵적 repo 감지 의존 금지.
- 사용자 지정 remote 가 없으면 즉시 실패.
- discussion log 를 2~3줄로 압축하지 말 것. `DISCUSSION_MODE=1`
  경로에서도 동일하게 적용된다 — Discussion 본문은 future-self 검색의
  SSOT 다.
- `--as-discussion` 는 명시적 사용자 의도 전용. AI 가 "이건 Discussion
  같음" 자동 판정해서 분기하지 말 것 (#619 Non-Goal). 잘못된 분기 =
  SSOT 분산.
- `--as-discussion` + `--label` / `--assignee` 동시 사용 시 후자를
  버리고 경고 1줄. `DISCUSSION_MODE=1` 일 때 Step 2.5 와 `gh issue
  create` 둘 다 우회.
- "should I create it?" 같은 확인 질문 금지.
