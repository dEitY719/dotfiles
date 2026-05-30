---
name: gh:issue-create
description: >-
  Save the current conversation as a GitHub issue. Use when the user runs
  /gh:issue-create, /gh-issue-create, or asks "이 대화 이슈로 등록",
  "chat을 깃허브 이슈로 남겨", "기록용 이슈 만들어". Summarizes the chat into
  a body keyed by conventional-commit prefix (feat / fix / refactor / perf /
  docs / test / verify / chore / misc) and creates the issue via
  `gh issue create` on
  the target remote's repo without confirmation, printing only the issue
  number and URL. Preserves reasoning and concrete details — the issue is
  reused for PR drafts and blog posts. Optional remote positional arg; flags
  `--no-auto-labels`, `--auto-label-debug`, `--as-discussion <category>`
  (#619) and `-h`/`--help`/`help` are documented in references/help.md.
allowed-tools: Bash, Read, Grep
metadata:
  model_recommendation:
    tier: sonnet
    reason: "chat→issue summarization with classification + auto-labels + clarification guard"
    claude: prefer
    non_claude: advisory-only
---

# gh:issue-create — Conversation → GitHub Issue

Convert the current chat into a well-structured issue on the target repo
(본문은 대화 언어로), execute immediately, and print only the issue number + URL.

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No API calls.

## Options

All arguments, flags, and env vars are in `references/options.md`
(Option | Description | Default). Key: `[remote]` positional (default
`origin`), `--no-auto-labels`, `--auto-label-debug`, `--label`,
`--assignee @me`, `--as-discussion <category>`, `GH_DISABLE_AI_METRICS=1`.

## Step 1: Detect Repo Context

Record `START_TS=$(date +%s)` for Step 3.5. Parse the positional remote arg
+ flags. Confirm a git repo (`git rev-parse --show-toplevel`) and resolve
`TARGET_REPO=<owner>/<repo>` via the remote (substeps in
`references/repo-resolution.md`). Never silently fall back to `origin` when
the user-supplied remote is missing. When `--as-discussion <category>` is
present, follow `references/discussion-mode.md` to bind `DISCUSSION_MODE` /
`CATEGORY` and validate the category (exit 3 on mismatch).

## Step 2: Classify the Conversation

Read `references/prefix-table.md` and pick exactly one conventional-commit
prefix as the dominant intent (covers disambiguation, `misc` default,
large-`feat` heuristic, and title formatting). `verify` 는 코드 변경이
아닌 라이브 검증 추적용 — 산출물이 issue + 코멘트 누적이면 `verify`,
테스트 코드 파일이면 `test` (`templates/verify.md`).

## Step 2.1: Clarification & Scope Guard

Apply `references/clarification.md` trigger signals (동사 없는 명사 나열 /
컴포넌트 ≥3 혼재 / feature 범위 미정의). 매치되면 1~2줄 확인 또는 분리안을
보내고 응답 전 `gh issue create` 호출 금지. "한 이슈로" 답하면 그대로 생성.

## Step 2.5: Auto-labels + Milestone (opt-in via SSOT)

Skip entirely when `--no-auto-labels` **or** `DISCUSSION_MODE=1` is set
(#619 F-3). Otherwise read `references/auto-labels.md` and follow verbatim
(Stage-1 signal → SSOT load → label union → `gh label list` validation →
milestone resolution). Stash kept labels + milestone for Step 4.
`--auto-label-debug` emits the Stage-1 trace.

## Step 3: Draft the Issue Body

Use the `references/templates/<prefix>.md` skeleton; title format per
`references/prefix-table.md`. **Over-compress 금지** — 파일 경로·명령 출력·
결정·근거 유지 (200줄 이슈도 정상). `DISCUSSION_MODE=1` 일 때는 Acceptance
Criteria 대신 Open Questions 섹션 + [[gh-discussion-create]] 의
`references/rfc-template.md` 스켈레톤 사용 (압축 금지 동일).

## Step 3.5: Compute AI Metrics

Read `references/metrics-baseline.md` and bind `TOKENS`, `HUMAN_H`,
`ELAPSED` for Step 4 (inputs: `START_TS`, the prefix, drafted title+body;
for `feat` infer small/medium/large from scope).

## Step 4: Create the Issue (or Discussion)

Follow `references/discussion-dispatch.md`: read `references/create-cmd.md`
and paste the matching bash block verbatim — Issue path (default) or
Discussion path (`DISCUSSION_MODE=1`). 확인 질문 없이 즉시 실행.

## Step 5: Report

Output format (Issue / Discussion / failure) is in
`references/report-template.md`. Always end with an `[OK]`/`[FAIL]` verdict
line + a `Next:` hint.

## Constraints

See `references/constraints.md` (assignee/label rules, always
`--repo "$TARGET_REPO"`, fail-fast on missing remote, no over-compression,
`--as-discussion` explicit-intent only, no confirmation prompts).
