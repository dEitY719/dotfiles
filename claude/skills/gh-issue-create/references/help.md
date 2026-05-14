# gh:issue-create — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | remote-name, or `-h`/`--help`/`help` | `origin` | Git remote whose repo will own the new issue (e.g. `upstream`) |

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--no-auto-labels` | off | Skip Step 2.5 — never auto-attach labels/milestones from `.gh-issue-defaults.yml`. User-supplied `--label` flags still apply. |
| `--auto-label-debug` | off | Print Stage-1 detection trace plus kept/dropped label sets to stderr before issue creation. |
| `--as-discussion <category>` | off | Route to [[gh-discussion-create]] instead of creating an Issue. `<category>` is one of `Ideas` / `Q&A` / `Announcements` / `Lessons` (case-insensitive). Skips Step 2.5 entirely; `--label` / `--assignee` are ignored with a 1-line warning. Invalid category exits 3 without calling any API. |

## Usage

- `/gh-issue-create` — create issue on `origin`'s repo (the most common case)
- `/gh-issue-create upstream` — create issue on the `upstream` remote's repo
- `/gh-issue-create --no-auto-labels` — skip the SSOT auto-label step
- `/gh-issue-create --auto-label-debug` — verbose label-dispatch trace
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
4. **Auto-labels (Step 2.5, opt-in)** — when `$TARGET_REPO` ships
   `.gh-issue-defaults.yml`, attaches default labels and (optionally) a
   milestone per that SSOT. Missing labels warn-and-skip; never auto-
   created. Disabled by `--no-auto-labels`. See
   `references/auto-labels.md`.
5. Creates the issue via `gh issue create --repo "$TARGET_REPO"` using a
   temp file written by `mktemp` (avoids shell escaping bugs).
6. Prints only `Issue #N created: <url>` — no preamble, no summary.

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
- Apply auto labels/milestones on repos without `.gh-issue-defaults.yml`.
- Fall back to `origin` when the user-specified remote is missing.
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
