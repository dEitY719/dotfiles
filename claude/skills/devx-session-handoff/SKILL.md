---
name: devx:session-handoff
description: >-
  컨텍스트 임계 근접 시 세션 인수인계(handoff) 자동화 — 이번 세션의 검증된
  완료분 / 남은 작업 / 재개 정보를 구조화해 트래킹 이슈에 코멘트로 게시하고,
  auto-memory 를 갱신하고, 다음 세션 재개 문장 1줄을 출력한다. Use when the
  user runs /devx:session-handoff, /devx-session-handoff, or says "핸드오프",
  "세션 넘겨", "이어서 하게 정리해줘", "컨텍스트 다 찼어", "handoff this
  session", "wrap up for the next session" — or when the context window nears
  its limit mid-way through a multi-session task. 일회성 작업 완료 기록은
  gh:issue-create / gh:discussion-create 를 쓰고, 본 스킬은 작업 진행 중
  세션 연속성 전용. Accepts `[issue-number] [remote]`, `--memory-only`
  (이슈 게시 생략), `--new-issue` (신규 트래킹 이슈 강제), and
  `-h`/`--help`/`help` to print usage. (중단 후 같은 세션 재개는
  devx:restart, 토큰 리밋 후 크론 재개는 devx:resume-after-limit — 이들은
  재개자(resumer)이고 본 스킬은 그에 선행하는 handoff 작성자다.)
allowed-tools: Bash, Read, Write, Grep, TaskList
metadata:
  model_recommendation:
    tier: sonnet
    reason: "conversation synthesis + tracking-issue resolution judgment; writes are two low-risk artifacts (issue comment, memory file)"
    claude: prefer
    non_claude: advisory-only
---

# devx:session-handoff — Handoff Comment + Resume Sentence

## Help

If arg #1 is `-h`, `--help`, or `help`, read `references/help.md` and output
its content verbatim, then stop. No API calls.

**Stop-on-error policy** — HARD-stop: Step 2 when no tracking issue can be
resolved AND GitHub is unreachable without `--memory-only` (ask, don't
guess). Soft-fail: Step 4 comment post (fall back to memory-only + warn);
Step 5 memory write never blocks — warn and continue.

## Step 1: Parse Args

| Option | Description | Default |
|---|---|---|
| `[issue-number]` | 트래킹 이슈 번호 (양의 정수) | auto-resolve (Step 2) |
| `[remote]` | git remote 이름 | `origin` |
| `--memory-only` | 이슈 코멘트 생략, 메모리에만 기록 | off |
| `--new-issue` | 기존 후보 무시, 신규 트래킹 이슈 강제 생성 | off |
| `-h`/`--help`/`help` | usage 출력 후 정지 | — |

Resolve `TARGET_REPO=<owner>/<repo>` from the remote URL (same procedure as
gh:issue-read); unknown remote → list `git remote -v` and stop.

## Step 2: Resolve the Tracking Issue

Follow `references/issue-resolution.md`: explicit arg → conversation
`#N` mentions → branch `wt/issue-N-*` → recent `gh` activity. Multiple
candidates → pick the most-referenced or ask. No candidate → judge:
substantive multi-session work gets a new tracking issue via
Skill(gh:issue-create); trivial work degrades to `--memory-only`. The
duplicate-handoff guard (prior handoff comment from this session → update
it, don't append) also lives there.

## Step 3: Compose the Handoff Artifact

Build the comment body per `references/handoff-template.md`. Honesty rules
are non-negotiable: only merged PRs and tests that ran green in this session
go under "완료 (검증됨)"; everything else is "미검증" or "남은 작업". Pull
remaining work from the session TodoList (TaskList) when one exists.

## Step 4: Post the Comment

`gh issue comment <N> --repo "$TARGET_REPO" --body-file <artifact>` — skip
entirely when `--memory-only`. On API failure: one `[WARN]` line, continue —
the Step 5 memory copy still preserves the handoff.

## Step 5: Update Auto-memory (always)

Write or update one `project`-type memory file recording issue number,
branch, worktree, next step, and the resume sentence; refresh the memory
index line. Format in `references/handoff-template.md` → "Memory record".
Runs even when Step 4 posted successfully (issue = team-visible, memory =
agent-local).

## Step 6: Resume Sentence + Report

Print the copy-paste resume sentence (`#<N> <next-step> 진행` — must map to
the real tracking issue and its actual next step; never fabricate), then the
`[OK]`/`[FAIL]` structured report per `references/report-template.md`,
ending with the `Next:` hint.

## Constraints

- Writes are exactly two artifacts: one issue comment, one memory file.
  Never commit, push, edit code, or close/relabel issues.
- Never overstate completion — unverified work is never listed as done.
- Never invent a resume sentence that doesn't map to the tracking issue.
- Reuses gh:issue-create (new tracking issue) and gh:issue-read
  (candidate validation). Sister skills devx:restart and
  devx:resume-after-limit are the resumers this handoff feeds — the resume
  sentence must stay parseable by the human driving them.
