# Issue Body Template — 8 Sections

The rendered issue body for `/devx:pr-to-ssot-issue` follows this exact
skeleton. Sections are ordered to put the **audit trail** (Section 6)
above the fold for a future reviewer scanning the issue list.

## Title

```
docs(ssot): #<PR#> 역공학 — <PR title (truncated to 60 chars, ellipsis if cut)>
```

The `docs(ssot):` prefix signals that the issue tracks SSOT / contract
recovery, not new feature work. Downstream `/gh-issue-flow` uses this
prefix to route the implementation into docs-only PRs.

## Body skeleton

```markdown
## 1. Why

신규/외부 기여자가 프로젝트의 Issue → PRD → TRD → 구현 → PR 워크플로우를
따르지 않고 PR-first 로 도착했음. 거절 비용 > 복귀 비용 으로 판단되어
역공학으로 SSOT 트랙 복귀를 시도한다.

원본 PR: #<PR#> — <PR title>
PR 상태: <OPEN|MERGED> (merged: <mergedAt or "-">)
PR 작성자: @<author>

## 2. Scope — 4-Bucket 갭 가설

| Bucket | Files | Gap hypothesis |
|--------|-------|----------------|
| code   | <N>   | <one line — from references/gap-detection.md> |
| schema | <N>   | <one line> |
| infra  | <N>   | <one line> |
| docs   | <N>   | <one line> |

### Subagent SSOT 갭 분석

<5 sections verbatim from the subagent — A through E. Empty sections kept as `(none)`.>

### A. Glossary 갭
...

### B. API 계약 갭
...

### C. Data Models 갭
...

### D. Deployment 갭
...

### E. Cross-refs 갭
...

## 3. Acceptance Criteria

<One AC per non-empty gap section. Drop ACs for sections that returned `(none)`.>

- [ ] A. Glossary — <gap 요약> 을 `docs/.ssot/glossary.md` (또는 적절한 위치) 에 반영
- [ ] B. API 계약 — <gap 요약> 을 OpenAPI / GraphQL 스펙에 반영
- [ ] C. Data Models — <gap 요약> 을 데이터 모델 docs 에 반영
- [ ] D. Deployment — <gap 요약> 을 runbook / deployment docs 에 반영
- [ ] E. Cross-refs — 끊어진 link / stale citation 갱신

## 4. Out of Scope

- 원본 PR 의 runtime 코드 변경 (이미 머지/리뷰 완료).
- 신규 기능 추가 — 본 이슈는 **SSOT 동기화** 만 다룬다.
- Sister `/devx:exception-merge-checklist` 가 다루는 merge-gate 검증
  (별도 이슈).

## 5. Parent / Related

- Parent issue: <`#<parent>` 또는 `(none)`>
- Source PR: #<PR#>
- Workflow: Exception PR → SSOT recovery (entry skill: `/devx:pr-to-ssot-issue`)

## 6. Audit

> [!IMPORTANT]
> **Exception 사유 (verbatim from `--reason`):**
>
> <reason text, line-break preserved>
>
> Recorded by: @<current user> on <YYYY-MM-DD>
> Source PR: #<PR#>
> Override flags: <`--force-overlap` if used, otherwise `(none)`>

## 7. TODO 후속

- [ ] AC 별 docs-only PR 작성 (`/gh-issue-flow <이 이슈 번호>` 권장)
- [ ] Sister exit-skill `/devx:exception-merge-checklist` 가 정식 등록되면
      본 이슈에 link
- [ ] (선택) 회고: 어떤 onboarding 자료가 있었다면 PR-first 사고를 막을
      수 있었을지

## 8. 관계 / Cross-refs

<Populated only when `--force-overlap` ran in Step 2.>

- 중복 가능 SSOT issue: #<M> — <issue title>
  - 본 이슈 등록 사유: <간략한 이유. `--reason` 본문에서 발췌 가능>
- 기타 cross-ref: <필요 시 수동 보완>

---

<ai-metrics footer per references/metrics-footer.md>
```

## Field rendering rules

- **`<PR title>`** — truncate at 60 chars. If cut, append `…`. Strip any
  conventional-commit prefix (`feat: `, `fix(api): ` 등) for readability.
- **`<reason text>`** — preserve newlines as-is. Do NOT collapse to a
  single line; the audit block reads best with the user's formatting.
  Quote markdown special chars only when they would break the callout
  block (e.g. a leading `>` becomes `\>`).
- **Empty subagent sections** — keep `(none)` literally. Removing them
  silently hides what was checked.
- **Empty bucket rows** — keep with `0` and `(none)` gap hypothesis.
- **`<current user>`** — from `git config user.name` or `gh api user
  --jq .login`. Fall back to `(unknown)`.

## Why this section order

1. **Why** before **Scope** — a future reviewer needs the motivation
   before the bucket table makes sense.
2. **Subagent gap analysis** lives inside Scope (Section 2) — keeps the
   "what changed" + "what's now stale" reading together.
3. **Acceptance Criteria** before **Out of Scope** — the AC list is the
   actionable surface; Out of Scope is a guardrail.
4. **Audit** (Section 6) is intentionally **below** AC so the AC list
   is what the implementer sees first when picking up the issue, but
   **above** TODO so the audit isn't buried at the bottom.

## Pairs with

- `references/gap-detection.md` — produces the bucket table and the
  5-section subagent report.
- `references/metrics-footer.md` — appended after Section 8.
- `SKILL.md` Step 4 — render order.
