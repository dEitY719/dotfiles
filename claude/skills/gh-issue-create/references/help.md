# gh:issue-create — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | remote-name, or `-h`/`--help`/`help` | `origin` | Git remote whose repo will own the new issue (e.g. `upstream`) |

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--no-auto-labels` | off | Skip Step 2.5 — never auto-attach labels/milestones from `.gh-issue-defaults.yml`. User-supplied `--label` flags still apply. |
| `--no-auto-deps` | off | Skip Step 2.6 — never auto-detect 선행 이슈 phrases in the conversation, and never run Step 4.5's `addBlockedBy` linking. |
| `--auto-label-debug` | off | Print Stage-1 detection trace plus kept/dropped label sets to stderr before issue creation. |
| `--no-ask` | off | Do not stop at the Step 3.1 미결 게이트 to ask. Decide every open item autonomously — repo convention first, else the most conservative option, else drop it from the acceptance criteria and note it as a separate issue — and record each one as `(자율 판단)` + 근거 under `## 확정 사항 (Decisions)`. For unattended callers (`devx:autopilot` Step 0b); never blocks the chain. Does not disable the gate. |
| `--as-discussion <category>` | off | Route to [[gh-discussion-create]] instead of creating an Issue. `<category>` is one of `Ideas` / `Q&A` / `Announcements` / `Lessons` (case-insensitive). Skips Step 2.5 entirely; `--label` / `--assignee` are ignored with a 1-line warning. Invalid category exits 3 without calling any API. |

## Usage

- `/gh-issue-create` — create issue on `origin`'s repo (the most common case)
- `/gh-issue-create upstream` — create issue on the `upstream` remote's repo
- `/gh-issue-create --no-auto-labels` — skip the SSOT auto-label step
- `/gh-issue-create --no-auto-deps` — skip 선행-이슈 (blockedBy) auto-detection
- `/gh-issue-create --auto-label-debug` — verbose label-dispatch trace
- `/gh-issue-create --no-ask` — 미결을 사용자에게 묻지 않고 보수적으로 자율 결정 (무인 호출용)
- `/gh-issue-create --as-discussion Ideas` — route the same conversation to [[gh-discussion-create]] (RFC body, Ideas category)
- `/gh-issue-create upstream --as-discussion Q&A` — Q&A Discussion on the `upstream` remote's repo
- `/gh-issue-create -h` / `--help` / `help` — print this help

## What the skill does

1. Confirms a git repo context and resolves `owner/repo` from the target
   remote's URL. If the remote does not exist, lists `git remote -v` and
   stops — no silent fallback to `origin`.
2. Classifies the conversation by **conventional-commit prefix**, which
   determines the title format and the body template loaded from
   `references/templates/<prefix>.md`:

   | Prefix | When to pick |
   |--------|--------------|
   | `feat` | 신규 기능 / 개선 / 확장 |
   | `fix` | 에러 / 실패 / 의도와 다른 동작 (기존 `bug` 흡수) |
   | `refactor` | 동작 보존하며 구조 정리 |
   | `perf` | 느림 / 자원 사용 과다 |
   | `docs` | 문서 자체 변경 |
   | `test` | 테스트 갭 / 추가 / 변경 |
   | `chore` | 빌드·CI·도구·deps·스타일 (`build`/`ci`/`style`/`revert` 흡수) |
   | `misc` | 위 어디에도 안 들어감 (fallback) |

   대형 `feat` 이슈는 본문에 PRD-lite + TRD-lite 를 포함하거나
   외부 문서로 분리한다 (`references/samples/{prd,trd}-sample.md`).

3. Drafts a structured issue body matching the template in the language
   the user was speaking (Korean chat → Korean issue).
4. **미결 게이트 (Step 3.1)** — inspects the draft for unresolved items
   (non-empty `## Open Questions`, deferral wording, unjudgeable acceptance
   criteria) and, if any fire, lists them with a **권고안 + 근거** each and
   waits — `gh issue create` is not called before the user answers. Settled
   items are written back as `## 확정 사항 (Decisions)`. No open items → no
   output at all. `--no-ask` decides them autonomously instead;
   `--as-discussion` skips the gate. See `references/clarification.md`.
