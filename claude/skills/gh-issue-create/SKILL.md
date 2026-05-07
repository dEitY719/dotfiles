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
  target a different remote's repository instead of origin. Accepts
  `-h`/`--help`/`help` to print usage.
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

## Step 1: Detect Repo Context

Record `START_TS=$(date +%s)` immediately for elapsed-time tracking in Step 3.5.

Confirm we're in a git repo (`git rev-parse --show-toplevel`), pick the
target remote (arg #1 if given, else `origin`), and resolve it to
`TARGET_REPO=<owner>/<repo>`. If the remote does not exist, list
`git remote -v` and stop — never silently fall back to `origin`. Full
substeps in `references/repo-resolution.md`.

## Step 2: Classify the Conversation

Pick exactly one conventional-commit prefix as the dominant intent.

| Prefix | When |
|--------|------|
| `feat` | 신규 기능 / 개선 / 확장 |
| `fix` | 에러 / 실패 / 의도와 다른 동작 |
| `refactor` | 동작 보존하며 구조 정리 |
| `perf` | 느림 / 자원 사용 과다 |
| `docs` | 문서 자체 변경 |
| `test` | 테스트 갭 / 추가 / 변경 |
| `chore` | 빌드·CI·도구·deps·스타일 (`build`/`ci`/`style`/`revert` 흡수) |
| `misc` | 위 어디에도 안 들어감 (fallback) |

모호하면 묻지 말고 가장 보수적인 `misc` 로 떨어진다. 대형 `feat`
휴리스틱(영향 컴포넌트 ≥3 / NF 명시 / 결정 누적 — 둘 이상)은
`references/templates/feat.md` "대형 feat 가이드" 를 따른다.

## Step 3: Draft the Issue Body

Step 2 의 prefix 에 매핑되는 템플릿을 로드한다:
`references/templates/<prefix>.md`. 각 템플릿은 타이틀 형식과 본문
골격을 모두 포함한다.

타이틀은 conventional commit 형식 `<type>[(<scope>)]: <한 줄 요약>`.
`misc` 만 prefix 없이 한 줄 요약만 적는다. 기존 `[Feature]` /
`[Bug]` / `[Misc]` 대괄호 형식은 폐기.

본문은 사용자 대화 언어로(한국어 대화 → 한국어 이슈). **DO NOT
over-compress** — 파일 경로·명령 출력·결정·근거를 그대로 유지한다.
대화가 길었다면 200줄짜리 이슈도 정상.

## Step 3.5: Compute AI Metrics

Before writing the body to the temp file, compute the metrics block:

1. **Elapsed time**: `ELAPSED=$(( ($(date +%s) - START_TS) / 60 ))`
2. **Issue type**: the prefix from Step 2 (`feat`, `fix`, `refactor`, etc.)
3. **Human time**: look up `references/metrics-baseline.md` by issue type.
   For `feat`, infer size (small / medium / large) from the conversation scope.
4. **Token estimate**: sum character counts of the drafted title + body, divide
   by 4, round to nearest 500 (minimum 1 000). See `references/metrics-baseline.md`
   for the full estimation rules.

Store results as `TOKENS`, `HUMAN_H`, `ELAPSED` for use in Step 4.

## Step 4: Create the Issue

`mktemp` 으로 임시 파일에 본문을 쓰고 metrics 블록을 append 한 뒤 생성한다:

```bash
BODY=$(mktemp) && trap 'rm -f "$BODY"' EXIT
# ... write body to "$BODY" ...
printf '\n---\n<details>\n<summary>🤖 AI Metrics · 📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min</summary>\n\n<!-- ai-metrics -->\n📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min\n<!-- /ai-metrics -->\n\n</details>\n' \
  "$TOKENS" "$HUMAN_H" "$ELAPSED" "$TOKENS" "$HUMAN_H" "$ELAPSED" >> "$BODY"
gh issue create --repo "$TARGET_REPO" --title "<title>" --body-file "$BODY"
```

`--assignee` / `--label` / `--milestone` 은 사용자가 명시 요청하지
않은 한 추가하지 않는다. 확인 질문하지 말고 즉시 실행.

## Step 5: Report

이슈 번호와 URL 만 출력:

```
Issue #123 created: https://github.com/owner/repo/issues/123
```

## Constraints

- `--assignee @me` / 라벨은 사용자 요청이 있을 때만 추가.
- 항상 `--repo "$TARGET_REPO"` — 암묵적 repo 감지 의존 금지.
- 사용자 지정 remote 가 없으면 즉시 실패.
- discussion log 를 2~3줄로 압축하지 말 것.
- "should I create it?" 같은 확인 질문 금지.
