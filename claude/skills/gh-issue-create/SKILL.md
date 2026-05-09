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
  trace. Accepts `-h`/`--help`/`help` to print usage.
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

Parse the positional remote argument and the optional flags before
resolving the repo:

- Remote name — first non-flag positional arg, default `origin`.
- `--no-auto-labels` — skip Step 2.5 entirely; user `--label` flags
  remain in effect. Default off.
- `--auto-label-debug` — verbose stderr trace of Stage-1 detection and
  the kept/dropped label sets. Default off.

Confirm we're in a git repo (`git rev-parse --show-toplevel`) and resolve
the remote to `TARGET_REPO=<owner>/<repo>`. If the remote does not
exist, list `git remote -v` and stop — never silently fall back to
`origin`. Full substeps in `references/repo-resolution.md`.

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

## Step 2.1: Clarification & Scope Guard

Step 2 분류 직후, 본문 작성 전에 `references/clarification.md` 의
트리거 신호(동사 없는 명사 나열 / 컴포넌트 ≥3 혼재 / feature 범위
미정의)를 확인한다. 매치되면 1~2줄 확인 또는 분리안을 사용자에게
보낸다 — 응답을 받기 전에는 `gh issue create` 호출 금지. 매치되지
않으면 no-op, 곧장 Step 2.5 로 진행.

사용자가 "한 이슈로" 라고 답하면 분리하지 않고 그대로 생성한다 —
이 가이드는 강제 분할이 아니라 안전망이다.

## Step 2.5: Auto-labels + Milestone (opt-in via SSOT)

If `--no-auto-labels` was passed in Step 1, skip this step entirely.

Otherwise check `$TARGET_REPO` for the Stage-1 signals listed in
`references/auto-labels.md` ("Stage 1 — Repo signal detection"). If no
signal fires, skip and continue.

When a signal fires:

1. Source `${SHELL_COMMON}/functions/parse_yaml_defaults.sh` and load
   `static_labels`, `prefix_labels` (using the prefix from Step 2), and
   `milestone_value` from `.gh-issue-defaults.yml`.
2. Compose the candidate label set as
   `static_labels ∪ prefix_labels ∪ user_labels`. User-supplied
   `--label` values are merged, never overridden.
3. Validate every candidate against
   `gh label list --repo "$TARGET_REPO" --json name --jq '.[].name'`.
   Missing labels emit `auto-labels: label '<x>' not found in
   $TARGET_REPO — skip` on stderr and are dropped. **Never** auto-create
   labels.
4. Resolve the milestone — `auto`, `none`, or an exact title — per
   `references/auto-labels.md` ("Dispatch order"). Unknown names
   warn-and-skip.
5. Stash the kept labels and resolved milestone for Step 4 to thread
   into `gh issue create`.

If `--auto-label-debug` is set, print Stage-1 evaluation, loaded YAML
values, and kept/dropped sets to stderr before Step 4 runs. The full
schema, dispatch order, and compatibility matrix live in
`references/auto-labels.md`.

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

`mktemp` 으로 임시 파일에 본문을 쓰고 metrics 블록을 append 한 뒤 생성한다.
`GH_DISABLE_AI_METRICS=1` 이면 footer append 를 skip — 본문만 그대로
생성된다 (issue #399).

```bash
BODY=$(mktemp) && trap 'rm -f "$BODY"' EXIT
# ... write body to "$BODY" ...
if [ "${GH_DISABLE_AI_METRICS:-0}" = "1" ]; then
    : # ai-metrics footer skipped via GH_DISABLE_AI_METRICS
else
    printf '\n---\n<details>\n<summary>🤖 AI Metrics · 📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min</summary>\n\n<!-- ai-metrics -->\n📊 ~%s tokens · 👤 ~%s h · 🤖 ~%s min\n<!-- /ai-metrics -->\n\n</details>\n' \
      "$TOKENS" "$HUMAN_H" "$ELAPSED" "$TOKENS" "$HUMAN_H" "$ELAPSED" >> "$BODY"
fi
gh issue create --repo "$TARGET_REPO" --title "<title>" --body-file "$BODY" \
    "${LABEL_ARGS[@]}" "${MILESTONE_ARGS[@]}"
```

`LABEL_ARGS` / `MILESTONE_ARGS` are the arrays Step 2.5 prepared (one
`--label <name>` per kept label; `--milestone <title>` if resolved).
Both are empty when Step 2.5 was skipped — the `gh issue create`
invocation degrades to its original form.

`--assignee` is still only added when the user asks. User-supplied
`--label` flags survive Step 2.5 (union with auto labels) unless
`--no-auto-labels` was set, in which case Step 2.5 is bypassed and the
user's labels pass straight through `LABEL_ARGS` from Step 1.
확인 질문하지 말고 즉시 실행.

## Step 5: Report

이슈 번호와 URL 만 출력:

```
Issue #123 created: https://github.com/owner/repo/issues/123
```

## Constraints

- `--assignee @me` 는 사용자 요청이 있을 때만 추가.
- 라벨/마일스톤 은 (a) 사용자 명시 또는 (b) Step 2.5 의 SSOT 기반
  자동 적용 일 때만 부착. 자동 적용 결과는 항상 `gh label list` 검증
  통과한 라벨만 유지 — 미존재 라벨 자동 생성 금지.
- 항상 `--repo "$TARGET_REPO"` — 암묵적 repo 감지 의존 금지.
- 사용자 지정 remote 가 없으면 즉시 실패.
- discussion log 를 2~3줄로 압축하지 말 것.
- "should I create it?" 같은 확인 질문 금지.