5. **Auto-labels (Step 2.5, opt-in)** — when `$TARGET_REPO` ships
   `.gh-issue-defaults.yml`, attaches default labels and (optionally) a
   milestone per that SSOT. Missing labels warn-and-skip; never auto-
   created. Disabled by `--no-auto-labels`. See
   `references/auto-labels.md`.
6. **Dependency auto-detect (Step 2.6 + 4.5)** — scans the conversation for
   explicit 선행-이슈 phrases (`#13 완료 후`, `depends on #13`, `blocked by
   #13`, `선행 이슈: #13`, `#13 이후`) and, right after the issue is created,
   links each one with GitHub's native `addBlockedBy` so the sidebar shows
   `Blocked by #13`. Plain mentions (`#13 참고`) never link; cross-repo
   `owner/repo#13` is warned and skipped in v1; a failed link is non-fatal
   and surfaces as one warning line. Disabled by `--no-auto-deps`. See
   `references/dependency-detect.md`.
7. Creates the issue via
   `GH_HOST="$TARGET_HOST" gh issue create --repo "$TARGET_REPO"` using a
   temp file written by `mktemp` (avoids shell escaping bugs). Host and repo
   are both pinned from the same remote URL so a dual-host `gh` login cannot
   file the issue on the wrong server (#1403).
8. Prints only `Issue #N created: <url>` — no preamble, no summary.

## Title format

Conventional commit: `<type>[(<scope>)]: <한 줄 요약>`. `misc` 만 예외로
prefix 없이 한 줄 요약만 적는다. 기존 `[Feature]` / `[Bug]` / `[Misc]`
대괄호 형식은 폐기.

## Detail preservation

Do NOT over-compress. The issue is reused later for PR descriptions and
blog posts, so preserve:
- concrete file paths and line references
- command outputs and error logs
- decisions and the reasoning behind them
- discussion log — never collapse to 2–3 bullets

A 200-line issue is fine if the conversation warranted it.

## What the skill will NOT do

- Add `--assignee` unless the user asked.
- Auto-create labels that don't exist on the target repo (warn + skip).
- Link a dependency from a plain mention (`#13 참고`), or from a
  cross-repo `owner/repo#13` reference (warn + skip in v1).
- Apply auto labels/milestones on repos without `.gh-issue-defaults.yml`.
- Fall back to `origin` when the user-specified remote is missing.
- Create an issue whose body still carries unresolved items — the Step
  3.1 gate converts them to decisions first (Discussion mode excepted).
- Silently delete an open item to get past that gate, or accept a
  `--no-ask` autonomous decision without a `(자율 판단)` mark and a reason.
- Ask "should I create it?" — running the skill is the confirmation.
- Rely on implicit repo detection — always passes `--repo "$TARGET_REPO"`.
- Truncate or summarize the conversation log.
- Auto-detect whether the chat is RFC-shaped and route to a Discussion
  on its own. `--as-discussion` requires an explicit user request
  (#619 Non-Goal: no AI auto-judgement).
- Apply labels or assignees on the Discussion path — those are an
  Issue-only concept. Mixing `--as-discussion` with `--label` /
  `--assignee` drops the latter with a 1-line warning.

## Error cases

- `--as-discussion Foo` (not one of `Ideas` / `Q&A` / `Announcements` /
  `Lessons`) → print the four allowed values and exit 3 without any
  API call.
- `--as-discussion <category>` when
  `shell-common/functions/gh_discussion.sh` is missing → print
  `Install gh-discussion-create skill first.` and exit 1.
- User answers the Step 3.1 gate only partially → the remaining items are
  asked again. Never filled in on the skill's own initiative.
- User answers "그냥 만들어" → the gate passes, but each open item is
  recorded as `(보류 — 사용자 지시)` under `## 확정 사항 (Decisions)`.
- `--no-ask` and neither repo convention nor a conservative default settles
  an item → that item is dropped from the acceptance criteria and flagged in
  the body as belonging to a separate issue. The chain never stops.
- `addBlockedBy` fails (permission, network, non-existent issue number,
  or a schema mismatch on the mutation's arguments) → the issue stays
  created; one `[WARN] Blocked by #N 링크 실패` line is appended to the
  report. Never aborts, never retries.
