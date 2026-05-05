# gh:issue-create — Help

## Arguments

| # | Name | Default | Description |
|---|------|---------|-------------|
| 1 | remote-name, or `-h`/`--help`/`help` | `origin` | Git remote whose repo will own the new issue (e.g. `upstream`) |

## Usage

- `/gh-issue-create` — create issue on `origin`'s repo (the most common case)
- `/gh-issue-create upstream` — create issue on the `upstream` remote's repo
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
4. Creates the issue via `gh issue create --repo "$TARGET_REPO"` using a
   temp file written by `mktemp` (avoids shell escaping bugs).
5. Prints only `Issue #N created: <url>` — no preamble, no summary.

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

- Add `--assignee`, `--label`, or `--milestone` unless the user asked.
- Fall back to `origin` when the user-specified remote is missing.
- Ask "should I create it?" — running the skill is the confirmation.
- Rely on implicit repo detection — always passes `--repo "$TARGET_REPO"`.
- Truncate or summarize the conversation log.
