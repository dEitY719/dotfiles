# devx:pr-to-ssot-issue — Help

## Usage

```
/devx:pr-to-ssot-issue <PR#> --reason "<exception 사유>" [flags]
/devx-pr-to-ssot-issue 727 --reason "신규 동료 SSO 전문가 — 일정 촉박, PR 품질 양호"
/devx:pr-to-ssot-issue 727 --reason "..." --parent 685 --dry-run
/devx:pr-to-ssot-issue -h          # show this help
/devx:pr-to-ssot-issue --help      # show this help
/devx:pr-to-ssot-issue help        # show this help
```

## Arguments

| # | Name | Required | Description |
|---|------|----------|-------------|
| 1 | `<PR#>` | yes | SSOT 로 역공학할 PR 번호 (positive integer). |

## Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--reason "<text>"` | **required** | Exception 사유. **≥ 10 chars 강제** — 비거나 짧으면 exit 2. 이슈 본문 audit block 에 verbatim 기록. |
| `--parent <issue#>` | parsed from `Closes #N` in PR body | 부모 이슈 번호. 미지정 + 본문에도 없으면 비워둠 (warn). |
| `--remote <name>` | `origin` | 대상 remote. 존재하지 않으면 `git remote -v` 목록만 출력 후 stop. |
| `--milestone "<name>"` | parent 또는 PR milestone 상속 | Milestone 이름. `--apply` 시 사전 검증. |
| `--label <name>` | `documentation`, `priority:medium` | Repeatable. `--apply` 시 사전 검증 — missing 시 stop. 자동 생성 안 함. 라벨 이름은 대상 repo 에 실제 존재하는 것으로 교체해서 호출한다 (priority 라벨 명칭은 repo 마다 다름). |
| `--force-overlap` | off | PR 이 이미 PRD/TRD 인용 issue 와 linked 돼 있어도 진행. Default 는 overlap 감지 시 exit 3. |
| `--dry-run` | off | `.claude/.pr-to-ssot.<PR#>.draft.md` 만 작성. `gh issue create` 생략. |
| `--no-next-hint` | off | 최종 보고에서 `Next: /gh-issue-flow <N>` 라인을 생략. composer (gh:issue-flow 등) 에서 호출할 때 사용. |

## Examples

```
# 1. Standard exception PR reverse-engineering (creates the SSOT issue):
/devx-pr-to-ssot-issue 727 \
    --reason "신규 SSO 전문가 합류, 일정 촉박. 코드 품질 양호 → 거절 비용 > 복귀 비용"

# 2. Dry-run preview (writes draft, no GitHub mutation):
/devx-pr-to-ssot-issue 727 \
    --reason "동일" \
    --dry-run

# 3. Explicit parent + custom labels:
/devx-pr-to-ssot-issue 727 \
    --reason "..." \
    --parent 685 \
    --label documentation \
    --label priority-medium \
    --label exception-recovery

# 4. Override overlap guard (PR already has SSOT linkage):
/devx-pr-to-ssot-issue 727 \
    --reason "기존 issue #500 은 outdated — 신규 SSOT 작성 필요" \
    --force-overlap
```

## What the skill does

1. Fetches the PR + its diff and classifies every changed file into one of
   four buckets: **code / schema / infra / docs**. Each bucket gets a
   one-line gap hypothesis pointing at which SSOT section is most at risk.
2. Delegates **gap analysis** to a subagent (`Explore` or
   `general-purpose`) which reads the repo's PRD/TRD docs and returns a
   structured report across five sections: Glossary / API 계약 / Data
   Models / Deployment / Cross-refs.
3. Renders an 8-section issue body (Why / Scope / Acceptance / Out of
   Scope / Parent / Audit / TODO / 관계) with `--reason` preserved
   verbatim inside an `> [!IMPORTANT]` callout block.
4. Pre-validates labels and milestone via `gh label list` / `gh api
   /milestones`. Missing → stop (never auto-create).
5. Creates the new SSOT issue on the target remote, then posts a backlink
   comment on `--parent` (if set).
6. Reports the new issue number, URL, bucket counts, and gap matrix, plus
   a `Next: /gh-issue-flow <N>` hint (unless `--no-next-hint` is set).

## What the skill will NOT do

- **Mutate the source PR.** Read-only. Never `gh pr edit`, never `gh pr
  comment`, never add labels to the PR.
- **Auto-create missing labels.** Pre-validates via `gh label list` and
  stops with the missing list. Memory: `feedback_gh_label_no_autocreate.md`.
- **Continue without `--reason`.** Empty / shorter than 10 chars → exit 2.
- **Silently fall back when `--remote <name>` is missing.** Stops with
  the remote list.
- **Register a stub issue when there is no gap.** If every SSOT section
  comes back `(none)`, exits 4 and recommends a normal review.
- **Override an existing SSOT linkage silently.** When the PR already
  links to a PRD/TRD-bearing issue, exits 3 unless `--force-overlap` is set.

## Prerequisites

- A `gh` CLI authenticated against the target remote's host.
- The PR is `OPEN` or `MERGED` — `CLOSED (unmerged)` PRs are refused.
- Labels in `--label` already exist on the target repo. Run a `--dry-run`
  first to inspect what labels the rendered body will need.
- For `--parent` backlink: the parent issue exists on the target repo.

## Pairs with

- `/gh-issue-flow <N>` — the natural next step once the SSOT issue is
  registered. Drives the full Issue → 구현 → PR loop.
- `/devx:exception-merge-checklist` (TODO, 별도 이슈) — sister exit-side
  skill. Together they form the exception-PR roundtrip: entry
  (reverse-engineer SSOT) + exit (merge gate).

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success (issue created, or `--dry-run` draft written). |
| 2 | `--reason` missing / shorter than 10 chars. |
| 3 | PR already linked to PRD/TRD-bearing issue (use `--force-overlap`). |
| 4 | Every SSOT gap section is `(none)` — recommend a normal review. |
| 1 | All other failures (missing remote, missing label, `gh` error). |
