# Gap Detection — 4-Bucket Classification + Subagent Prompt

Substep procedure for Step 2 ("PR Diff Fetch + 4-Bucket Classification")
and Step 3 ("Subagent Gap Analysis").

## Bucket rules

Every file from `gh pr diff <PR#> --name-only` lands in **exactly one**
of the four buckets below. Apply the rules top-to-bottom; the first
match wins.

| Bucket | Match patterns (top-to-bottom precedence) | Gap hypothesis (one line) |
|--------|------------------------------------------|---------------------------|
| **schema** | `migrations/**`, `*.sql`, `schema*.sql`, `openapi*.{yaml,yml,json}`, `*.proto`, `graphql/**`, `**/schema.{ts,py,graphql}`, dataclass / Pydantic / SQLAlchemy model files exported as DB or API contracts | PRD/TRD 의 **Data Models / API 계약** 섹션이 변경 후의 shape 와 일치하는지 확인 필요. |
| **infra** | `.github/workflows/**`, `Dockerfile*`, `docker-compose*.yml`, `Makefile`, `terraform/**`, `helm/**`, `ansible/**`, `.env*` templates, `infra/**`, `deploy/**` | TRD **Deployment / Operations** 섹션의 가정 (env vars, runtime, secrets) 이 변경됐는지 확인 필요. |
| **docs** | `*.md`, `*.rst`, `docs/**`, `README*`, comment-only diffs in code files (no executable change) | 기존 SSOT 문서를 **부분 갱신**했을 가능성 — PRD/TRD 본문이 fragmented 되지 않았는지 cross-ref 확인 필요. |
| **code** | (default — anything not matched above; .py/.ts/.tsx/.go/.rs/.sh/.bash/.zsh/.lua/.js 등 runtime source) | PRD 의 **Goals / Requirements** 와 TRD 의 **Architecture / Components** 가 신규 runtime 동작을 반영하는지 확인 필요. |

### Tie-breaks

- A file matching both `schema` and `code` patterns (예: `models/user.py`
  with API export) → **schema** wins. Schemas are external contracts and
  outrank runtime classification.
- A `*.md` file inside `docs/` that contains an explicit OpenAPI / SQL
  block → stays in **docs**. The block alone doesn't promote it; only
  when paired with a non-doc file in the same PR is the docs change
  treated as a cross-ref hint, not a schema change.
- An `.env.example` template → **infra**, not schema.

## Output shape (Step 2)

The bucket table appears in the rendered issue body as:

```markdown
| Bucket | Files | Gap hypothesis |
|--------|-------|----------------|
| code   | N     | <one line>     |
| schema | N     | <one line>     |
| infra  | N     | <one line>     |
| docs   | N     | <one line>     |
```

Empty buckets show `0` and `(none)` — never dropped from the table.

## Subagent prompt (Step 3)

The subagent receives a self-contained prompt assembled from:

1. **PR meta** — number, title, body (first 2000 chars), base/head ref.
2. **Bucket table** — exactly as rendered above.
3. **Repo SSOT entry points** — paths to `docs/`, `docs/architecture/`,
   `docs/.ssot/` (when present). Use `Glob` to confirm existence; never
   hardcode.
4. **The prompt template below.**

```
You are auditing a GitHub PR whose changes shipped (or are about to
ship) without the project's normal Issue → PRD → TRD → 구현 → PR
workflow. Your job is to identify which sections of the existing PRD /
TRD documents are now **out of sync** with the PR's behavior, so the
human reviewer can patch the SSOT after the fact.

Read every PRD / TRD file under `docs/` (use Read / Glob / Grep). For
each of the five sections below, report:

- **PRESENT** — a one-line description of the gap, naming the file and
  the section that drifts. Concrete only; no speculation.
- **(none)** — there is no gap in this category.

The five sections (keep this exact order in your output):

A. Glossary — new terms / acronyms introduced by the PR that the
   Glossary doesn't define.
B. API 계약 — endpoints, payload shapes, error codes, auth flows that
   the API spec doesn't reflect.
C. Data Models — DB schemas, message envelopes, persisted state that
   the data model docs miss.
D. Deployment — env vars, runtime requirements, secrets, infra topology
   that the deploy / runbook docs miss.
E. Cross-refs — broken links, stale citations, inconsistent feature
   names across documents.

Cap your report at ~300 lines. Use this format verbatim:

    ### A. Glossary 갭
    <one-line per gap, or `(none)`>

    ### B. API 계약 갭
    ...

    ### C. Data Models 갭
    ...

    ### D. Deployment 갭
    ...

    ### E. Cross-refs 갭
    ...

Do NOT propose fixes — the human reviewer decides what to patch. Do NOT
modify any file.
```

## Empty-gap refusal (Step 3)

After the subagent returns, parse each `### <letter>. ...` block.

- If **every** block is exactly `(none)` (whitespace-trimmed) → the
  PR has no SSOT impact worth tracking. Exit 4 with `PR scope too small
  for SSOT gap — recommend a normal review instead`.
- If any block has content → proceed to Step 4 (render body).

## Pairs with

- `references/issue-body-template.md` — where the bucket table and
  five-section gap report appear in the rendered issue.
- `SKILL.md` Step 2 + Step 3 — invocation order.
